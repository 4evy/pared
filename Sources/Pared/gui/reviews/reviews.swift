import SwiftUI

// One presentation route keeps mutually exclusive reviews in one sheet
enum GUIReview: Identifiable {
  case cleanup(ModelCleanupOffer)
  case modelUsers(ModelQuitOffer)
  case quickAction(GUIQuickAction)

  var id: String {
    switch self {
    case .cleanup(let offer): "cleanup-\(offer.id)"
    case .modelUsers(let offer): "users-\(offer.id)"
    case .quickAction(let action): "quick-\(action.id)"
    }
  }
}

struct GUIReviewView: View {
  let store: GUIStore
  let review: GUIReview

  var body: some View {
    switch review {
    case .cleanup(let offer): CleanupReview(store: store, review: offer)
    case .modelUsers(let offer): ModelQuitReview(store: store, review: offer)
    case .quickAction(let action): QuickActionReview(store: store, action: action)
    }
  }
}
