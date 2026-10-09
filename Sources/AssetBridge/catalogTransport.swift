import Foundation

private func catalogTransportError(_ message: String) -> NSError {
  NSError(domain: "org.pared", code: 69, userInfo: [NSLocalizedDescriptionKey: message])
}

private final class PublishedCatalogRedirects: NSObject, URLSessionTaskDelegate {
  func urlSession(
    _ session: URLSession, task: URLSessionTask,
    willPerformHTTPRedirection response: HTTPURLResponse,
    newRequest request: URLRequest,
    completionHandler: @escaping @Sendable (URLRequest?) -> Void
  ) {
    completionHandler(nil)
  }
}

/// Fetches metadata from the validated Apple endpoint without following
/// redirects
///
/// The response is bounded to 32 MiB and 35 seconds; no asset files are fetched
///
/// HTTPS authenticates the host but does not verify the envelope's independent
/// signature
public func paredFetchPublishedCatalog(
  _ assetType: String, configuration: ParedCatalogRequestConfiguration
) async throws -> ParedPublishedCatalog {
  let limit = 32 * 1024 * 1024
  let body = ParedCatalogRequestBody(assetType: assetType, configuration: configuration)
  var request = URLRequest(url: configuration.endpoint)
  request.httpMethod = "POST"
  request.setValue("application/json", forHTTPHeaderField: "Content-Type")
  request.httpBody = try JSONEncoder().encode(body)
  let settings = URLSessionConfiguration.ephemeral
  settings.httpShouldSetCookies = false
  settings.urlCache = nil
  settings.timeoutIntervalForRequest = 30
  settings.timeoutIntervalForResource = 35
  let session = URLSession(configuration: settings)
  defer { session.invalidateAndCancel() }
  let (bytes, response) = try await session.bytes(
    for: request, delegate: PublishedCatalogRedirects())
  guard let response = response as? HTTPURLResponse else {
    throw catalogTransportError("Apple's catalog request returned an unsupported response")
  }
  guard !(300..<400).contains(response.statusCode) else {
    throw catalogTransportError("Apple's catalog unexpectedly redirected the request")
  }
  guard response.statusCode == 200, response.expectedContentLength <= Int64(limit) else {
    throw catalogTransportError("Apple's catalog request failed or exceeded the size limit")
  }
  var data = Data()
  for try await byte in bytes {
    guard data.count < limit else {
      throw catalogTransportError("Apple's catalog exceeded the 32 MiB size limit")
    }
    data.append(byte)
  }
  return try ParedPublishedCatalog(envelope: data, audience: configuration.audience)
}
