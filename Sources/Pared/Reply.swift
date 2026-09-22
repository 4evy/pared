import Foundation
import os

// The transport error handler and reply run on XPC queues. Accept only the
// first result and synchronize access with the waiting main thread
final class Reply<Value: Sendable>: Sendable {
  private let done = DispatchSemaphore(value: 0)
  private let result = OSAllocatedUnfairLock<Value?>(initialState: nil)

  func finish(_ value: Value, message: String? = nil) {
    result.withLock { result in
      guard result == nil else { return }
      result = value
      if let message { report(message) }
      done.signal()
    }
  }

  func wait(timeout: TimeInterval) -> Value? {
    guard done.wait(timeout: .now() + timeout) == .success else { return nil }
    return result.withLock { $0 }
  }
}

extension Reply where Value == ExitStatus {
  func wait() -> ExitStatus {
    guard let result = wait(timeout: UnifiedAssets.replyTimeout) else {
      report(
        "Timed out observing the request; outcome unknown. Inspect daemon logs before retrying")
      return .outcomeUnknown
    }
    return result
  }
}
