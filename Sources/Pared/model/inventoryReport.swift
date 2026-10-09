import AssetBridge
import Foundation

struct ModelReportedAsset: Encodable, Sendable {
  let location: String
  let name: String
  let metadata: [String: ParedJSONValue]
  var catalogMetadata: [String: ParedJSONValue]?
  var catalogUncomparedBrokerFields: [String]?
  var catalogMatchError: String?

  init(_ asset: ParedDiagnosticAsset) {
    location = asset.location
    name = asset.name
    metadata = asset.metadata
  }
}

struct ModelInventoryReport: Encodable, Sendable {
  struct Broker: Encodable, Sendable {
    let assetType: String
    let directory: String
    let directoryListingComplete: Bool
    let metadataFileContentsComplete = false
    let metadataSource = "Apple asset subscription daemon; not raw file contents"
    let metadataRedactions = ["ArchiveDecryptionKey"]
    var reportedAssets: [ModelReportedAsset]
    let directoryEntries: [String]?
    let diagnosticError: String?
    let inventoryError: String?
  }

  struct PublishedCatalog: Encodable, Sendable {
    var catalogMetadataMatched = false
    var catalogMatchedAssetCount: Int?
    var catalogError: String?
    var catalogSource: String?
    var catalogAssetSetID: String?
    var catalogPostingDate: String?
    var catalogMetadataSource: String?
  }

  var broker: Broker
  var catalog = PublishedCatalog()

  var complete: Bool { broker.directoryListingComplete && catalog.catalogMetadataMatched }

  private enum CodingKeys: String, CodingKey {
    case complete
  }

  func encode(to encoder: any Encoder) throws {
    // Synthesized records share the flat report object; only completeness is
    // derived, so adding evidence fields needs no second serialization list
    try broker.encode(to: encoder)
    try catalog.encode(to: encoder)
    var values = encoder.container(keyedBy: CodingKeys.self)
    try values.encode(complete, forKey: .complete)
  }
}
