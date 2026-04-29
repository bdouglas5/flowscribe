import AppKit
import CryptoKit
import Foundation
import Network
import Security

@Observable
@MainActor
final class SpotifyAuthService {
    private(set) var isAuthenticated = false
    private(set) var isAuthenticating = false
    private(set) var currentUser: SpotifyUser?
    private(set) var lastError: String?

    private var accessToken: String?
    private var refreshToken: String?
    private var tokenExpiresAt: Date?

    private let keychainService = "com.scribeosaur.spotify"
    private let keychainAccessTokenKey = "accessToken"
    private let keychainRefreshTokenKey = "refreshToken"
    private let keychainExpiresAtKey = "tokenExpiresAt"

    private static let callbackPort: UInt16 = 19836
    private static let redirectURI = "http://127.0.0.1:19836/callback"

    var clientID: String?

    var userCountry: String? {
        currentUser?.country
    }

    var statusLabel: String {
        if isAuthenticating { return "Connecting..." }
        if isAuthenticated, let user = currentUser {
            return user.displayName ?? user.id
        }
        if isAuthenticated { return "Connected" }
        return "Not connected"
    }

    init() {
        loadTokensFromKeychain()
    }

    // MARK: - Public API

    func authorize(clientID: String) async {
        self.clientID = clientID
        isAuthenticating = true
        lastError = nil

        do {
            let codeVerifier = generateCodeVerifier()
            let codeChallenge = generateCodeChallenge(from: codeVerifier)
            let state = UUID().uuidString
            let scopes = "user-library-read user-read-playback-position user-read-private"

            var components = URLComponents(string: "https://accounts.spotify.com/authorize")!
            components.queryItems = [
                URLQueryItem(name: "client_id", value: clientID),
                URLQueryItem(name: "response_type", value: "code"),
                URLQueryItem(name: "redirect_uri", value: Self.redirectURI),
                URLQueryItem(name: "scope", value: scopes),
                URLQueryItem(name: "state", value: state),
                URLQueryItem(name: "code_challenge_method", value: "S256"),
                URLQueryItem(name: "code_challenge", value: codeChallenge),
            ]

            guard let authURL = components.url else {
                throw SpotifyServiceError.authorizationFailed("Could not build authorization URL")
            }

            let result = try await startLoopbackServer(then: {
                NSWorkspace.shared.open(authURL)
            })

            guard result.state == state else {
                throw SpotifyServiceError.authorizationFailed("State mismatch")
            }

            let tokenResponse = try await exchangeCode(
                code: result.code,
                codeVerifier: codeVerifier,
                redirectURI: Self.redirectURI,
                clientID: clientID
            )

            applyTokenResponse(tokenResponse)
            saveTokensToKeychain()

            let user = try await fetchCurrentUser()
            currentUser = user
            isAuthenticated = true
            isAuthenticating = false

            AppLogger.info("SpotifyAuth", "Authorized as \(user.displayName ?? user.id)")
        } catch {
            isAuthenticating = false
            lastError = error.localizedDescription
            AppLogger.error("SpotifyAuth", "Authorization failed: \(error.localizedDescription)")
        }
    }

    func disconnect() {
        accessToken = nil
        refreshToken = nil
        tokenExpiresAt = nil
        currentUser = nil
        isAuthenticated = false
        deleteKeychainTokens()
        AppLogger.info("SpotifyAuth", "Disconnected")
    }

    /// Returns a valid access token, refreshing if necessary.
    func validAccessToken() async throws -> String {
        guard let refreshToken else {
            throw SpotifyServiceError.notAuthenticated
        }

        if let token = accessToken, let expiresAt = tokenExpiresAt, Date() < expiresAt.addingTimeInterval(-60) {
            return token
        }

        guard let clientID else {
            throw SpotifyServiceError.clientIDMissing
        }

        AppLogger.info("SpotifyAuth", "Refreshing access token")
        let tokenResponse = try await refreshAccessToken(refreshToken: refreshToken, clientID: clientID)
        applyTokenResponse(tokenResponse)
        saveTokensToKeychain()
        return tokenResponse.accessToken
    }

    func restoreSession(clientID: String) async {
        self.clientID = clientID
        guard refreshToken != nil else { return }

        do {
            let token = try await validAccessToken()
            accessToken = token
            let user = try await fetchCurrentUser()
            currentUser = user
            isAuthenticated = true
            AppLogger.info("SpotifyAuth", "Session restored for \(user.displayName ?? user.id)")
        } catch {
            AppLogger.error("SpotifyAuth", "Session restore failed: \(error.localizedDescription)")
            isAuthenticated = false
        }
    }

    // MARK: - PKCE Helpers

    private func generateCodeVerifier() -> String {
        var bytes = [UInt8](repeating: 0, count: 64)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        return Data(bytes)
            .base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    private func generateCodeChallenge(from verifier: String) -> String {
        let data = Data(verifier.utf8)
        let hash = SHA256.hash(data: data)
        return Data(hash)
            .base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    // MARK: - Loopback Callback Server

    /// Starts a local HTTP server on port 19836, executes `onReady` (to open the browser),
    /// then waits for Spotify to redirect back with an authorization code.
    private nonisolated func startLoopbackServer(
        then onReady: @MainActor @Sendable @escaping () -> Void
    ) async throws -> (code: String, state: String) {
        guard let port = NWEndpoint.Port(rawValue: Self.callbackPort) else {
            throw SpotifyServiceError.authorizationFailed("Invalid callback port")
        }

        let listener = try NWListener(using: .tcp, on: port)
        let queue = DispatchQueue(label: "spotify-auth-callback")

        return try await withCheckedThrowingContinuation { continuation in
            var resumed = false

            // Timeout after 120 seconds
            queue.asyncAfter(deadline: .now() + 120) {
                guard !resumed else { return }
                resumed = true
                listener.cancel()
                continuation.resume(
                    throwing: SpotifyServiceError.authorizationFailed("Authorization timed out")
                )
            }

            listener.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    Task { @MainActor in onReady() }
                case .failed(let error):
                    guard !resumed else { return }
                    resumed = true
                    listener.cancel()
                    continuation.resume(
                        throwing: SpotifyServiceError.authorizationFailed(
                            "Callback server failed: \(error.localizedDescription)"
                        )
                    )
                default:
                    break
                }
            }

            listener.newConnectionHandler = { connection in
                connection.start(queue: queue)
                connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { data, _, _, error in
                    defer { listener.cancel() }
                    guard !resumed else { return }

                    if let error {
                        resumed = true
                        continuation.resume(
                            throwing: SpotifyServiceError.authorizationFailed(
                                "Connection error: \(error.localizedDescription)"
                            )
                        )
                        return
                    }

                    guard let data, let request = String(data: data, encoding: .utf8) else {
                        resumed = true
                        continuation.resume(
                            throwing: SpotifyServiceError.authorizationFailed("No data received from callback")
                        )
                        return
                    }

                    // Parse: "GET /callback?code=...&state=... HTTP/1.1\r\n..."
                    guard let firstLine = request.split(separator: "\r\n").first,
                          let pathPart = firstLine.split(separator: " ").dropFirst().first,
                          let urlComponents = URLComponents(string: String(pathPart))
                    else {
                        Self.sendHTTPResponse(
                            connection: connection,
                            body: "<h2>Authorization Failed</h2><p>Could not parse callback.</p>"
                        )
                        resumed = true
                        continuation.resume(
                            throwing: SpotifyServiceError.authorizationFailed("Invalid callback response")
                        )
                        return
                    }

                    let queryItems = urlComponents.queryItems ?? []

                    if let code = queryItems.first(where: { $0.name == "code" })?.value,
                       let state = queryItems.first(where: { $0.name == "state" })?.value {
                        Self.sendHTTPResponse(
                            connection: connection,
                            body: "<h2>Authorization Complete</h2><p>You can close this tab and return to Scribeosaur.</p>"
                        )
                        resumed = true
                        continuation.resume(returning: (code: code, state: state))
                    } else {
                        let spotifyError = queryItems.first(where: { $0.name == "error" })?.value
                            ?? "Missing code in callback"
                        Self.sendHTTPResponse(
                            connection: connection,
                            body: "<h2>Authorization Failed</h2><p>\(spotifyError)</p>"
                        )
                        resumed = true
                        continuation.resume(
                            throwing: SpotifyServiceError.authorizationFailed(spotifyError)
                        )
                    }
                }
            }

            listener.start(queue: queue)
        }
    }

    private nonisolated static func sendHTTPResponse(connection: NWConnection, body: String) {
        let html = "<html><body style=\"font-family:system-ui;text-align:center;padding:2em\">\(body)</body></html>"
        let response = "HTTP/1.1 200 OK\r\nContent-Type: text/html; charset=utf-8\r\nConnection: close\r\n\r\n\(html)"
        connection.send(
            content: response.data(using: .utf8),
            completion: .contentProcessed { _ in connection.cancel() }
        )
    }

    // MARK: - Token Exchange

    private func exchangeCode(
        code: String,
        codeVerifier: String,
        redirectURI: String,
        clientID: String
    ) async throws -> SpotifyTokenResponse {
        var request = URLRequest(url: URL(string: "https://accounts.spotify.com/api/token")!)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")

        let body = [
            "grant_type": "authorization_code",
            "code": code,
            "redirect_uri": redirectURI,
            "client_id": clientID,
            "code_verifier": codeVerifier,
        ]
        request.httpBody = body.map { "\($0.key)=\($0.value.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? $0.value)" }
            .joined(separator: "&")
            .data(using: .utf8)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            let body = String(data: data, encoding: .utf8) ?? ""
            throw SpotifyServiceError.authorizationFailed("Token exchange failed: \(body)")
        }

        return try JSONDecoder().decode(SpotifyTokenResponse.self, from: data)
    }

    private func refreshAccessToken(refreshToken: String, clientID: String) async throws -> SpotifyTokenResponse {
        var request = URLRequest(url: URL(string: "https://accounts.spotify.com/api/token")!)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")

        let body = [
            "grant_type": "refresh_token",
            "refresh_token": refreshToken,
            "client_id": clientID,
        ]
        request.httpBody = body.map { "\($0.key)=\($0.value.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? $0.value)" }
            .joined(separator: "&")
            .data(using: .utf8)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            throw SpotifyServiceError.tokenRefreshFailed
        }

        return try JSONDecoder().decode(SpotifyTokenResponse.self, from: data)
    }

    private func applyTokenResponse(_ response: SpotifyTokenResponse) {
        accessToken = response.accessToken
        tokenExpiresAt = Date().addingTimeInterval(TimeInterval(response.expiresIn))
        if let newRefresh = response.refreshToken {
            refreshToken = newRefresh
        }
    }

    // MARK: - User Profile

    private func fetchCurrentUser() async throws -> SpotifyUser {
        guard let token = accessToken else { throw SpotifyServiceError.notAuthenticated }

        var request = URLRequest(url: URL(string: "https://api.spotify.com/v1/me")!)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            throw SpotifyServiceError.apiError(
                (response as? HTTPURLResponse)?.statusCode ?? 0,
                String(data: data, encoding: .utf8) ?? ""
            )
        }

        return try JSONDecoder().decode(SpotifyUser.self, from: data)
    }

    // MARK: - Keychain

    private func saveTokensToKeychain() {
        if let accessToken {
            setKeychainValue(accessToken, forKey: keychainAccessTokenKey)
        }
        if let refreshToken {
            setKeychainValue(refreshToken, forKey: keychainRefreshTokenKey)
        }
        if let expiresAt = tokenExpiresAt {
            setKeychainValue(String(expiresAt.timeIntervalSince1970), forKey: keychainExpiresAtKey)
        }
    }

    private func loadTokensFromKeychain() {
        accessToken = getKeychainValue(forKey: keychainAccessTokenKey)
        refreshToken = getKeychainValue(forKey: keychainRefreshTokenKey)
        if let expiresString = getKeychainValue(forKey: keychainExpiresAtKey),
           let interval = Double(expiresString) {
            tokenExpiresAt = Date(timeIntervalSince1970: interval)
        }
    }

    private func deleteKeychainTokens() {
        deleteKeychainValue(forKey: keychainAccessTokenKey)
        deleteKeychainValue(forKey: keychainRefreshTokenKey)
        deleteKeychainValue(forKey: keychainExpiresAtKey)
    }

    private func setKeychainValue(_ value: String, forKey key: String) {
        let data = Data(value.utf8)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: key,
        ]
        SecItemDelete(query as CFDictionary)

        var addQuery = query
        addQuery[kSecValueData as String] = data
        SecItemAdd(addQuery as CFDictionary, nil)
    }

    private func getKeychainValue(forKey key: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess, let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    private func deleteKeychainValue(forKey key: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: key,
        ]
        SecItemDelete(query as CFDictionary)
    }
}
