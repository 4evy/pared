import Darwin
import Foundation

struct ModelDirectoryObservation: Equatable {
  let device: dev_t
  let inode: ino_t
  let count: UInt32
  let modifiedSeconds: Int
  let modifiedNanoseconds: Int
  let changedSeconds: Int
  let changedNanoseconds: Int

  init?(_ path: String) {
    var attributes = attrlist()
    attributes.bitmapcount = UInt16(ATTR_BIT_MAP_COUNT)
    attributes.dirattr = attrgroup_t(ATTR_DIR_ENTRYCOUNT)
    struct Entries {
      var length: UInt32 = 0
      var count: UInt32 = 0
    }
    var entries = Entries()
    var metadata = stat()
    guard lstat(path, &metadata) == 0,
      metadata.st_mode & mode_t(S_IFMT) == mode_t(S_IFDIR),
      getattrlist(
        path, &attributes, &entries, MemoryLayout<Entries>.size,
        UInt32(FSOPT_NOFOLLOW)) == 0,
      entries.length == MemoryLayout<Entries>.size
    else { return nil }
    device = metadata.st_dev
    inode = metadata.st_ino
    count = entries.count
    modifiedSeconds = metadata.st_mtimespec.tv_sec
    modifiedNanoseconds = metadata.st_mtimespec.tv_nsec
    changedSeconds = metadata.st_ctimespec.tv_sec
    changedNanoseconds = metadata.st_ctimespec.tv_nsec
  }
}

// APFS exposes entry counts even when model-storage policy denies readdir
// Accept only an empty type directory or its sole empty purpose_auto child
// Other layouts remain unknown rather than inferring absence from denied access
func modelDirectoryIsProvablyEmpty(_ directory: URL) -> Bool {
  guard let before = ModelDirectoryObservation(directory.path) else { return false }
  if before.count == 0 { return true }
  let purpose = directory.appendingPathComponent("purpose_auto", isDirectory: true)
  return before.count == 1 && ModelDirectoryObservation(purpose.path)?.count == 0
    && ModelDirectoryObservation(directory.path) == before
}
