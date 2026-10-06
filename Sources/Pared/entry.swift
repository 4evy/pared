import ArgumentParser
import Foundation

public enum ParedMain {
  @MainActor static var updateController: (any ParedUpdateControlling)?

  @MainActor
  public static func main(updater: (any ParedUpdateControlling)? = nil) async {
    updateController = updater
    let arguments = Array(CommandLine.arguments.dropFirst())
    if arguments.isEmpty && Bundle.main.bundleURL.pathExtension == "app" {
      ParedApp.main()
    } else {
      do {
        var command = try ParedCLI.parseAsRoot(arguments)
        if var asyncCommand = command as? AsyncParsableCommand {
          try await asyncCommand.run()
        } else {
          try command.run()
        }
      } catch {
        let code = ParedCLI.exitCode(for: error)
        // Preserve Pared's exit 1 for invalid CLI input
        if code == .validationFailure {
          report(ParedCLI.fullMessage(for: error))
          exit(ExitStatus.failure.rawValue)
        }
        ParedCLI.exit(withError: error)
      }
    }
  }
}
