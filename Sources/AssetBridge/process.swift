import Darwin
import Foundation

// Darwin's private proc_pidinfo flavors 17 and 18 share these ABI layouts
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

private func processError(_ error: BridgeError, _ code: Int32) {
  error?.pointee = NSError(domain: NSPOSIXErrorDomain, code: Int(code))
}

@_cdecl("ParedProcessVersions")
public func bridgeProcessVersions() -> NSDictionary {
  precondition(MemoryLayout<ParedUniqueProcessInfo>.size == 56)
  let count = proc_listallpids(nil, 0)
  guard count > 0, count <= 100_000 else { return [:] }
  var pids = [pid_t](repeating: 0, count: Int(count) + 64)
  let found = pids.withUnsafeMutableBytes { proc_listallpids($0.baseAddress, Int32($0.count)) }
  var versions: [NSNumber: NSNumber] = [:]
  for pid in pids.prefix(max(0, min(Int(found), pids.count))) where pid > 1 && pid != getpid() {
    var info = ParedUniqueProcessInfo()
    let size = Int32(MemoryLayout.size(ofValue: info))
    if proc_pidinfo(pid, 17, 0, &info, size) == size {
      versions[NSNumber(value: pid)] = NSNumber(value: UInt32(bitPattern: info.version))
    }
  }
  return versions as NSDictionary
}

@_cdecl("ParedInspectProcess")
public func paredInspectProcess(_ pid: Int32, _ error: AutoreleasingUnsafeMutablePointer<NSError?>?)
  -> ParedProcessIdentity?
{
  guard pid > 1, pid != getpid() else {
    processError(error, EINVAL)
    return nil
  }
  var info = ParedBSDUniqueProcessInfo()
  let size = Int32(MemoryLayout.size(ofValue: info))
  let bytes = proc_pidinfo(pid, 18, 0, &info, size)
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
  guard
    let executable = path.withUnsafeBufferPointer({ String(validatingCString: $0.baseAddress!) }),
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

/// Captures process versions before an open-file inspection
public func paredProcessVersions() -> [NSNumber: NSNumber] {
  bridgeProcessVersions() as! [NSNumber: NSNumber]
}

/// Rechecks identity, then sends SIGKILL with kernel PID-version validation
public func paredForceQuitProcess(
  _ pid: Int32, _ version: UInt32, _ uid: UInt32, _ executable: String,
  _ error: AutoreleasingUnsafeMutablePointer<NSError?>?
) -> Bool {
  bridgeForceQuitProcess(pid, version, uid, executable as NSString, error)
}
