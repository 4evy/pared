import Foundation

// XPC_MDM_PublicProtocol declares ordinary void v32@0:8@16@?24 and carries
// property-list objects, so it needs no UAF subscription-class allowlist
@objc private protocol MDMProfileQuery {
  func publicRequest(_ request: NSDictionary, reply: @escaping (NSDictionary) -> Void)
}

private struct InstalledProfile: Sendable {
  let identifier: String
  let uuid: String
  let payloadCount: Int

  init(metadata: [String: Any]) throws(CLIError) {
    guard let identifier = metadata["PayloadIdentifier"] as? String,
      let uuid = metadata["PayloadUUID"] as? String
    else { throw CLIError("Device profile query failed or returned an unknown format") }
    self.identifier = identifier
    self.uuid = uuid
    // PayloadContent contains payload summaries, not enforced preference values
    // The daemon can omit it for an empty profile; reject malformed content
    if let content = metadata["PayloadContent"] {
      guard let payloads = content as? [NSDictionary] else {
        throw CLIError("Device profile metadata contains an unknown payload format")
      }
      payloadCount = payloads.count
    } else {
      payloadCount = 0
    }
  }
}

private struct DeviceProfileListReply: Sendable {
  let profiles: [InstalledProfile]

  init(_ response: NSDictionary) throws(CLIError) {
    // __Success__ is a CFBoolean and Response contains a ProfileList array
    // A successful empty list means no installed system profiles were returned
    guard let success = response["__Success__"] as? NSNumber,
      CFGetTypeID(success) == CFBooleanGetTypeID()
    else { throw CLIError("Device profile query returned an unknown success flag") }
    // Failures carry a serialized NSError dictionary, not an NSError object
    // Preserve its domain/code and message instead of mistaking it for absence
    guard success.boolValue else {
      guard let failure = response["__Error__"] as? [String: Any],
        let domain = failure["domain"] as? String, let code = failure["code"] as? Int
      else { throw CLIError("Device profile query failed without a supported error record") }
      let info = failure["userInfo"] as? [String: Any]
      let reason =
        (info?[NSLocalizedDescriptionKey] ?? info?[NSDebugDescriptionErrorKey]) as? String
      throw CLIError(
        "Device profile query failed: \(domain) (\(code))\(reason.map { ": \($0)" } ?? "")")
    }
    guard
      let body = response["Response"] as? [String: Any],
      let metadata = body["ProfileList"] as? [[String: Any]]
    else {
      throw CLIError("Device profile query failed or returned an unknown format")
    }
    // Retain only identity and count; discard unrelated profile and payload
    // fields, including installation-source userInfo
    var profiles: [InstalledProfile] = []
    for entry in metadata {
      profiles.append(try InstalledProfile(metadata: entry))
    }
    self.profiles = profiles
  }
}

private enum DeviceProfiles {
  // GetProfileList chooses device or user scope from the server's bootstrap
  // context; this system daemon queries device profiles even for a user client
  static let service = "com.apple.mdmclient.daemon.unrestricted"
  static let timeout: TimeInterval = 10
  // Source can filter by installer; Options can set ManagedOnly and OmitHidden
  // Omit those filters to include manually installed Pared profiles
  static let listRequest = ["Command": "GetProfileList"]
}

private struct ProfileInstallationStatus: Encodable {
  let identifier: String
  let expectedUUID: String
  let installed: Bool
  let installedPayloadCount: Int
  let conflictingProfileIdentifiers: [String]
}

func reportProfileInstallation() throws -> ExitStatus {
  let identifier = ProfileIdentity.identifier
  let uuid = ProfileIdentity.uuid

  // GetProfileList returns installed system profile metadata without private
  // entitlements; it does not report pending profiles or effective settings
  let connection = NSXPCConnection(
    machServiceName: DeviceProfiles.service, options: .privileged)
  connection.remoteObjectInterface = NSXPCInterface(with: MDMProfileQuery.self)
  connection.resume()
  defer { connection.invalidate() }
  let reply = Reply<Result<[InstalledProfile], Error>>()
  guard
    let proxy = connection.remoteObjectProxyWithErrorHandler({ error in
      reply.finish(.failure(error))
    }) as? MDMProfileQuery
  else { throw CLIError("Cannot create the device profile query proxy") }
  proxy.publicRequest(DeviceProfiles.listRequest as NSDictionary) { response in
    reply.finish(Result { try DeviceProfileListReply(response).profiles })
  }
  guard let result = reply.wait(timeout: DeviceProfiles.timeout) else {
    throw CLIError("Device profile query timed out; installation status is unknown")
  }
  let profiles = try result.get()
  // Match the identifier because an older EUVlok profile uses the same UUID
  let match = profiles.first { $0.identifier == identifier }
  let conflicts = profiles.filter {
    $0.identifier != identifier && $0.uuid.caseInsensitiveCompare(uuid) == .orderedSame
  }.map(\.identifier).sorted()
  let status = ProfileInstallationStatus(
    identifier: identifier, expectedUUID: uuid, installed: match != nil,
    installedPayloadCount: match?.payloadCount ?? 0,
    conflictingProfileIdentifiers: conflicts)
  FileHandle.standardOutput.write(try jsonData(status))
  report("Installed metadata does not show policy contents or runtime enforcement.")
  return status.installed ? .success : .failure
}
