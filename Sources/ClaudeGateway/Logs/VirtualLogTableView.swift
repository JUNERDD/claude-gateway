import AppKit
import SwiftUI

struct VirtualLogTableView: NSViewRepresentable {
    var events: [GatewayLogEvent]
    var onShowDetails: (GatewayLogEvent) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onShowDetails: onShowDetails)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSScrollView()
        scroll.hasVerticalScroller = true
        scroll.hasHorizontalScroller = false
        scroll.autohidesScrollers = true
        scroll.borderType = .noBorder
        scroll.drawsBackground = true
        scroll.backgroundColor = .textBackgroundColor

        let table = NSTableView()
        table.rowHeight = 34
        table.intercellSpacing = NSSize(width: 0, height: 3)
        table.usesAlternatingRowBackgroundColors = false
        table.selectionHighlightStyle = .regular
        table.columnAutoresizingStyle = .lastColumnOnlyAutoresizingStyle
        table.gridStyleMask = [.solidHorizontalGridLineMask]
        table.gridColor = NSColor.separatorColor.withAlphaComponent(0.35)
        table.backgroundColor = .textBackgroundColor
        table.rowSizeStyle = .medium
        if #available(macOS 11.0, *) {
            table.style = .plain
        }
        table.dataSource = context.coordinator
        table.delegate = context.coordinator
        table.target = context.coordinator
        table.doubleAction = #selector(Coordinator.openSelectedDetail(_:))

        context.coordinator.tableView = table
        context.coordinator.replaceEvents(events)

        addColumn("time", title: "Time", width: 76, minWidth: 68, to: table)
        addColumn("level", title: "", width: 78, minWidth: 68, to: table)
        addColumn("message", title: "Message", width: 300, minWidth: 180, maxWidth: 1_000, to: table)
        addColumn("route", title: "Method/Path", width: 164, minWidth: 112, to: table)
        addColumn("status", title: "Status", width: 64, minWidth: 52, to: table)
        addColumn("latency", title: "Latency", width: 76, minWidth: 64, to: table)
        addColumn("meta", title: "Meta", width: 190, minWidth: 120, maxWidth: 420, to: table)
        addColumn("detail", title: "", width: 36, minWidth: 34, maxWidth: 40, to: table)

        scroll.documentView = table
        return scroll
    }

    func updateNSView(_ nsView: NSScrollView, context: Context) {
        context.coordinator.onShowDetails = onShowDetails
        if let table = context.coordinator.tableView {
            let previousEvents = context.coordinator.events
            let selectedIDs = Set(table.selectedRowIndexes.compactMap { index in
                previousEvents.indices.contains(index) ? previousEvents[index].id : nil
            })
            let changed = context.coordinator.replaceEvents(events)
            if changed {
                table.reloadData()
            }
            let indexes = IndexSet(events.enumerated().compactMap { index, event in
                selectedIDs.contains(event.id) ? index : nil
            })
            if !indexes.isEmpty {
                table.selectRowIndexes(indexes, byExtendingSelection: false)
            }
        } else {
            context.coordinator.replaceEvents(events)
        }
    }

    private func addColumn(
        _ id: String,
        title: String,
        width: CGFloat,
        minWidth: CGFloat,
        maxWidth: CGFloat? = nil,
        to table: NSTableView
    ) {
        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier(id))
        column.title = title
        column.width = width
        column.minWidth = minWidth
        column.maxWidth = maxWidth ?? width
        column.resizingMask = id == "detail" ? [] : .userResizingMask
        table.addTableColumn(column)
    }

    final class Coordinator: NSObject, NSTableViewDataSource, NSTableViewDelegate {
        weak var tableView: NSTableView?
        var events: [GatewayLogEvent] = []
        private var eventIDs: [String] = []
        private var projections: [LogRowProjection] = []
        var onShowDetails: (GatewayLogEvent) -> Void

        init(onShowDetails: @escaping (GatewayLogEvent) -> Void) {
            self.onShowDetails = onShowDetails
        }

        @discardableResult
        func replaceEvents(_ newEvents: [GatewayLogEvent]) -> Bool {
            let newIDs = newEvents.map(\.id)
            guard newIDs != eventIDs else { return false }
            events = newEvents
            eventIDs = newIDs
            projections = newEvents.map(LogRowProjection.init(event:))
            return true
        }

        func numberOfRows(in tableView: NSTableView) -> Int {
            events.count
        }

        func tableView(_ tableView: NSTableView, heightOfRow row: Int) -> CGFloat {
            34
        }

        func tableView(
            _ tableView: NSTableView,
            viewFor tableColumn: NSTableColumn?,
            row: Int
        ) -> NSView? {
            guard events.indices.contains(row),
                let columnID = tableColumn?.identifier.rawValue
            else {
                return nil
            }

            let event = events[row]
            let projection = projections.indices.contains(row) ? projections[row] : LogRowProjection(event: event)
            switch columnID {
            case "time":
                return textCell(
                    tableView,
                    id: columnID,
                    text: event.timestamp.isEmpty ? "--:--:--" : event.timestamp,
                    font: .monospacedSystemFont(ofSize: 11, weight: .regular),
                    color: .secondaryLabelColor
                )
            case "level":
                return badgeCell(tableView, id: columnID, tone: event.tone)
            case "message":
                return textCell(
                    tableView,
                    id: columnID,
                    text: projection.message,
                    font: .systemFont(ofSize: 12, weight: .regular),
                    color: .labelColor,
                    lineBreakMode: .byTruncatingTail
                )
            case "route":
                return textCell(
                    tableView,
                    id: columnID,
                    text: projection.route,
                    font: .monospacedSystemFont(ofSize: 11, weight: .regular),
                    color: projection.route == "-" ? .tertiaryLabelColor : .secondaryLabelColor
                )
            case "status":
                return textCell(
                    tableView,
                    id: columnID,
                    text: projection.status,
                    font: .monospacedSystemFont(ofSize: 11, weight: .semibold),
                    color: projection.statusColor
                )
            case "latency":
                return textCell(
                    tableView,
                    id: columnID,
                    text: projection.latency,
                    font: .monospacedSystemFont(ofSize: 11, weight: .regular),
                    color: .secondaryLabelColor
                )
            case "meta":
                return textCell(
                    tableView,
                    id: columnID,
                    text: projection.meta,
                    font: .monospacedSystemFont(ofSize: 10.5, weight: .regular),
                    color: projection.meta == "-" ? .tertiaryLabelColor : .secondaryLabelColor
                )
            case "detail":
                return detailButton(tableView, row: row, event: event)
            default:
                return nil
            }
        }

        @objc func showDetail(_ sender: NSButton) {
            let tableRow = tableView?.row(for: sender) ?? -1
            let row = events.indices.contains(tableRow) ? tableRow : sender.tag
            guard events.indices.contains(row) else { return }
            onShowDetails(events[row])
        }

        @objc func openSelectedDetail(_ sender: NSTableView) {
            let row = sender.clickedRow >= 0 ? sender.clickedRow : sender.selectedRow
            guard events.indices.contains(row), events[row].detailJSON != nil else { return }
            onShowDetails(events[row])
        }

        private func textCell(
            _ tableView: NSTableView,
            id: String,
            text: String,
            font: NSFont,
            color: NSColor,
            lineBreakMode: NSLineBreakMode = .byTruncatingMiddle
        ) -> NSTableCellView {
            let identifier = NSUserInterfaceItemIdentifier("cell-\(id)")
            let cell = tableView.makeView(withIdentifier: identifier, owner: self) as? NSTableCellView
                ?? makeTextCell(identifier: identifier)
            cell.textField?.stringValue = text
            cell.textField?.font = font
            cell.textField?.textColor = color
            cell.textField?.lineBreakMode = lineBreakMode
            return cell
        }

        private func makeTextCell(identifier: NSUserInterfaceItemIdentifier) -> NSTableCellView {
            let cell = NSTableCellView()
            cell.identifier = identifier

            let textField = NSTextField(labelWithString: "")
            textField.translatesAutoresizingMaskIntoConstraints = false
            textField.lineBreakMode = .byTruncatingMiddle
            textField.maximumNumberOfLines = 1
            textField.allowsExpansionToolTips = true

            cell.addSubview(textField)
            cell.textField = textField
            NSLayoutConstraint.activate([
                textField.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 10),
                textField.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -8),
                textField.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
            ])
            return cell
        }

        private func badgeCell(_ tableView: NSTableView, id: String, tone: GatewayLogTone) -> NSTableCellView {
            let identifier = NSUserInterfaceItemIdentifier("cell-\(id)")
            let cell = tableView.makeView(withIdentifier: identifier, owner: self) as? NSTableCellView
                ?? makeBadgeCell(identifier: identifier)
            guard let badge = cell.textField else { return cell }
            badge.stringValue = tone.tableLabel
            badge.textColor = tone.badgeTextColor
            badge.backgroundColor = tone.badgeBackgroundColor
            badge.layer?.borderColor = tone.badgeBorderColor.cgColor
            return cell
        }

        private func makeBadgeCell(identifier: NSUserInterfaceItemIdentifier) -> NSTableCellView {
            let cell = NSTableCellView()
            cell.identifier = identifier

            let badge = NSTextField(labelWithString: "")
            badge.translatesAutoresizingMaskIntoConstraints = false
            badge.alignment = .center
            badge.font = .systemFont(ofSize: 10, weight: .semibold)
            badge.drawsBackground = true
            badge.isBordered = false
            badge.wantsLayer = true
            badge.layer?.cornerRadius = 5
            badge.layer?.masksToBounds = true
            badge.layer?.borderWidth = 0.7

            cell.addSubview(badge)
            cell.textField = badge
            NSLayoutConstraint.activate([
                badge.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 8),
                badge.widthAnchor.constraint(equalToConstant: 58),
                badge.heightAnchor.constraint(equalToConstant: 18),
                badge.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
            ])
            return cell
        }

        private func detailButton(_ tableView: NSTableView, row: Int, event: GatewayLogEvent) -> NSView {
            let identifier = NSUserInterfaceItemIdentifier("cell-detail")
            let cell = tableView.makeView(withIdentifier: identifier, owner: self) as? NSTableCellView
                ?? makeDetailCell(identifier: identifier)

            guard let button = cell.subviews.compactMap({ $0 as? NSButton }).first else {
                return cell
            }
            button.isEnabled = event.detailJSON != nil
            button.alphaValue = event.detailJSON == nil ? 0.18 : 0.85
            button.tag = row
            return cell
        }

        private func makeDetailCell(identifier: NSUserInterfaceItemIdentifier) -> NSTableCellView {
            let cell = NSTableCellView()
            cell.identifier = identifier

            let button = NSButton(title: "", target: self, action: #selector(showDetail(_:)))
            button.translatesAutoresizingMaskIntoConstraints = false
            button.bezelStyle = .inline
            button.controlSize = .small
            button.image = NSImage(systemSymbolName: "info.circle", accessibilityDescription: "详情")
            button.imagePosition = .imageOnly
            button.isBordered = false
            button.contentTintColor = .secondaryLabelColor

            cell.addSubview(button)
            NSLayoutConstraint.activate([
                button.widthAnchor.constraint(equalToConstant: 22),
                button.heightAnchor.constraint(equalToConstant: 22),
                button.centerXAnchor.constraint(equalTo: cell.centerXAnchor),
                button.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
            ])
            return cell
        }
    }
}

private struct LogRowProjection {
    var message: String
    var route: String
    var status: String
    var statusColor: NSColor
    var latency: String
    var meta: String

    init(event: GatewayLogEvent) {
        message = event.subtitle.isEmpty ? event.title : "\(event.title) - \(event.subtitle)"
        route = Self.route(from: event)
        status = Self.status(from: event)
        statusColor = Self.statusColor(status)
        latency = Self.fieldValue(in: event, matching: ["耗时", "latency", "duration"]) ?? "-"
        meta = Self.meta(from: event)
    }

    private static func route(from event: GatewayLogEvent) -> String {
        let parts = event.subtitle.split(separator: " ", maxSplits: 1).map(String.init)
        guard parts.count == 2, parts[0].range(of: #"^[A-Z]+$"#, options: .regularExpression) != nil else {
            return "-"
        }
        return "\(parts[0]) \(parts[1])"
    }

    private static func status(from event: GatewayLogEvent) -> String {
        let parts = event.subtitle.split(separator: " ").map(String.init)
        if parts.count == 2, parts[0].localizedCaseInsensitiveCompare("HTTP") == .orderedSame {
            return parts[1]
        }
        return "-"
    }

    private static func statusColor(_ value: String) -> NSColor {
        guard let status = Int(value) else { return .tertiaryLabelColor }
        switch status {
        case 200..<300:
            return .systemGreen
        case 300..<400:
            return .systemBlue
        case 400..<500:
            return .systemOrange
        default:
            return .systemRed
        }
    }

    private static func meta(from event: GatewayLogEvent) -> String {
        let hiddenLabels = ["耗时", "latency", "duration"]
        let fields = event.fields.filter { field in
            !hiddenLabels.contains { label in
                field.label.localizedCaseInsensitiveContains(label)
            }
        }
        let summary = fields.map { "\($0.label): \($0.value)" }.joined(separator: "  ")
        return summary.isEmpty ? "-" : summary
    }

    private static func fieldValue(in event: GatewayLogEvent, matching labels: [String]) -> String? {
        event.fields.first { field in
            labels.contains { label in
                field.label.localizedCaseInsensitiveContains(label)
            }
        }?.value
    }
}

private extension GatewayLogTone {
    var tableLabel: String {
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

    var badgeTextColor: NSColor {
        switch self {
        case .info, .request:
            return .systemBlue
        case .response:
            return .systemGreen
        case .warning:
            return .systemOrange
        case .error:
            return .systemRed
        }
    }

    var badgeBackgroundColor: NSColor {
        badgeTextColor.withAlphaComponent(0.10)
    }

    var badgeBorderColor: NSColor {
        badgeTextColor.withAlphaComponent(0.24)
    }
}
