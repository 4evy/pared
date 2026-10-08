import Foundation

/// Copied identifiers for a downloaded asset
@objc(ParedDownloadedAsset)
public final class ParedDownloadedAsset: NSObject {
  @objc public let assetID: String
  @objc public let assetType: String
  @objc public let assetSpecifier: String
  @objc public let assetVersion: String

  init(id: String, type: String, specifier: String, version: String) {
    assetID = id
    assetType = type
    assetSpecifier = specifier
    assetVersion = version
    super.init()
  }
}

/// A copied snapshot that holds no lock and does not keep asset files available
/// Byte counts do not measure reclaimable disk space
@objc(ParedLocalDownloadStatus)
public final class ParedLocalDownloadStatus: NSObject {
  @objc public let latestDownloadedAtomicInstance: String?
  @objc public let downloadedAssets: [ParedDownloadedAsset]
  @objc public let configuredAssetEntries: UInt
  // Keep Apple's spelling for compatibility with existing output
  @objc public var latestDowloadedAtomicInstanceEntries: UInt { UInt(downloadedAssets.count) }
  @objc public let downloadedNetworkBytes: Int64
  @objc public let downloadedFilesystemBytes: Int64
  @objc public let vendingAtomicInstanceForConfiguredEntries: Bool

  init(
    instance: String?, configured: Int, assets: [ParedDownloadedAsset], network: Int64,
    filesystem: Int64, vending: Bool
  ) {
    latestDownloadedAtomicInstance = instance
    configuredAssetEntries = UInt(configured)
    downloadedAssets = assets
    downloadedNetworkBytes = network
    downloadedFilesystemBytes = filesystem
    vendingAtomicInstanceForConfiguredEntries = vending
    super.init()
  }
}

/// A validated native subscription ready to send through XPC
@objc(ParedAssetSubscription)
public final class ParedAssetSubscription: NSObject {
  // Keep the ivar name used by the diagnostic inspection tool
  @objc private let _native: AnyObject
  @objc let name: NSString
  var native: AnyObject { _native }

  init(native: AnyObject, name: NSString) {
    _native = native
    self.name = name.copy() as! NSString
    super.init()
  }
}

/// A process identity for reviewing and targeting one running instance
@objc(ParedProcessIdentity)
public final class ParedProcessIdentity: NSObject {
  @objc public let pid: Int32
  @objc public let version: UInt32
  @objc public let uid: UInt32
  @objc public let executable: String

  init(pid: Int32, version: UInt32, uid: UInt32, executable: String) {
    self.pid = pid
    self.version = version
    self.uid = uid
    self.executable = executable
    super.init()
  }
}
