import Darwin
import Foundation

/// Preserves Apple's diagnostic interface and its oneway reply signature
public func paredDiagnosticServiceInterface() -> NSXPCInterface? {
  bridgeServiceInterface(.diagnostic, replyClasses: [[NSString.self], [NSError.self]])
}

/// Returns asset records as JSON, discarding diagnostic preferences,
/// subscriptions, and decryption keys without saving the raw reply
public func paredDiagnosticAssets(
  _ proxy: NSObject, _ completion: @escaping (Data?, Error?) -> Void
) {
  typealias Completion = @convention(block) (NSString?, NSError?) -> Void
  let reply: Completion = { information, error in
    if let error {
      completion(nil, error)
      return
    }
    guard let information, information.length <= 8 * 1024 * 1024,
      let data = (information as String).data(using: .utf8),
      let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
      let assets = object["SystemAssets"] as? [[String: Any]]
    else {
      completion(
        nil,
        NSError(
          domain: "org.pared", code: 69,
          userInfo: [NSLocalizedDescriptionKey: "Unsupported asset diagnostic reply"]))
      return
    }
    let records = assets.compactMap { asset -> [String: Any]? in
      guard let location = asset["location"] as? String,
        var metadata = asset["metadata"] as? [String: Any]
      else { return nil }
      metadata.removeValue(forKey: "ArchiveDecryptionKey")
      return [
        "location": location, "name": asset["name"] as? String ?? "",
        "metadata": metadata,
      ]
    }
    do {
      completion(try JSONSerialization.data(withJSONObject: records), nil)
    } catch { completion(nil, error) }
  }
  typealias Send = @convention(c) (AnyObject, Selector, Completion) -> Void
  let send = unsafeBitCast(
    dlsym(UnsafeMutableRawPointer(bitPattern: -2), "objc_msgSend")!, to: Send.self)
  send(proxy, NSSelectorFromString("diagnosticInformation:"), reply)
}
