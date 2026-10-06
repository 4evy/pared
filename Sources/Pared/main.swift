import Foundation

let arguments = CommandLine.arguments.dropFirst()
if arguments.first == "gui" {
  let options = Array(arguments.dropFirst())
  if CLIOption.isHelp(options[...]) {
    print(
      "Usage: pared gui [--policy FILE]\n\nOpen the macOS app with the default or an existing policy."
    )
    exit(0)
  }
  guard
    options.isEmpty
      || (options.count == 2 && options[0] == "--policy" && !options[1].hasPrefix("-"))
  else {
    report("Usage: pared gui [--policy FILE]")
    exit(ExitStatus.failure.rawValue)
  }
  ParedApp.main()
  exit(0)
}
if arguments.isEmpty && Bundle.main.bundleURL.pathExtension == "app" {
  ParedApp.main()
  exit(0)
}

do {
  exit(try runCLI(arguments).rawValue)
} catch {
  report("pared: \(error)")
  exit(ExitStatus.failure.rawValue)
}
