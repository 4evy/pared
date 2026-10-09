import Darwin
import Foundation

// Darwin's private proc_pidinfo flavors 17 and 18 share these ABI layouts
// Source: https://github.com/apple-oss-distributions/xnu/blob/main/bsd/sys/proc_info_private.h
private enum ProcessInfoFlavor: Int32 {
  case uniqueIdentifier = 17
  case bsdWithUniqueIdentifier = 18
}

private struct ParedUniqueProcessInfo {
  var uuid: uuid_t = (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0)
  var uniqueID: UInt64 = 0
  var parentUniqueID: UInt64 = 0
  var version: Int32 = 0
  var originalParentVersion: Int32 = 0
  var reserved: (UInt64, UInt64) = (0, 0)
}

private struct ParedBSDUniqueProcessInfo {
  var bsd = proc_bsdinfo()
  var unique = ParedUniqueProcessInfo()
}

private let processLayoutIsValid =
  MemoryLayout<ParedUniqueProcessInfo>.size == 56
  && MemoryLayout<ParedUniqueProcessInfo>.offset(of: \.version) == 32
  && MemoryLayout<ParedUniqueProcessInfo>.offset(of: \.reserved) == 40
  && MemoryLayout<ParedBSDUniqueProcessInfo>.offset(of: \.unique)
    == MemoryLayout<proc_bsdinfo>.stride
  && MemoryLayout<ParedBSDUniqueProcessInfo>.size
    == MemoryLayout<proc_bsdinfo>.stride + 56

private func processError(_ error: BridgeError, _ code: Int32) {
  error?.pointee = NSError(domain: NSPOSIXErrorDomain, code: Int(code))
}

@_cdecl("ParedProcessVersions")
public func bridgeProcessVersions() -> NSDictionary {
  paredProcessVersions() as NSDictionary
}

/// Captures process versions before an open-file inspection
/// Missing entries mean the process was not observable in this snapshot
public func paredProcessVersions() -> [Int32: UInt32] {
  guard processLayoutIsValid else { return [:] }
  let count = proc_listallpids(nil, 0)
  guard count > 0, count <= 100_000 else { return [:] }
  var pids = [pid_t](repeating: 0, count: Int(count) + 64)
  let found = pids.withUnsafeMutableBytes { proc_listallpids($0.baseAddress, Int32($0.count)) }
  var versions: [Int32: UInt32] = [:]
  for pid in pids.prefix(max(0, min(Int(found), pids.count))) where pid > 1 && pid != getpid() {
    var info = ParedUniqueProcessInfo()
    let size = Int32(MemoryLayout.size(ofValue: info))
    if proc_pidinfo(pid, ProcessInfoFlavor.uniqueIdentifier.rawValue, 0, &info, size) == size {
      versions[pid] = UInt32(bitPattern: info.version)
    }
  }
  return versions
}

@_cdecl("ParedInspectProcess")
public func paredInspectProcess(_ pid: Int32, _ error: AutoreleasingUnsafeMutablePointer<NSError?>?)
  -> ParedProcessIdentity?
{
  guard processLayoutIsValid, pid > 1, pid != getpid() else {
    processError(error, EINVAL)
    return nil
  }
  var info = ParedBSDUniqueProcessInfo()
  let size = Int32(MemoryLayout.size(ofValue: info))
  let bytes = proc_pidinfo(pid, ProcessInfoFlavor.bsdWithUniqueIdentifier.rawValue, 0, &info, size)
  guard bytes == size, info.bsd.pbi_pid == UInt32(pid) else {
    processError(error, bytes <= 0 ? errno : EINVAL)
    return nil
  }
  // Bind the executable lookup to this PID version, preventing PID reuse races
  var token = audit_token_t()
  token.val.5 = UInt32(pid)
  token.val.7 = UInt32(bitPattern: info.unique.version)
  var path = [CChar](repeating: 0, count: 4 * Int(MAXPATHLEN))
  let pathBytes = path.withUnsafeMutableBytes {
    proc_pidpath_audittoken(&token, $0.baseAddress, UInt32($0.count))
  }
  guard pathBytes > 0 else {
    processError(error, errno)
    return nil
  }
  // libproc returns strlen(buffer); decode only those bytes and check the NUL
  guard Int(pathBytes) < path.count, path[Int(pathBytes)] == 0,
    let executable = path.withUnsafeBytes({
      String(validating: $0.prefix(Int(pathBytes)), as: UTF8.self)
    }),
    !executable.isEmpty
  else {
    processError(error, EINVAL)
    return nil
  }
  return ParedProcessIdentity(
    pid: pid, version: UInt32(bitPattern: info.unique.version), uid: info.bsd.pbi_uid,
    executable: executable)
}

@_cdecl("ParedForceQuitProcess")
public func bridgeForceQuitProcess(
  _ pid: Int32, _ version: UInt32, _ uid: UInt32, _ executable: NSString,
  _ error: AutoreleasingUnsafeMutablePointer<NSError?>?
) -> Bool {
  guard let current = paredInspectProcess(pid, error) else { return false }
  guard current.version == version, current.uid == uid,
    (current.executable as NSString).isEqual(executable)
  else {
    processError(error, ESRCH)
    return false
  }
  var token = audit_token_t()
  token.val.5 = UInt32(pid)
  token.val.7 = version
  // This API returns the error code directly rather than a -1 sentinel
  let signalError = proc_signal_with_audittoken(&token, SIGKILL)
  guard signalError == 0 else {
    processError(error, signalError)
    return false
  }
  return true
}

/// Rechecks identity, then sends SIGKILL with kernel PID-version validation
public func paredForceQuitProcess(
  _ pid: Int32, _ version: UInt32, _ uid: UInt32, _ executable: String,
  _ error: AutoreleasingUnsafeMutablePointer<NSError?>?
) -> Bool {
  bridgeForceQuitProcess(pid, version, uid, executable as NSString, error)
}
