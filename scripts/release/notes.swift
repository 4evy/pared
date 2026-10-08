// Extract the requested release's notes from the canonical changelog
import Foundation

do {
  guard CommandLine.arguments.count == 2 else {
    throw NSError(
      domain: "release-notes", code: 1,
      userInfo: [
        NSLocalizedDescriptionKey: "Usage: swift scripts/release/notes.swift VERSION"
      ])
  }
  let version = CommandLine.arguments[1]
  let source = try String(contentsOfFile: "CHANGELOG.md", encoding: .utf8)
  let lines = source.components(separatedBy: "\n")
  guard
    let start = lines.firstIndex(where: {
      $0.hasPrefix("## ")
        && $0.dropFirst(3).split(whereSeparator: { $0.isWhitespace }).first.map(String.init)
          == version
    })
  else {
    throw NSError(
      domain: "release-notes", code: 1,
      userInfo: [
        NSLocalizedDescriptionKey: "CHANGELOG.md needs a release section for \(version)"
      ])
  }
  let end = lines[(start + 1)...].firstIndex(where: { $0.hasPrefix("## ") }) ?? lines.endIndex
  let body = lines[(start + 1)..<end].joined(separator: "\n")
    .trimmingCharacters(in: .whitespacesAndNewlines)
  print("\(lines[start])\n\(body)")
} catch {
  FileHandle.standardError.write(Data("\(error.localizedDescription)\n".utf8))
  exit(1)
}
