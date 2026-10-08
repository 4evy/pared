import AssetBridge
import Foundation
import Synchronization

private final class CatalogResponse: NSObject, URLSessionDataDelegate {
  static let limit = 32 * 1024 * 1024
  let reply = Reply<Result<Data, Error>>()
  private let data = Mutex(Data())

  func urlSession(
    _ session: URLSession, dataTask: URLSessionDataTask, didReceive response: URLResponse,
    completionHandler: @escaping @Sendable (URLSession.ResponseDisposition) -> Void
  ) {
    guard let response = response as? HTTPURLResponse, response.statusCode == 200,
      response.expectedContentLength <= Int64(Self.limit)
    else {
      reply.finish(.failure(CLIError("Apple's catalog request failed or exceeded the size limit")))
      completionHandler(.cancel)
      return
    }
    completionHandler(.allow)
  }

  func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive chunk: Data) {
    let accepted = data.withLock { data in
      guard chunk.count <= Self.limit - data.count else { return false }
      data.append(chunk)
      return true
    }
    if !accepted {
      reply.finish(.failure(CLIError("Apple's catalog exceeded the 32 MiB size limit")))
      dataTask.cancel()
    }
  }

  func urlSession(
    _ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?
  ) {
    if let error {
      reply.finish(.failure(error))
    } else {
      reply.finish(.success(data.withLock { $0 }))
    }
  }

  func urlSession(
    _ session: URLSession, task: URLSessionTask,
    willPerformHTTPRedirection response: HTTPURLResponse,
    newRequest request: URLRequest,
    completionHandler: @escaping @Sendable (URLRequest?) -> Void
  ) {
    reply.finish(.failure(CLIError("Apple's catalog unexpectedly redirected the request")))
    completionHandler(nil)
  }
}

private struct CatalogAssetIdentity: Hashable {
  let type: String
  let specifier: String
  let version: String
  let archive: String

  init?(_ metadata: [String: Any]) {
    guard let type = metadata["AssetType"] as? String,
      let specifier = metadata["AssetSpecifier"] as? String,
      let version = metadata["AssetVersion"] as? String,
      let archive = metadata["ArchiveID"] as? String,
      !type.isEmpty, !specifier.isEmpty, !version.isEmpty, !archive.isEmpty
    else { return nil }
    self.type = type
    self.specifier = specifier
    self.version = version
    self.archive = archive
  }
}

// This fetches published metadata only, never __BaseURL / __RelativePath assets
// Matching server fields supplement the broker; they cannot prove local bytes
func modelCatalogMetadata(_ inventory: [String: Any]) -> (object: [String: Any], complete: Bool) {
  var result = inventory
  result["catalogMetadataMatched"] = false
  guard let assetType = inventory["assetType"] as? String,
    let rows = inventory["reportedAssets"] as? [[String: Any]]
  else {
    result["catalogError"] = "No locally reported assets to match against a published catalog"
    return (result, false)
  }
  if rows.isEmpty {
    let complete =
      inventory["directoryListingComplete"] as? Bool == true
      && (inventory["directoryEntries"] as? [String] ?? []).allSatisfy {
        !$0.hasSuffix(".asset")
      }
    result["catalogMetadataMatched"] = complete
    result["catalogMatchedAssetCount"] = 0
    if !complete {
      result["catalogError"] =
        "The empty broker view does not establish that no assets need matching"
    }
    return (result, complete)
  }
  do {
    guard let configuration = paredCatalogRequestConfiguration(assetType),
      let endpoint = configuration["endpoint"], let url = URL(string: endpoint)
    else { throw CLIError("Apple's catalog configuration or device parameters are unavailable") }
    var body: [String: Any] = configuration.filter { $0.key != "endpoint" }
    body["AssetType"] = assetType
    body["Purpose"] = "auto"
    body["ClientVersion"] = 2
    body["CompatibilityVersion"] = 20
    body["CertIssuanceDay"] = "2023-12-10"
    var request = URLRequest(url: url)
    request.httpMethod = "POST"
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    request.httpBody = try JSONSerialization.data(withJSONObject: body)
    let settings = URLSessionConfiguration.ephemeral
    settings.httpShouldSetCookies = false
    settings.urlCache = nil
    settings.timeoutIntervalForRequest = 30
    settings.timeoutIntervalForResource = 35
    let response = CatalogResponse()
    let session = URLSession(configuration: settings, delegate: response, delegateQueue: nil)
    defer { session.invalidateAndCancel() }
    session.dataTask(with: request).resume()
    guard let reply = response.reply.wait(timeout: 40) else {
      throw CLIError("Apple's catalog request timed out")
    }
    let envelope = try reply.get()
    // Pallas wraps JSON in JWS; HTTPS authenticates the configured Apple host
    // This parser does not claim to verify the envelope's separate signature
    let parts = envelope.split(separator: UInt8(ascii: "."), omittingEmptySubsequences: false)
    guard parts.count == 3, !parts[0].isEmpty, !parts[2].isEmpty,
      let encoded = String(data: parts[1], encoding: .ascii)
    else { throw CLIError("Apple returned an unsupported catalog envelope") }
    var base64 = encoded.replacingOccurrences(of: "-", with: "+")
      .replacingOccurrences(of: "_", with: "/")
    base64 += String(repeating: "=", count: (4 - base64.count % 4) % 4)
    guard let payload = Data(base64Encoded: base64),
      let catalog = try JSONSerialization.jsonObject(with: payload) as? [String: Any],
      catalog["AssetAudience"] as? String == configuration["AssetAudience"],
      let assets = catalog["Assets"] as? [[String: Any]]
    else { throw CLIError("Apple returned an unsupported catalog payload") }
    var candidates: [CatalogAssetIdentity: [[String: Any]]] = [:]
    for var asset in assets {
      asset.removeValue(forKey: "ArchiveDecryptionKey")
      guard let identity = CatalogAssetIdentity(asset), identity.type == assetType else { continue }
      candidates[identity, default: []].append(asset)
    }
    var matched = 0
    let supplemented = rows.map { row -> [String: Any] in
      var row = row
      guard let metadata = row["metadata"] as? [String: Any],
        let identity = CatalogAssetIdentity(metadata), identity.type == assetType
      else {
        row["catalogMatchError"] = "The broker did not report a complete asset identity"
        return row
      }
      let compatible = (candidates[identity] ?? []).filter { candidate in
        metadata.allSatisfy { key, value in
          // The broker adds local usage and experiment annotations that are
          // absent from published catalogs; compare every shared field
          guard let actual = candidate[key] else { return true }
          return NSDictionary(dictionary: [key: value]).isEqual(to: [key: actual])
        }
      }
      guard let selected = compatible.first,
        compatible.allSatisfy({ NSDictionary(dictionary: selected).isEqual(to: $0) })
      else {
        row["catalogMatchError"] =
          "No unique published metadata matches the exact asset identity and every shared broker field"
        return row
      }
      row["catalogMetadata"] = selected
      row["catalogUncomparedBrokerFields"] = metadata.keys.filter { selected[$0] == nil }.sorted()
      matched += 1
      return row
    }
    result["reportedAssets"] = supplemented
    result["catalogMetadataMatched"] = matched == rows.count
    result["catalogMatchedAssetCount"] = matched
    result["catalogSource"] = endpoint
    result["catalogAssetSetID"] = catalog["AssetSetId"]
    result["catalogPostingDate"] = catalog["PostingDate"]
    result["catalogMetadataSource"] =
      "Apple's published catalog matched to daemon-reported installed assets; not local file contents"
    if matched != rows.count {
      result["catalogError"] = "Some installed assets have no unique compatible catalog metadata"
    }
    return (result, matched == rows.count)
  } catch {
    result["catalogError"] = error.localizedDescription
    return (result, false)
  }
}
