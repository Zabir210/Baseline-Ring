import SwiftUI
import BaselineCore

extension BaselineStatus {
    var tint: Color {
        switch self {
        case .clear: .green
        case .learning: .secondary
        case .info: .blue
        case .warn: .orange
        case .high: .red
        }
    }
}
