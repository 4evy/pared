import Foundation

extension FeatureState {
  var title: String {
    switch self {
    case .enabled: "Enabled"
    case .disabled: "Disabled"
    case .unmanaged: "Unmanaged"
    }
  }

  var symbol: String {
    switch self {
    case .enabled: "checkmark.circle"
    case .disabled: "minus.circle"
    case .unmanaged: "circle.dashed"
    }
  }
}

enum GUISection: String, CaseIterable, Identifiable {
  case features = "Features"
  case models = "Models"
  case profile = "Profile"

  var id: Self { self }

  var symbol: String {
    switch self {
    case .features: "switch.2"
    case .models: "internaldrive"
    case .profile: "doc.badge.gearshape"
    }
  }
}

enum GUIFeatureFilter: String, CaseIterable, Identifiable {
  case all = "All Features"
  case enabled = "Enabled"
  case disabled = "Disabled"
  case unmanaged = "Unmanaged"
  case changes = "Unsaved Changes"

  var id: Self { self }
}

struct FeaturePresentation: Identifiable {
  let id: String
  let title: String
  let symbol: String
  let group: String

  static let groups = ["Siri & Writing", "Apps", "System", "Shared Models"]

  init(_ name: String) {
    id = name
    let presentation: (String, String, String)
    switch name {
    case "siri": presentation = ("Siri", "waveform", "Siri & Writing")
    case "siriVoiceTrigger":
      presentation = ("Voice Activation", "mic", "Siri & Writing")
    case "writingTools": presentation = ("Writing Tools", "pencil.line", "Siri & Writing")
    case "inlinePredictions":
      presentation = ("Inline Predictions", "text.cursor", "Siri & Writing")
    case "externalIntelligence":
      presentation = ("External Integrations", "network", "Siri & Writing")
    case "genmoji": presentation = ("Genmoji", "face.smiling", "Apps")
    case "imagePlayground": presentation = ("Image Playground", "photo", "Apps")
    case "mailSmartReplies": presentation = ("Mail Smart Replies", "envelope", "Apps")
    case "mailSummaries": presentation = ("Mail Summaries", "envelope", "Apps")
    case "mailAutomaticSummaries":
      presentation = ("Automatic Mail Summaries", "envelope", "Apps")
    case "mailPersonalizedReplies":
      presentation = ("Personalized Mail Replies", "envelope", "Apps")
    case "notesSummaries": presentation = ("Notes Summaries", "note.text", "Apps")
    case "safariSummaries": presentation = ("Safari Summaries", "safari", "Apps")
    case "messagesSummaries": presentation = ("Messages Summaries", "message", "Apps")
    case "spatialPhotos": presentation = ("Spatial Photos", "photo.stack", "Apps")
    case "photosCleanup": presentation = ("Photos Clean Up Models", "sparkles", "Apps")
    case "notificationSummaries":
      presentation = ("Notification Summaries", "bell", "System")
    case "visualIntelligence": presentation = ("Visual Intelligence", "eye", "System")
    case "calendarIntelligence":
      presentation = ("Calendar Intelligence", "calendar", "Apps")
    case "codeIntelligence":
      presentation = (
        "Code Generation Models", "chevron.left.forwardslash.chevron.right", "Shared Models"
      )
    case "foundationModels":
      presentation = ("Foundation Models", "cube.transparent", "Shared Models")
    default: presentation = (name, "slider.horizontal.3", "System")
    }
    (title, symbol, group) = presentation
  }

  static func modelTitle(_ assetSet: String) -> String {
    switch assetSet {
    case "com.apple.modelcatalog": "Foundation Models"
    case "com.apple.MobileAsset.UAF.FM.Visual": "Image Generation"
    case "com.apple.MobileAsset.UAF.FM.CodeLM": "Code Generation"
    case "com.apple.MobileAsset.UAF.Photos.MagicCleanup": "Photos Clean Up"
    case "com.apple.MobileAsset.UAF.Photos.SpatialPhotosRelive": "Spatial Photos"
    default: assetSet
    }
  }

  static func preferenceTitle(_ key: String) -> String {
    switch key {
    case "Assistant Enabled": "Siri Assistant"
    case "StatusMenuVisible": "Siri in the Menu Bar"
    case "VoiceTriggerUserEnabled": "Voice Activation"
    case "DisableAutomaticMessageSummarization": "Automatic Mail Summaries"
    case "PersonalizedSmartReplies": "Personalized Mail Replies"
    case "messageSummarizationEnabled": "Messages Summaries"
    case "summarize_previews": "Notification Summaries"
    case "NSAutomaticInlinePredictionEnabled": "Inline Predictions"
    case "LocallyDisabled": "Spatial Photos"
    default: key
    }
  }
}
