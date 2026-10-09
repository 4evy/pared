import AssetBridge
import Foundation

// This fetches published metadata only, never __BaseURL / __RelativePath assets
// Matching server fields supplement the broker; they cannot prove local bytes
func modelCatalogMetadata(_ inventory: ModelInventoryReport) async -> ModelInventoryReport {
  var result = inventory
  let assetType = inventory.broker.assetType
  let rows = inventory.broker.reportedAssets
  if rows.isEmpty {
    let complete =
      inventory.broker.directoryListingComplete
      && (inventory.broker.directoryEntries ?? []).allSatisfy { !$0.hasSuffix(".asset") }
    result.catalog.catalogMetadataMatched = complete
    result.catalog.catalogMatchedAssetCount = 0
    if !complete {
      result.catalog.catalogError =
        "The empty broker view does not establish that no assets need matching"
    }
    return result
  }
  do {
    guard let configuration = paredCatalogRequestConfiguration(assetType)
    else { throw CLIError("Apple's catalog configuration or device parameters are unavailable") }
    let catalog = try await paredFetchPublishedCatalog(assetType, configuration: configuration)
    let candidates = Dictionary(
      grouping: catalog.assets.filter { $0.identity.type == assetType }, by: \.identity
    )
    .mapValues { $0.map(\.metadata) }
    var matched = 0
    result.broker.reportedAssets = rows.map { row in
      var row = row
      let metadata = row.metadata
      guard let identity = ParedCatalogAssetIdentity(metadata), identity.type == assetType else {
        row.catalogMatchError = "The broker did not report a complete asset identity"
        return row
      }
      let compatible = (candidates[identity] ?? []).filter { candidate in
        metadata.allSatisfy { key, value in
          // Local usage and experiment annotations can be absent from catalogs
          // Shared fields must match as JSON values, including bool versus
          // number
          guard let actual = candidate[key] else { return true }
          return actual == value
        }
      }
      guard let selected = compatible.first, compatible.allSatisfy({ selected == $0 }) else {
        row.catalogMatchError =
          "No unique published metadata matches the exact asset identity and every shared broker field"
        return row
      }
      row.catalogMetadata = selected
      row.catalogUncomparedBrokerFields = metadata.keys.filter { selected[$0] == nil }.sorted()
      matched += 1
      return row
    }
    result.catalog.catalogMetadataMatched = matched == rows.count
    result.catalog.catalogMatchedAssetCount = matched
    result.catalog.catalogSource = configuration.endpoint.absoluteString
    result.catalog.catalogAssetSetID = catalog.assetSetID
    result.catalog.catalogPostingDate = catalog.postingDate
    result.catalog.catalogMetadataSource =
      "Apple's published catalog matched to daemon-reported installed assets; not local file contents"
    if matched != rows.count {
      result.catalog.catalogError =
        "Some installed assets have no unique compatible catalog metadata"
    }
    return result
  } catch {
    result.catalog.catalogError = error.localizedDescription
    return result
  }
}
