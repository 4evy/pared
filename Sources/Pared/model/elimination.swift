import Foundation
import Subprocess

private struct ModelEliminationLog: Decodable {
  let processImagePath: String
  let subsystem: String
  let category: String
  let userID: Int
  let timestamp: Date
  let eventMessage: String
}

struct ModelEliminationEvidence: Sendable {
  let assetTypes: Set<String>

  // Logs describe daemon-managed assets, not an independent folder inventory
  static let confirmation =
    "Apple's asset daemon completed elimination for every selected model type."

  static func parse(_ output: String, since start: Date, assetTypes: Set<String>) -> Self {
    let timestamp = DateFormatter()
    timestamp.locale = Locale(identifier: "en_US_POSIX")
    timestamp.dateFormat = "yyyy-MM-dd HH:mm:ss.SSSSSSZZZ"
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .formatted(timestamp)
    var completed: [String: [UUID: Date]] = [:]
    var reviews: [String: [UUID: (date: Date, empty: Bool)]] = [:]
    for line in output.split(separator: "\n") {
      guard let row = try? decoder.decode(ModelEliminationLog.self, from: Data(line.utf8)),
        row.processImagePath == "/usr/libexec/mobileassetd",
        row.subsystem == "com.apple.mobileassetd",
        row.category == "AutoControl", row.userID == 0, row.timestamp >= start
      else { continue }
      let date = row.timestamp
      let message = row.eventMessage
      guard
        message.contains("requestMessage:MA-AUTO:ELIMINATE_ALL_FOR_ASSET_TYPE["),
        message.contains("assetsubscriptiond:"),
        let match = message.firstMatch(of: #/\|requestUUID:([^|]*)\|/#),
        let request = UUID(uuidString: String(match.1))
      else { continue }
      for type in assetTypes
      where message.contains("assetSelector:type:\(type)|specifier:(null)(any version)") {
        if message.contains(
          "{_eliminateCompleteIfAllDone} [SUCCESS] done with asset-selector elimination"),
          message.contains("|responseError:N|"),
          message.contains("|limitedToCancelActivity:N]")
        {
          completed[type, default: [:]][request] = max(completed[type]?[request] ?? date, date)
        }
        if message.contains(
          "{_removeAllContentForEliminateTracker} reviewed all downloadedDescriptorsBySelector("),
          date >= (reviews[type]?[request]?.date ?? .distantPast)
        {
          // A later review can supersede an earlier empty snapshot
          reviews[type, default: [:]][request] = (
            date: date,
            empty: message.contains("| removeDescriptors:0 | notRemovedStillLocked:0 |")
          )
        }
      }
    }
    return Self(
      assetTypes: Set(
        assetTypes.filter {
          let type = $0
          return reviews[type, default: [:]].contains { request, reviewed in
            reviewed.empty && completed[type]?[request].map { $0 >= reviewed.date } == true
          }
        }))
  }
}

func modelEliminationEvidence(since start: Date, assetTypes: Set<String>)
  -> ModelEliminationEvidence
{
  let reply = Reply<ModelEliminationEvidence>()
  let task = Task.detached {
    do {
      let output = try await withThrowingTaskGroup(of: String.self) { group in
        group.addTask {
          let format = DateFormatter()
          format.locale = Locale(identifier: "en_US_POSIX")
          format.dateFormat = "yyyy-MM-dd HH:mm:ss"
          let result = try await Subprocess.run(
            .path("/usr/bin/log"),
            arguments: [
              "show", "--start", format.string(from: start), "--style", "ndjson",
              "--predicate",
              "process == 'mobileassetd' AND category == 'AutoControl' AND (eventMessage CONTAINS '{_eliminateCompleteIfAllDone} [SUCCESS]' OR eventMessage CONTAINS '{_removeAllContentForEliminateTracker}')",
            ], output: .string(limit: 8 * 1024 * 1024), error: .string(limit: 16 * 1024))
          guard result.terminationStatus.isSuccess else {
            throw CLIError("Asset daemon completion logs are unavailable")
          }
          return result.standardOutput
        }
        group.addTask {
          try await Task.sleep(for: .seconds(8))
          throw CLIError("Reading asset daemon completion logs timed out")
        }
        defer { group.cancelAll() }
        return try await group.next()!
      }
      reply.finish(.parse(output, since: start, assetTypes: assetTypes))
    } catch {
      reply.finish(ModelEliminationEvidence(assetTypes: []))
    }
  }
  defer { task.cancel() }
  return reply.wait(timeout: 10) ?? ModelEliminationEvidence(assetTypes: [])
}
