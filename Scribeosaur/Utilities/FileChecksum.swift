import CryptoKit
import Foundation

enum FileChecksum {
    enum Algorithm {
        case sha1
        case sha256

        static func fromDigestString(_ digest: String) -> Algorithm {
            digest.count == 40 ? .sha1 : .sha256
        }
    }

    static func matches(url: URL, expectedDigest: String) throws -> Bool {
        let digest = try digest(for: url, expectedDigest: expectedDigest)
        return digest.caseInsensitiveCompare(expectedDigest) == .orderedSame
    }

    static func digest(for url: URL, expectedDigest: String) throws -> String {
        let algorithm = Algorithm.fromDigestString(expectedDigest)
        return try digest(for: url, algorithm: algorithm)
    }

    static func digest(for url: URL, algorithm: Algorithm) throws -> String {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }

        switch algorithm {
        case .sha1:
            var hasher = Insecure.SHA1()
            while let data = try handle.read(upToCount: 1_048_576), !data.isEmpty {
                hasher.update(data: data)
            }
            return hasher.finalize().map { String(format: "%02x", $0) }.joined()

        case .sha256:
            var hasher = SHA256()
            while let data = try handle.read(upToCount: 1_048_576), !data.isEmpty {
                hasher.update(data: data)
            }
            return hasher.finalize().map { String(format: "%02x", $0) }.joined()
        }
    }
}
