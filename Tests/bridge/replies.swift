// bridge.swift compiles this with production reply/profile decoders
import Foundation
import Synchronization

struct CLIError: Error {
  let message: String
  init(_ message: String) { self.message = message }
}

private let messages = Mutex<[String]>([])
func report(_ message: String) {
  messages.withLock { $0.append(message) }
}

private func expectRejected(_ response: NSDictionary) {
  do {
    _ = try DeviceProfileListReply(response)
    fatalError("Accepted malformed profile reply: \(response)")
  } catch {
    precondition(!error.message.isEmpty)
  }
}

private func success(_ body: Any) -> NSDictionary {
  ["__Success__": true, "Response": body]
}

private func profileDecoding() throws {
  let empty = try DeviceProfileListReply(success(["ProfileList": []]))
  precondition(empty.profiles.isEmpty)
  let minimal = ["PayloadIdentifier": "test", "PayloadUUID": "uuid"]
  let populated: [String: Any] = [
    "PayloadIdentifier": "test", "PayloadUUID": "uuid",
    "PayloadContent": [["PayloadType": "example"]],
  ]
  let list = try DeviceProfileListReply(success(["ProfileList": [minimal, populated]]))
  precondition(list.profiles.map(\.payloadCount) == [0, 1])
  for flag in [NSNull(), NSNumber(value: 1), NSNumber(value: 0), "true", [], [:]] as [Any] {
    expectRejected(["__Success__": flag, "Response": ["ProfileList": []]])
  }
  for body in [NSNull(), "wrong", [], [:], ["ProfileList": NSNull()], ["ProfileList": [1]]] as [Any]
  {
    expectRejected(success(body))
  }
  for entry in [
    [:], ["PayloadIdentifier": "test"], ["PayloadUUID": "uuid"],
    ["PayloadIdentifier": 1, "PayloadUUID": "uuid"],
    ["PayloadIdentifier": "test", "PayloadUUID": NSNull()],
    ["PayloadIdentifier": "test", "PayloadUUID": "uuid", "PayloadContent": NSNull()],
    ["PayloadIdentifier": "test", "PayloadUUID": "uuid", "PayloadContent": [1]],
  ] as [[String: Any]] {
    expectRejected(success(["ProfileList": [entry]]))
  }
  for failure in [
    [:], ["domain": "test"], ["domain": 1, "code": 1],
    ["domain": "test", "code": "1"],
  ] as [[String: Any]] {
    expectRejected(["__Success__": false, "__Error__": failure])
  }
  do {
    _ = try DeviceProfileListReply([
      "__Success__": false,
      "__Error__": [
        "domain": "test.daemon", "code": 123,
        "userInfo": [NSLocalizedDescriptionKey: "denied"],
      ],
    ])
    fatalError("Accepted a daemon failure")
  } catch {
    precondition(error.message == "Device profile query failed: test.daemon (123): denied")
  }
  let many = Array(repeating: populated, count: 10_000)
  let decoded = try DeviceProfileListReply(success(["ProfileList": many]))
  precondition(decoded.profiles.count == many.count)
  print("Profile decoder: malformed envelopes, failures, empty lists, 10,000 profiles passed")
}

private func replies() {
  for round in 0..<2_000 {
    let reply = Reply<Int>()
    let accepted = Mutex<[Int]>([])
    let group = DispatchGroup()
    for contender in 0..<8 {
      group.enter()
      DispatchQueue.global().async {
        reply.finish(contender, message: "\(round):\(contender)")
        accepted.withLock { $0.append(contender) }
        group.leave()
      }
    }
    let value = reply.wait(timeout: 5)
    precondition(group.wait(timeout: .now() + 5) == .success)
    precondition(value != nil && accepted.withLock { $0.contains(value!) })
    let log = messages.withLock { value -> [String] in
      let snapshot = value
      value.removeAll(keepingCapacity: true)
      return snapshot
    }
    precondition(log == ["\(round):\(value!)"])
  }
  for _ in 0..<2_000 {
    let reply = Reply<Int>()
    precondition(reply.wait(timeout: 0) == nil)
    DispatchQueue.concurrentPerform(iterations: 8) { index in
      reply.finish(index, message: "late success")
    }
    precondition(reply.wait(timeout: 0) == nil)
    precondition(messages.withLock { $0.isEmpty })
  }
  // Exercise races at the observation deadline without assuming the winner
  for _ in 0..<2_000 {
    let reply = Reply<Int>()
    let group = DispatchGroup()
    group.enter()
    DispatchQueue.global().async {
      reply.finish(7, message: "racing reply")
      group.leave()
    }
    let value = reply.wait(timeout: 0)
    precondition(group.wait(timeout: .now() + 5) == .success)
    let log = messages.withLock { value -> [String] in
      defer { value.removeAll(keepingCapacity: true) }
      return value
    }
    precondition(value == nil ? log.isEmpty : value == 7 && log == ["racing reply"])
  }
  print("Reply coordination: 6,000 rounds, 34,000 callbacks passed")
}

@main
private enum PrivateReplyChecks {
  static func main() throws {
    try profileDecoding()
    replies()
  }
}
