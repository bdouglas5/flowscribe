import Foundation

struct AIModelAsset: Hashable, Codable {
    let path: String
    let sizeBytes: Int64
    let checksum: String
}

struct AIModelDescriptor: Identifiable, Hashable, Codable {
    let id: String
    let displayName: String
    let providerID: String
    let revision: String
    let estimatedDownloadSizeBytes: Int64
    let estimatedMemoryBytes: Int64
    let notes: String
    let assetFiles: [AIModelAsset]

    var totalBytes: Int64 {
        assetFiles.reduce(0) { $0 + $1.sizeBytes }
    }

    func remoteURL(for asset: AIModelAsset) -> URL {
        URL(
            string: "https://huggingface.co/\(providerID)/resolve/\(revision)/\(asset.path)"
        )!
    }
}

enum AIModelCatalogError: LocalizedError {
    case missingManifest(String)
    case invalidManifest(String, Error)

    var errorDescription: String? {
        switch self {
        case .missingManifest(let manifestName):
            "Missing bundled AI model manifest: \(manifestName).json"
        case .invalidManifest(let manifestName, let error):
            "Invalid bundled AI model manifest \(manifestName).json: \(error.localizedDescription)"
        }
    }
}

enum AIModelCatalog {
    static let manifestDirectory = "AIModels"
    static let localGemmaManifestName = "gemma-e4b-4bit"

    private static let manifestNames = [localGemmaManifestName]
    private static let fallbackDefaultModel = AIModelDescriptor(
        id: "gemma-e4b-4bit-local",
        displayName: "Gemma 4 E4B (4-bit)",
        providerID: "unsloth/gemma-4-E4B-it-UD-MLX-4bit",
        revision: "52a9e17e759f23e63acf486834de990060319265",
        estimatedDownloadSizeBytes: 5_625_005_881,
        estimatedMemoryBytes: 5_368_709_120,
        notes: "Default local Gemma 4 E4B model for Apple Silicon.",
        assetFiles: []
    )

    private static let bundledCatalogLoadResult: Result<[AIModelDescriptor], AIModelCatalogError> = {
        do {
            return .success(try loadDescriptors(from: .main))
        } catch let error as AIModelCatalogError {
            return .failure(error)
        } catch {
            return .failure(.invalidManifest(localGemmaManifestName, error))
        }
    }()

    static var loadError: AIModelCatalogError? {
        guard case .failure(let error) = bundledCatalogLoadResult else { return nil }
        return error
    }

    static var all: [AIModelDescriptor] {
        (try? bundledCatalogLoadResult.get()) ?? [fallbackDefaultModel]
    }

    static var defaultModel: AIModelDescriptor {
        all.first ?? fallbackDefaultModel
    }

    static func descriptor(for id: String?) -> AIModelDescriptor {
        guard let id else { return defaultModel }
        return all.first(where: { $0.id == id }) ?? defaultModel
    }

    static func loadDescriptors(from bundle: Bundle) throws -> [AIModelDescriptor] {
        try manifestNames.map { manifestName in
            let manifestURL = try manifestURL(named: manifestName, in: bundle)
            return try descriptor(from: manifestURL, manifestName: manifestName)
        }
    }

    static func descriptor(from manifestURL: URL) throws -> AIModelDescriptor {
        try descriptor(from: manifestURL, manifestName: manifestURL.deletingPathExtension().lastPathComponent)
    }

    private static func manifestURL(named manifestName: String, in bundle: Bundle) throws -> URL {
        if let manifestURL = bundle.url(
            forResource: manifestName,
            withExtension: "json",
            subdirectory: manifestDirectory
        ) {
            return manifestURL
        }

        if let manifestURL = bundle.url(
            forResource: manifestName,
            withExtension: "json"
        ) {
            return manifestURL
        }

        throw AIModelCatalogError.missingManifest(manifestName)
    }

    private static func descriptor(from manifestURL: URL, manifestName: String) throws -> AIModelDescriptor {
        do {
            let data = try Data(contentsOf: manifestURL)
            return try JSONDecoder().decode(AIModelDescriptor.self, from: data)
        } catch {
            throw AIModelCatalogError.invalidManifest(manifestName, error)
        }
    }
}
