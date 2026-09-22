import Foundation

do {
  exit(try runCLI(Array(CommandLine.arguments.dropFirst())).rawValue)
} catch {
  report("pared: \(error)")
  exit(ExitStatus.failure.rawValue)
}
