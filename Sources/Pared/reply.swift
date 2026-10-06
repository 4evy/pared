import Foundation
import Synchronization

// XPC callbacks can arrive on different queues; keep the result and lock inline
// and accept only the first reply before waking the waiting thread
final class Reply<Value: Sendable>: Sendable {
  private enum State {
    case pending
    case finished(Value)
    case timedOut
  }

  private let done = DispatchSemaphore(value: 0)
  private let result = Mutex<State>(.pending)

  func finish(_ value: Value, message: String? = nil) {
    result.withLock { result in
      guard case .pending = result else { return }
      result = .finished(value)
      if let message { report(message) }
      done.signal()
    }
  }

  func wait(timeout: TimeInterval) -> Value? {
    _ = done.wait(timeout: .now() + timeout)
    return result.withLock { result in
      switch result {
      case .finished(let value): return value
      case .pending:
        // A late callback must not report success after an unknown outcome
        result = .timedOut
        return nil
      case .timedOut: return nil
      }
    }
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
