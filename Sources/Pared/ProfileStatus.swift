import Foundation

@objc private protocol MDMProfileQuery {
  func publicRequest(_ request: NSDictionary, reply: @escaping (NSDictionary) -> Void)
}

private struct InstalledProfile: Sendable {
  let identifier: String
  let uuid: String
  let payloadCount: Int

  init(metadata: [String: Any]) throws {
    guard let identifier = metadata["PayloadIdentifier"] as? String,
      let uuid = metadata["PayloadUUID"] as? String
    else { throw CLIError("Device profile query failed or returned an unknown format") }
    self.identifier = identifier
    self.uuid = uuid
    payloadCount = (metadata["PayloadContent"] as? [Any])?.count ?? 0
  }
}

private enum DeviceProfiles {
  static let service = "com.apple.mdmclient.daemon.unrestricted"
  static let timeout: TimeInterval = 10
  static let listRequest: NSDictionary = ["Command": "GetProfileList"]
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

  // MDMClientXPCMessageHandler_Public dispatches GetProfileList without
  // private entitlements. Use the daemon for our System-scoped profile. This
  // returns installed metadata, not downloaded profiles or enforced values
  // Match identifiers: an older EUVlok profile shares our UUID, not our identity
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
  proxy.publicRequest(DeviceProfiles.listRequest) { response in
    guard (response["__Success__"] as? NSNumber)?.boolValue == true,
      let body = response["Response"] as? [String: Any],
      let profiles = body["ProfileList"] as? [[String: Any]]
    else {
      reply.finish(.failure(CLIError("Device profile query failed or returned an unknown format")))
      return
    }
    // Retain only metadata needed here; unrelated payloads may contain secrets
    reply.finish(Result { try profiles.map(InstalledProfile.init(metadata:)) })
  }
  guard let result = reply.wait(timeout: DeviceProfiles.timeout) else {
    throw CLIError("Device profile query timed out; installation status is unknown")
  }
  let profiles = try result.get()
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
