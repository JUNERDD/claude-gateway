import AppKit
import SwiftUI

struct LogDetailSheet: View {
    var event: GatewayLogEvent
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .center, spacing: 10) {
                Text(event.tone.sheetLabel)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(event.tone.sheetTint)
                    .padding(.horizontal, 8)
                    .frame(height: 19)
                    .background(event.tone.sheetTint.opacity(0.10), in: Capsule())
                    .overlay(
                        Capsule()
                            .stroke(event.tone.sheetTint.opacity(0.24), lineWidth: 0.7)
                    )

                VStack(alignment: .leading, spacing: 4) {
                    Text(event.detailTitle ?? event.title)
                        .font(.system(size: 14, weight: .semibold))
                    Text(event.subtitle.isEmpty ? event.title : event.subtitle)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }

                Spacer()

                Text(event.timestamp.isEmpty ? "--:--:--" : event.timestamp)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(Color(nsColor: .controlBackgroundColor))

            Divider()

            VStack(alignment: .leading, spacing: 10) {
                if !event.fields.isEmpty {
                    HStack(spacing: 8) {
                        ForEach(event.fields) { field in
                            LogFieldChip(field: field)
                        }
                        Spacer()
                    }
                }

                ScrollView([.horizontal, .vertical]) {
                    Text(event.detailJSON ?? "{}")
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(.primary)
                        .textSelection(.enabled)
                        .padding(10)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(minHeight: 320)
                .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 6))
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(Color(nsColor: .separatorColor).opacity(0.75), lineWidth: 1)
                )

                HStack {
                    Spacer()

                    Button {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(event.detailJSON ?? "{}", forType: .string)
                    } label: {
                        Label("复制 JSON", systemImage: "doc.on.doc")
                    }
                    .controlSize(.small)

                    Button("关闭") {
                        dismiss()
                    }
                    .controlSize(.small)
                    .keyboardShortcut(.cancelAction)
                }
            }
            .padding(14)
        }
        .frame(width: 720, height: 500)
        .background(Color(nsColor: .windowBackgroundColor))
    }
}

private struct LogFieldChip: View {
    var field: GatewayLogField

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(field.label.uppercased())
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(.secondary)
            Text(field.value)
                .font(.system(size: 11, design: .monospaced))
                .lineLimit(1)
                .truncationMode(.middle)
                .textSelection(.enabled)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 5))
        .overlay(
            RoundedRectangle(cornerRadius: 5)
                .stroke(Color(nsColor: .separatorColor).opacity(0.65), lineWidth: 1)
        )
    }
}

private extension GatewayLogTone {
    var sheetLabel: String {
        switch self {
        case .info:
            return "INFO"
        case .request:
            return "REQUEST"
        case .response:
            return "RESP"
        case .warning:
            return "WARN"
        case .error:
            return "ERROR"
        }
    }

    var sheetTint: Color {
        switch self {
        case .info, .request:
            return .blue
        case .response:
            return .green
        case .warning:
            return .orange
        case .error:
            return .red
        }
    }
}
