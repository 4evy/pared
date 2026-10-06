import Foundation
import Noora
import Synchronization

enum WizardStyle {
  // The user's terminal theme supplies contrast for ordinary text; reserve the
  // accent for focus and changes
  static let theme = Theme(
    primary: "397CAD", secondary: "275A80", muted: "808080", accent: "B07919",
    danger: "C74848", success: "39835A", info: "397CAD",
    selectedRowText: "FFFFFF", selectedRowBackground: "275A80")

  static let content = Content(
    errorAlertTitle: "✖ Error", errorAlertRecommendedTitle: "What happens next",
    warningAlertTitle: "! Check before continuing", warningAlertRecommendedTitle: "Details",
    successAlertTitle: "✔ Done", successAlertRecommendedTitle: "Next steps",
    infoAlertTitle: "i Pared", infoAlertRecommendedTitle: "Details",
    choicePromptFilterTitle: "Search",
    choicePromptInstructionWithoutFilter: "↑/↓ move · Enter choose",
    choicePromptInstructionWithFilter: "↑/↓ move · / search · Enter choose",
    choicePromptInstructionIsFiltering: "↑/↓ move · Esc clear · Enter choose",
    multipleChoicePromptFilterTitle: "Search",
    multipleChoicePromptErrorTitle: "Check your selection",
    multipleChoicePromptInstructionWithoutFilter: "↑/↓ move · Space select · Enter review",
    multipleChoicePromptInstructionWithFilter: "↑/↓ move · Space select · / search · Enter review",
    multipleChoicePromptInstructionIsFiltering:
      "↑/↓ move · Space select · Esc clear · Enter review",
    textPromptValidationErrorsTitle: "Check this path",
    yesOrNoChoicePromptInstruction: "←/→ choose · Enter confirm",
    yesOrNoChoicePromptPositiveText: YesNoAnswerContent(fullText: "Yes", character: "y"),
    yesOrNoChoicePromptNegativeText: YesNoAnswerContent(fullText: "No", character: "n"))

  private static var styling: Regex<Substring> {
    #/\x1B\[[0-?]*[ -/]*[@-~]|\x1B\][^\x07\x1B]*(?:\x07|\x1B\\)/#
  }

  static func plain(_ text: String) -> String {
    text.replacing(styling, with: "")
  }

  static var contentWidth: Int {
    max(12, min(74, (Terminal(signalBehavior: .none).size()?.columns ?? 80) - 4))
  }

  // Wrap words while retaining zero-width styling sequences and wide glyphs
  static func wrap(_ text: String, width: Int) -> [String] {
    let tokens = #/\x1B\[[0-?]*[ -/]*[@-~]|\x1B\][^\x07\x1B]*(?:\x07|\x1B\\)|[^\s\x1B]+|[ \t]+/#
    var result: [String] = []
    for source in text.components(separatedBy: "\n") {
      var line = ""
      var used = 0
      var styles = ""
      func nextLine() {
        result.append(line + "\u{1B}[0m")
        line = styles
        used = 0
      }
      for match in source.matches(of: tokens) {
        let token = match.output
        if token.hasPrefix("\u{1B}") {
          line += token
          if token == "\u{1B}[0m" { styles = "" } else { styles += token }
          continue
        }
        if token.first?.isWhitespace == true {
          if used + token.displayWidth < width {
            line += token
            used += token.displayWidth
          }
          continue
        }
        if used > 0 && used + token.displayWidth > width { nextLine() }
        for character in token {
          if used + character.displayWidth > width { nextLine() }
          line.append(character)
          used += character.displayWidth
        }
      }
      result.append(line + "\u{1B}[0m")
    }
    if !Terminal.isColored() { return result.map(plain) }
    return result
  }
}

// Tell Noora how much room remains inside the panel, so its scrolling keeps
// the current option visible rather than filling the physical terminal
struct WizardTerminal: Terminaling {
  private let base = Terminal()
  var isInteractive: Bool { base.isInteractive }
  var isColored: Bool { base.isColored }
  var signalBehavior: SignalBehavior { base.signalBehavior }
  func withoutCursor(_ body: () throws -> Void) rethrows { try base.withoutCursor(body) }
  func inRawMode(_ body: @escaping () throws -> Void) rethrows { try base.inRawMode(body) }
  func readRawCharacter() -> Int32? { base.readRawCharacter() }
  func readCharacter() -> Character? { base.readCharacter() }
  func readRawCharacterNonBlocking() -> Int32? { base.readRawCharacterNonBlocking() }
  func readCharacterNonBlocking() -> Character? { base.readCharacterNonBlocking() }
  func size() -> TerminalSize? {
    base.size().map { TerminalSize(rows: max(1, $0.rows - 3), columns: WizardStyle.contentWidth) }
  }
}

// Clear physical rows, including wrapping, rather than Noora's logical lines
final class WizardRenderer: Rendering {
  private let previousLines = Mutex<[String]>([])
  private let terminal = Terminal(signalBehavior: .none)

  func render(_ input: String, standardPipeline: StandardPipelining) {
    previousLines.withLock { previousLines in
      let columns = max(1, terminal.size()?.columns ?? 80)
      let rows = previousLines.reduce(0) { count, line in
        count + max(1, (WizardStyle.plain(line).displayWidth + columns - 1) / columns)
      }
      if rows > 0 {
        for row in 0...rows {
          standardPipeline.write(content: "\u{1B}[2K")
          if row < rows { standardPipeline.write(content: "\u{1B}[1A") }
        }
        standardPipeline.write(content: "\u{1B}[1G")
      }
      let width = WizardStyle.contentWidth
      // Noora sets a background for the selected Yes/No answer; supply its text
      // color too, so it stays readable on both light and dark terminal themes
      let source = input.trimmingCharacters(in: .newlines).replacing(
        #/\x1B\[(?:48;2;\d+;\d+;\d+|48;5;\d+)m/#
      ) { "\($0.output)\u{1B}[38;2;255;255;255m" }
      let lines: [String]
      if source.contains("\n") {
        let edge: TerminalText = "\(.muted(String(repeating: "─", count: width + 2)))"
        let side: TerminalText = "\(.muted("│"))"
        let horizontal = edge.formatted(theme: WizardStyle.theme, terminal: terminal)
        let vertical = side.formatted(theme: WizardStyle.theme, terminal: terminal)
        let focused = source.components(separatedBy: "\n").map { line in
          if WizardStyle.plain(line).contains("❯") {
            let text: TerminalText = "\(.primary(WizardStyle.plain(line)))"
            return text.formatted(theme: WizardStyle.theme, terminal: terminal)
          }
          return line
        }.joined(separator: "\n")
        let content = WizardStyle.wrap(focused, width: width).map { line in
          let padding = String(
            repeating: " ", count: max(0, width - WizardStyle.plain(line).displayWidth))
          return "\(vertical) \(line)\(padding) \(vertical)"
        }
        lines = ["╭\(horizontal)╮"] + content + ["╰\(horizontal)╯"]
      } else {
        lines = WizardStyle.wrap(source, width: width + 4)
      }
      for line in lines { standardPipeline.write(content: line + "\n") }
      previousLines = lines
    }
  }
}
