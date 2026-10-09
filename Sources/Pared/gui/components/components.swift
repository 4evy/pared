import SwiftUI

struct FullWidthDisclosureStyle: DisclosureGroupStyle {
  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  func makeBody(configuration: Configuration) -> some View {
    VStack(alignment: .leading, spacing: 0) {
      Button {
        withAnimation(reduceMotion ? nil : .default) {
          configuration.isExpanded.toggle()
        }
      } label: {
        HStack(spacing: 8) {
          Image(systemName: "chevron.right")
            .font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            .rotationEffect(.degrees(configuration.isExpanded ? 90 : 0))
            .accessibilityHidden(true)
          configuration.label.frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, 6)
        .contentShape(Rectangle())
      }
      .buttonStyle(.plain)
      .accessibilityValue(configuration.isExpanded ? "Expanded" : "Collapsed")
      if configuration.isExpanded {
        configuration.content
          .frame(maxWidth: .infinity, alignment: .leading)
          .padding(.leading, 18)
      }
    }
  }
}

struct GUIPage<Content: View>: View {
  var spacing: CGFloat = 20
  var padding: CGFloat = 28
  var maximumWidth: CGFloat = 860
  @ViewBuilder var content: () -> Content

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: spacing, content: content)
        .padding(padding).frame(maxWidth: maximumWidth, alignment: .leading)
        .frame(maxWidth: .infinity, alignment: .top)
    }
    .disclosureGroupStyle(FullWidthDisclosureStyle())
  }
}

struct SettingsGroup<Content: View>: View {
  var title: String? = nil
  var spacing: CGFloat = 12
  @ViewBuilder var content: () -> Content

  var body: some View {
    GroupBox {
      VStack(alignment: .leading, spacing: spacing, content: content)
        .padding(8).frame(maxWidth: .infinity, alignment: .leading)
    } label: {
      if let title { Text(title) }
    }
  }
}

struct GUICard<Content: View>: View {
  var spacing: CGFloat = 12
  var padding: CGFloat = 20
  var subtle = false
  @ViewBuilder var content: () -> Content

  var body: some View {
    VStack(alignment: .leading, spacing: spacing, content: content)
      .padding(padding).frame(maxWidth: .infinity, alignment: .leading)
      .background {
        if subtle {
          RoundedRectangle(cornerRadius: 10).fill(.quaternary.opacity(0.5))
        } else {
          RoundedRectangle(cornerRadius: 12).fill(Color(nsColor: .controlBackgroundColor))
        }
      }
  }
}

struct ChoiceBadge: View {
  let title: String
  var highlighted = false

  var body: some View {
    Text(title)
      .font(.caption.weight(.medium))
      .padding(.horizontal, 10).padding(.vertical, 4)
      .foregroundStyle(highlighted ? Color.accentColor : .secondary)
      .background(
        highlighted ? Color.accentColor.opacity(0.1) : Color.secondary.opacity(0.08),
        in: Capsule()
      )
      .fixedSize()
  }
}

struct ReviewSheet<Content: View, Actions: View>: View {
  let title: String
  let description: String
  let symbol: String
  @ViewBuilder var content: () -> Content
  @ViewBuilder var actions: () -> Actions

  var body: some View {
    VStack(spacing: 0) {
      PageHeading(title: title, description: description, symbol: symbol)
        .padding(24)
      ScrollView {
        VStack(alignment: .leading, spacing: 16, content: content)
          .frame(maxWidth: .infinity, alignment: .leading)
          .padding(.horizontal, 24).padding(.bottom, 24)
      }
      .defaultScrollAnchor(.top)
      .frame(maxHeight: 300)
      Divider()
      HStack(spacing: 10, content: actions)
        .padding(20)
    }
    .frame(width: 540)
  }
}

struct InlineMessage: View {
  let title: String?
  let message: String
  let symbol: String
  var isError = false

  var body: some View {
    HStack(alignment: .top, spacing: 10) {
      Image(systemName: symbol)
        .foregroundStyle(isError ? Color.orange : Color.secondary)
        .accessibilityHidden(true)
      VStack(alignment: .leading, spacing: 3) {
        if let title { Text(title).fontWeight(.medium).accessibilityAddTraits(.isHeader) }
        Text(message).foregroundStyle(.secondary).textSelection(.enabled)
      }
      Spacer(minLength: 0)
    }
    .font(.callout)
    .padding(14)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(.quaternary.opacity(0.5))
    .accessibilityElement(children: .combine)
  }
}

struct PageHeading: View {
  let title: String
  let description: String
  let symbol: String

  var body: some View {
    HStack(alignment: .top, spacing: 14) {
      Image(systemName: symbol).font(.system(size: 24, weight: .medium)).foregroundStyle(.tint)
        .frame(width: 48, height: 48)
        .background(Color.accentColor.opacity(0.1), in: RoundedRectangle(cornerRadius: 12))
        .accessibilityHidden(true)
      VStack(alignment: .leading, spacing: 6) {
        Text(title).font(.title.weight(.semibold)).accessibilityAddTraits(.isHeader)
        if !description.isEmpty {
          Text(description).font(.callout).foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
        }
      }
      Spacer(minLength: 0)
    }
    .padding(.bottom, 8)
  }
}

struct DiagnosticsDisclosure: View {
  let text: String

  var body: some View {
    if !text.isEmpty {
      DisclosureGroup("Operation Details") {
        ScrollView {
          Text(text).font(.caption.monospaced()).textSelection(.enabled)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxHeight: 180).padding(.top, 8)
      }
    }
  }
}
