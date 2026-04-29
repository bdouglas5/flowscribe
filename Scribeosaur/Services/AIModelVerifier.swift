import Foundation

enum LocalAIProvisioningError: LocalizedError, Equatable {
    case downloadFailed(assetPath: String, reason: String)
    case missingAsset(String)
    case sizeMismatch(assetPath: String, expectedBytes: Int64, actualBytes: Int64)
    case checksumMismatch(assetPath: String, expectedDigest: String, actualDigest: String)
    case verificationRecordInvalid(String)
    case bundledSeedInvalid(String)
    case manifestInvalid(String)

    var errorDescription: String? {
        switch self {
        case .downloadFailed(let assetPath, _):
            "Download failed for \(assetPath)."
        case .missingAsset(let assetPath):
            "Required model file is missing: \(assetPath)."
        case .sizeMismatch(let assetPath, _, _):
            "Downloaded size did not match for \(assetPath)."
        case .checksumMismatch(let assetPath, _, _):
            "Checksum verification failed for \(assetPath)."
        case .verificationRecordInvalid:
            "The local model verification record is invalid."
        case .bundledSeedInvalid:
            "The bundled local model seed is invalid."
        case .manifestInvalid:
            "The bundled local model manifest is invalid."
        }
    }
}

struct VerifiedAIModelRecord: Codable, Equatable {
    let modelID: String
    let revision: String
    let verifiedAt: Date
    let assets: [String: String]
}

struct AIModelVerifier {
    private let fileManager: FileManager

    init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    func currentRecordIfValid(
        for descriptor: AIModelDescriptor,
        verificationFile: URL,
        modelDirectory: URL
    ) throws -> VerifiedAIModelRecord? {
        guard fileManager.fileExists(atPath: verificationFile.path) else {
            return nil
        }

        let data: Data
        do {
            data = try Data(contentsOf: verificationFile)
        } catch {
            throw LocalAIProvisioningError.verificationRecordInvalid(error.localizedDescription)
        }

        let record: VerifiedAIModelRecord
        do {
            record = try JSONDecoder().decode(VerifiedAIModelRecord.self, from: data)
        } catch {
            throw LocalAIProvisioningError.verificationRecordInvalid(error.localizedDescription)
        }

        guard record.modelID == descriptor.id, record.revision == descriptor.revision else {
            return nil
        }

        for asset in descriptor.assetFiles {
            let assetURL = modelDirectory.appendingPathComponent(asset.path)
            guard fileManager.fileExists(atPath: assetURL.path) else {
                return nil
            }

            let recordedDigest = record.assets[asset.path] ?? ""
            guard recordedDigest.caseInsensitiveCompare(asset.checksum) == .orderedSame else {
                return nil
            }

            let actualSize = fileSize(at: assetURL)
            guard actualSize == asset.sizeBytes else {
                return nil
            }
        }

        return record
    }

    func verifyFiles(
        for descriptor: AIModelDescriptor,
        in modelDirectory: URL
    ) throws -> VerifiedAIModelRecord {
        var verifiedAssets: [String: String] = [:]

        for asset in descriptor.assetFiles {
            let assetURL = modelDirectory.appendingPathComponent(asset.path)
            guard fileManager.fileExists(atPath: assetURL.path) else {
                throw LocalAIProvisioningError.missingAsset(asset.path)
            }

            let actualSize = fileSize(at: assetURL)
            guard actualSize == asset.sizeBytes else {
                throw LocalAIProvisioningError.sizeMismatch(
                    assetPath: asset.path,
                    expectedBytes: asset.sizeBytes,
                    actualBytes: actualSize
                )
            }

            let actualDigest = try FileChecksum.digest(for: assetURL, expectedDigest: asset.checksum)
            guard actualDigest.caseInsensitiveCompare(asset.checksum) == .orderedSame else {
                throw LocalAIProvisioningError.checksumMismatch(
                    assetPath: asset.path,
                    expectedDigest: asset.checksum,
                    actualDigest: actualDigest
                )
            }

            verifiedAssets[asset.path] = actualDigest.lowercased()
        }

        return VerifiedAIModelRecord(
            modelID: descriptor.id,
            revision: descriptor.revision,
            verifiedAt: Date(),
            assets: verifiedAssets
        )
    }

    func writeVerificationRecord(_ record: VerifiedAIModelRecord, to verificationFile: URL) throws {
        let recordData = try JSONEncoder().encode(record)
        try recordData.write(to: verificationFile, options: .atomic)
    }

    private func fileSize(at url: URL) -> Int64 {
        let attributes = try? fileManager.attributesOfItem(atPath: url.path)
        return (attributes?[.size] as? NSNumber)?.int64Value ?? 0
    }
}
