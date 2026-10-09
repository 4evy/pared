import Darwin
import Foundation

/// Reads the catalog endpoint and nonunique device parameters without starting
/// DownloadManager or requesting any asset downloads
public func paredCatalogRequestConfiguration(_ assetType: String) -> [String: String]? {
  guard
    dlopen(
      "/System/Library/PrivateFrameworks/MobileAssetDaemon.framework/MobileAssetDaemon", RTLD_NOW)
      != nil,
    let type = NSClassFromString("DownloadManager"),
    hasMethod(type, "pallasConfigurationForAssetType:", .catalogConfiguration),
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
    endpoint.query == nil, endpoint.fragment == nil,
    let gestalt = dlopen("/usr/lib/libMobileGestalt.dylib", RTLD_NOW),
    let symbol = dlsym(gestalt, "MGCopyAnswer")
  else { return nil }
  typealias Answer = @convention(c) (NSString) -> Unmanaged<AnyObject>?
  let answer = unsafeBitCast(symbol, to: Answer.self)
  var result = ["endpoint": endpoint.absoluteString, "AssetAudience": audience]
  for key in ["ProductType", "HWModelStr", "ProductVersion", "BuildVersion"] {
    guard let value = answer(key as NSString)?.takeRetainedValue() as? String,
      !value.isEmpty
    else { return nil }
    result[key] = value
  }
  return result
}
