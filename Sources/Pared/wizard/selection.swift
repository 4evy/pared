import Foundation
import Noora

// Keep letters available during search, including j and k
// which Noora's multi-choice prompt otherwise reserves for navigation
func wizardSelectFeatures(options: [(id: String, label: String)]) -> [String] {
  let terminal = WizardTerminal()
  let renderer = WizardRenderer()
  let output = StandardOutputPipeline()
  var selected = Set<String>()
  var searching = false
  var query = ""
  var current = 0

  func matches() -> [(id: String, label: String)] {
    options.filter { query.isEmpty || $0.label.localizedCaseInsensitiveContains(query) }
  }

  func render() {
    let filtered = matches()
    let width = WizardStyle.contentWidth
    let header =
      [
        "◉ Choose features",
        "Space selects; Enter reviews your choices.",
        "\(selected.count) selected across all search results",
      ] + (searching ? ["Search: \(query)"] : [])
    let footer =
      searching
      ? "↑/↓ move · Space select · Esc clear · Enter review"
      : "↑/↓ move · Space select · / search · Enter review"
    let overhead = WizardStyle.wrap((header + [footer]).joined(separator: "\n"), width: width).count
    // Budget wrapped option rows as well as the panel and trailing newline
    let optionRows = max(
      1, filtered.map { WizardStyle.wrap("  ❯ ◉ " + $0.label, width: width).count }.max() ?? 1)
    let count = max(1, ((terminal.size()?.rows ?? 21) - overhead) / optionRows)
    let start = max(0, min(current - count / 2, filtered.count - count))
    let visible = filtered.dropFirst(start).prefix(count)
    var lines = header.map { TerminalText(stringLiteral: $0) }
    if filtered.isEmpty {
      lines.append("No matching features. Esc clears the search.")
    } else {
      for (offset, option) in visible.enumerated() {
        let marker = selected.contains(option.id) ? "◉" : "○"
        let focused = start + offset == current
        let label = "\(focused ? "❯" : " ") \(marker) \(option.label)"
        lines.append(focused ? "  \(.primary(label))" : "  \(label)")
      }
    }
    lines.append("\(.muted(footer))")
    renderer.render(
      lines.map { $0.formatted(theme: WizardStyle.theme, terminal: terminal) }.joined(
        separator: "\n"),
      standardPipeline: output)
  }

  terminal.withoutCursor {
    terminal.inRawMode {
      render()
      KeyStrokeListener().listen(terminal: terminal) { key in
        let filtered = matches()
        switch key {
        case .returnKey: return .abort
        case .printable(" "):
          if filtered.indices.contains(current) {
            let name = filtered[current].id
            if selected.contains(name) { selected.remove(name) } else { selected.insert(name) }
          }
        case .printable(let character) where searching:
          query.append(character)
          current = 0
        case .backspace, .delete:
          if searching && !query.isEmpty {
            query.removeLast()
            current = 0
          }
        case .escape:
          searching = false
          query = ""
          current = 0
        case .printable("/"):
          searching = true
        case .upArrowKey, .printable("k"):
          if !filtered.isEmpty { current = (current + filtered.count - 1) % filtered.count }
        case .downArrowKey, .printable("j"):
          if !filtered.isEmpty { current = (current + 1) % filtered.count }
        default: break
        }
        render()
        return .continue
      }
    }
  }
  renderer.render("✔ Choose features: \(selected.count) selected", standardPipeline: output)
  return options.filter { selected.contains($0.id) }.map(\.id)
}
