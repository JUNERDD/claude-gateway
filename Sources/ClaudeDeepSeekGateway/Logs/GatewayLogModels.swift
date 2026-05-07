import AppKit
import SwiftUI

// MARK: - 日志事件视图

enum GatewayLogTone {
    case info
    case request
    case response
    case warning
    case error

    var color: Color {
        switch self {
        case .info:
            return .secondary
        case .request:
            return .blue
        case .response:
            return .green
        case .warning:
            return .orange
        case .error:
            return .red
        }
    }

    var nsColor: NSColor {
        switch self {
        case .info:
            return .secondaryLabelColor
        case .request:
            return .systemBlue
        case .response:
            return .systemGreen
        case .warning:
            return .systemOrange
        case .error:
            return .systemRed
        }
    }

    var symbolName: String {
        switch self {
        case .info:
            return "circle"
        case .request:
            return "arrow.up.forward.circle.fill"
        case .response:
            return "checkmark.circle.fill"
        case .warning:
            return "exclamationmark.triangle.fill"
        case .error:
            return "xmark.octagon.fill"
        }
    }

    var label: String {
        switch self {
        case .info:
            return "Info"
        case .request:
            return "Request"
        case .response:
            return "Response"
        case .warning:
            return "Warning"
        case .error:
            return "Error"
        }
    }
}

struct GatewayLogField: Identifiable {
    let id = UUID()
    var label: String
    var value: String
}

struct GatewayLogEvent: Identifiable {
    let id: String
    var timestamp: String
    var tone: GatewayLogTone
    var title: String
    var subtitle: String
    var fields: [GatewayLogField]
    var detailTitle: String?
    var detailJSON: String?
}
