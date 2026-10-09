import Darwin
import Foundation

struct ModelDirectoryObservation: Equatable {
  let count: UInt32
  private let metadata: Metadata

  private struct Metadata: Equatable {
    let device: dev_t
    let inode: ino_t
    let modifiedSeconds: Int
    let modifiedNanoseconds: Int
    let changedSeconds: Int
    let changedNanoseconds: Int

    init?(_ path: String) {
      var metadata = stat()
      guard lstat(path, &metadata) == 0,
        metadata.st_mode & mode_t(S_IFMT) == mode_t(S_IFDIR)
      else { return nil }
      device = metadata.st_dev
      inode = metadata.st_ino
      modifiedSeconds = metadata.st_mtimespec.tv_sec
      modifiedNanoseconds = metadata.st_mtimespec.tv_nsec
      changedSeconds = metadata.st_ctimespec.tv_sec
      changedNanoseconds = metadata.st_ctimespec.tv_nsec
    }
  }

  init?(_ path: String) {
    var attributes = attrlist()
    attributes.bitmapcount = UInt16(ATTR_BIT_MAP_COUNT)
    attributes.dirattr = attrgroup_t(ATTR_DIR_ENTRYCOUNT)
    struct Entries {
      var length: UInt32 = 0
      var count: UInt32 = 0
    }
    var entries = Entries()
    guard let before = Metadata(path),
      getattrlist(
        path, &attributes, &entries, MemoryLayout<Entries>.size,
        UInt32(FSOPT_NOFOLLOW)) == 0,
      entries.length == MemoryLayout<Entries>.size, Metadata(path) == before
    else { return nil }
    metadata = before
    count = entries.count
  }
}

// APFS exposes entry counts even when model-storage policy denies readdir
// Accept only an empty type directory or its sole empty purpose_auto child
// Other layouts remain unknown rather than inferring absence from denied access
func modelDirectoryIsProvablyEmpty(_ directory: URL) -> Bool {
  guard let before = ModelDirectoryObservation(directory.path) else { return false }
  if before.count == 0 { return ModelDirectoryObservation(directory.path) == before }
  let purpose = directory.appendingPathComponent("purpose_auto", isDirectory: true)
  guard before.count == 1, let childBefore = ModelDirectoryObservation(purpose.path),
    childBefore.count == 0
  else { return false }
  return ModelDirectoryObservation(purpose.path) == childBefore
    && ModelDirectoryObservation(directory.path) == before
}
