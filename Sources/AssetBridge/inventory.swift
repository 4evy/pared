import Foundation

/// Preserves Apple's diagnostic interface and its oneway reply signature
public func paredDiagnosticServiceInterface() -> NSXPCInterface? {
  bridgeServiceInterface(.diagnostic, replyClasses: [[NSString.self], [NSError.self]])
}

private struct DiagnosticEnvelope: Decodable {
  let assets: [ParedDiagnosticAsset]

  private enum CodingKeys: String, CodingKey {
    case assets = "SystemAssets"
  }
}

/// Returns typed asset records, discarding diagnostic preferences,
/// subscriptions, and decryption keys without saving the raw reply
public func paredDiagnosticAssets(
  _ service: ParedDiagnosticService,
  _ completion: @escaping @Sendable (Result<[ParedDiagnosticAsset], Error>) -> Void
) {
  guard let proxy = service.proxy(), let dispatcher = bridgeMessageDispatcher(proxy, .diagnostic)
  else {
    completion(
      .failure(
        NSError(
          domain: "org.pared", code: 69,
          userInfo: [NSLocalizedDescriptionKey: "The diagnostic receiver ABI is unavailable"])))
    return
  }
  typealias Completion = @convention(block) (NSString?, NSError?) -> Void
  let reply: Completion = { information, error in
    if let error {
      completion(.failure(error))
      return
    }
    guard let information, information.length <= 8 * 1024 * 1024,
      let data = (information as String).data(using: .utf8)
    else {
      completion(
        .failure(
          NSError(
            domain: "org.pared", code: 69,
            userInfo: [NSLocalizedDescriptionKey: "Unsupported asset diagnostic reply"])))
      return
    }
    do {
      // Decode every record: dropping an unsupported record hides missing
      // assets
      completion(
        .success(try JSONDecoder().decode(DiagnosticEnvelope.self, from: data).assets))
    } catch {
      // Decoder diagnostics can contain raw values from sensitive metadata
      completion(
        .failure(
          NSError(
            domain: "org.pared", code: 69,
            userInfo: [NSLocalizedDescriptionKey: "Unsupported asset diagnostic record"])))
    }
  }
  typealias Send = @convention(c) (AnyObject, Selector, Completion) -> Void
  let send = unsafeBitCast(dispatcher, to: Send.self)
  send(proxy, NSSelectorFromString("diagnosticInformation:"), reply)
}
