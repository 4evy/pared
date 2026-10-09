import Darwin
import Foundation

private typealias GestaltAnswer = @convention(c) (NSString) -> Unmanaged<AnyObject>?

private enum GestaltKey: String {
  case productType = "ProductType"
  case hardwareModel = "HWModelStr"
  case productVersion = "ProductVersion"
  case buildVersion = "BuildVersion"
}

// Keep these images loaded for the lifetime of their registered classes and
// function pointers, taking one loader reference rather than one per query
private let catalogRuntimeAvailable =
  dlopen(
    "/System/Library/PrivateFrameworks/MobileAssetDaemon.framework/MobileAssetDaemon", RTLD_NOW)
  != nil
private let gestaltAnswer: GestaltAnswer? = {
  guard let library = dlopen("/usr/lib/libMobileGestalt.dylib", RTLD_NOW),
    let symbol = dlsym(library, "MGCopyAnswer")
  else { return nil }
  return unsafeBitCast(symbol, to: GestaltAnswer.self)
}()

/// Validated endpoint and complete device parameters for a catalog query
public struct ParedCatalogRequestConfiguration: Sendable {
  public let endpoint: URL
  public let audience: String
  public let productType: String
  public let hardwareModel: String
  public let productVersion: String
  public let buildVersion: String
}

/// Reads the catalog endpoint and nonunique device parameters without starting
/// DownloadManager or requesting any asset downloads
public func paredCatalogRequestConfiguration(_ assetType: String)
  -> ParedCatalogRequestConfiguration?
{
  guard !assetType.isEmpty, catalogRuntimeAvailable,
    let type = NSClassFromString("DownloadManager"),
    let configuration = objectValue(
      type, .catalogConfiguration, assetType as NSString),
    hasMethods(configuration, .catalogConfigurationValues),
    let audience = objectValue(configuration, .uuid) as? String,
    UUID(uuidString: audience) != nil,
    let endpointString = objectValue(configuration, .url) as? String,
    let endpoint = URL(string: endpointString),
    endpoint.scheme == "https", endpoint.path == "/v2/assets",
    ["gdmf.apple.com", "gdmf-ados.apple.com"].contains(endpoint.host ?? ""),
    endpoint.user == nil, endpoint.password == nil, endpoint.port == nil,
    endpoint.query == nil, endpoint.fragment == nil, let answer = gestaltAnswer
  else { return nil }
  func value(_ key: GestaltKey) -> String? {
    guard let value = answer(key.rawValue as NSString)?.takeRetainedValue() as? String,
      !value.isEmpty
    else {
      return nil
    }
    return value
  }
  guard let productType = value(.productType), let hardwareModel = value(.hardwareModel),
    let productVersion = value(.productVersion), let buildVersion = value(.buildVersion)
  else { return nil }
  return ParedCatalogRequestConfiguration(
    endpoint: endpoint, audience: audience, productType: productType,
    hardwareModel: hardwareModel, productVersion: productVersion, buildVersion: buildVersion)
}
