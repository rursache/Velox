import SwiftUI
import AppKit

struct SearchView: View {
    @ObservedObject var engine: SearchEngine
    var theme: Theme
    var highlight: SelectionStyle = HighlightCatalog.style(for: .accent)
    var acceptsFocus: Bool = true

    private let searchRowHeight = SearchPanelController.searchRowHeight
    private let resultRowHeight = SearchPanelController.resultRowHeight

    var body: some View {
        VStack(spacing: 0) {
            searchField
                .frame(height: searchRowHeight)

            if !engine.results.isEmpty {
                resultsSection
            }
        }
        .frame(maxWidth: .infinity, alignment: .top)
        .fixedSize(horizontal: false, vertical: true)
        .ignoresSafeArea()
        .preferredColorScheme(theme.legibility.colorScheme)
    }

    private var resultsSection: some View {
        VStack(spacing: 0) {
            Divider().opacity(theme.dividerOpacity)

            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(Array(engine.results.enumerated()), id: \.element.id) { index, item in
                            ResultRow(item: item, isSelected: index == engine.selectedIndex, theme: theme, highlight: highlight)
                                .onTapGesture {
                                    guard SearchPanelShowTransition.shouldRunResultAction(acceptsFocus: acceptsFocus) else { return }
                                    engine.selectedIndex = index
                                    Task {
                                        let kind = await engine.executeSelected()
                                        NotificationCenter.default.post(name: .veloxHidePanel, object: kind)
                                    }
                                }
                        }
                    }
                }
                .frame(height: CGFloat(engine.results.count) * resultRowHeight)
                .onChange(of: engine.selectedIndex) { _, newValue in
                    if engine.results.indices.contains(newValue) {
                        proxy.scrollTo(engine.results[newValue].id, anchor: .center)
                    }
                }
            }
            .padding(.bottom, SearchPanelController.resultsBottomPad)
        }
    }

    private var searchField: some View {
        HStack(alignment: .firstTextBaseline, spacing: Constants.Panel.stackSpacing) {
            SearchSettingsButton()

            SearchTextField(
                text: Binding(
                    get: { engine.query },
                    set: { engine.updateQuery($0) }
                ),
                acceptsFocus: acceptsFocus,
                onSubmit: {
                    guard SearchPanelShowTransition.shouldRunResultAction(acceptsFocus: acceptsFocus) else { return }
                    Task {
                        let kind = await engine.executeSelected()
                        NotificationCenter.default.post(name: .veloxHidePanel, object: kind)
                    }
                }
            )
            .fixedSize(horizontal: false, vertical: true)

            if !engine.query.isEmpty {
                Button {
                    engine.updateQuery("")
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 15))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .alignmentGuide(.firstTextBaseline) { d in
                    d[VerticalAlignment.center] + SearchTextField.metrics.searchFont.capHeight / 2
                }
            }
        }
        .padding(.horizontal, Constants.Panel.barPaddingX)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
    }
}

private struct SearchSettingsButton: View {
    @State private var hovering = false

    var body: some View {
        Button(action: openSettings) {
            Image(systemName: StatusItemAppearance.symbolName(hovering: hovering))
                .font(.system(size: SearchTextField.metrics.iconPointSize, weight: .medium))
                .foregroundStyle(.secondary)
                .frame(width: Constants.Panel.iconColumn, height: Constants.Panel.iconColumn)
                .contentTransition(.symbolEffect(.replace))
        }
        .buttonStyle(.plain)
        .help(hovering ? "Settings" : "Search")
        .alignmentGuide(.firstTextBaseline) { d in
            d[VerticalAlignment.center] + SearchTextField.metrics.searchFont.capHeight / 2
        }
        .onHover { isHovering in
            withAnimation(.easeInOut(duration: 0.12)) {
                hovering = isHovering
            }
        }
        .accessibilityLabel("Settings")
    }

    private func openSettings() {
        hovering = false
        PreferencesWindowController.shared.show()
    }
}

/// AppKit text field with reliable focus + select-all for accessory / panel hosts
struct SearchTextField: NSViewRepresentable {
    @Binding var text: String
    var acceptsFocus: Bool = true
    var onSubmit: () -> Void

    /// Tracks system text size (Accessibility → Text size) with a slight Spotlight-like bump
    enum metrics {
        static var searchFont: NSFont {
            let system = NSFont.preferredFont(forTextStyle: .title2)
            // title2 is usually ~17; +3 reads closer to Spotlight while still scaling
            let size = system.pointSize + 3
            return NSFont.systemFont(ofSize: size, weight: .regular)
        }

        static var iconPointSize: CGFloat {
            max(18, searchFont.pointSize - 2)
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeNSView(context: Context) -> NSTextField {
        let field = SelectAllTextField()
        field.allowsFocus = acceptsFocus
        field.isBordered = false
        field.isBezeled = false
        field.drawsBackground = false
        field.focusRingType = .none
        applyTypography(to: field)
        field.textColor = .labelColor
        field.stringValue = text
        field.delegate = context.coordinator
        field.lineBreakMode = .byTruncatingTail
        field.cell?.usesSingleLineMode = true
        field.cell?.isScrollable = true
        field.cell?.wraps = false
        field.setContentHuggingPriority(.defaultLow, for: .horizontal)
        field.setContentHuggingPriority(.defaultHigh, for: .vertical)
        field.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        context.coordinator.field = field
        context.coordinator.observeFocus()
        context.coordinator.observeTypography()
        return field
    }

    func updateNSView(_ nsView: NSTextField, context: Context) {
        context.coordinator.parent = self
        (nsView as? SelectAllTextField)?.allowsFocus = acceptsFocus
        if acceptsFocus {
            context.coordinator.ensureFocusObservers()
        }
        applyTypography(to: nsView)
        if nsView.stringValue != text {
            // Preserve selection/caret when external updates match typing path
            let selected = nsView.currentEditor()?.selectedRange
            nsView.stringValue = text
            if let selected, let editor = nsView.currentEditor() {
                let maxLoc = (text as NSString).length
                let loc = min(selected.location, maxLoc)
                let len = min(selected.length, maxLoc - loc)
                editor.selectedRange = NSRange(location: loc, length: len)
            }
        }
    }

    private func applyTypography(to field: NSTextField) {
        let font = Self.metrics.searchFont
        field.font = font
        // Placeholder inherits field font via attributed string
        field.placeholderAttributedString = NSAttributedString(
            string: "Search",
            attributes: [
                .font: font,
                .foregroundColor: NSColor.secondaryLabelColor
            ]
        )
    }

    final class Coordinator: NSObject, NSTextFieldDelegate {
        var parent: SearchTextField
        weak var field: NSTextField?
        private var focusObserver: NSObjectProtocol?
        private var selectAllObserver: NSObjectProtocol?
        private var typographyObserver: NSObjectProtocol?

        init(_ parent: SearchTextField) {
            self.parent = parent
        }

        deinit {
            if let focusObserver {
                NotificationCenter.default.removeObserver(focusObserver)
            }
            if let selectAllObserver {
                NotificationCenter.default.removeObserver(selectAllObserver)
            }
            if let typographyObserver {
                NotificationCenter.default.removeObserver(typographyObserver)
            }
            DistributedNotificationCenter.default().removeObserver(self)
        }

        func observeFocus() {
            ensureFocusObservers()
        }

        func ensureFocusObservers() {
            guard parent.acceptsFocus else { return }
            guard focusObserver == nil else { return }
            focusObserver = NotificationCenter.default.addObserver(
                forName: .veloxFocusSearch,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                self?.focusField()
            }
            selectAllObserver = NotificationCenter.default.addObserver(
                forName: .veloxSelectAllSearchText,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                self?.selectAll()
            }
            // Focus once the panel is on screen
            DispatchQueue.main.async { [weak self] in
                self?.focusField()
            }
        }

        func observeTypography() {
            typographyObserver = NotificationCenter.default.addObserver(
                forName: NSWindow.didChangeBackingPropertiesNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                guard let self, let field = self.field else { return }
                self.parent.applyTypography(to: field)
            }
            // System text size changes
            DistributedNotificationCenter.default().addObserver(
                self,
                selector: #selector(systemTypographyChanged),
                name: NSNotification.Name("AppleTextScalingFactorDidChangeNotification"),
                object: nil
            )
        }

        @objc private func systemTypographyChanged() {
            guard let field else { return }
            parent.applyTypography(to: field)
        }

        func focusField() {
            guard let field else { return }
            field.window?.makeFirstResponder(field)
        }

        func selectAll() {
            guard let field else { return }
            focusField()
            // Field editor may appear on next runloop tick after becoming first responder
            DispatchQueue.main.async {
                if let editor = field.currentEditor() as? NSTextView
                    ?? field.window?.fieldEditor(true, for: field) as? NSTextView {
                    editor.selectAll(nil)
                } else {
                    field.selectText(nil)
                }
            }
        }

        func controlTextDidChange(_ obj: Notification) {
            guard let field = obj.object as? NSTextField else { return }
            parent.text = field.stringValue
        }

        func control(
            _ control: NSControl,
            textView: NSTextView,
            doCommandBy commandSelector: Selector
        ) -> Bool {
            if commandSelector == #selector(NSResponder.insertNewline(_:)) {
                parent.onSubmit()
                return true
            }
            if commandSelector == #selector(NSResponder.selectAll(_:)) {
                textView.selectAll(nil)
                return true
            }
            return false
        }
    }
}

/// Ensures the field can own first responder inside a nonactivating panel
private final class SelectAllTextField: NSTextField {
    var allowsFocus = true
    override var acceptsFirstResponder: Bool { allowsFocus }

    override func becomeFirstResponder() -> Bool {
        let ok = super.becomeFirstResponder()
        if ok {
            // Place caret at end on first focus (Spotlight-like)
            currentEditor()?.selectedRange = NSRange(location: stringValue.utf16.count, length: 0)
        }
        return ok
    }
}

struct ResultRow: View {
    let item: SearchResult
    let isSelected: Bool
    var theme: Theme = ThemeCatalog.glass
    var highlight: SelectionStyle = HighlightCatalog.style(for: .accent)

    var body: some View {
        HStack(spacing: Constants.Panel.stackSpacing) {
            icon
                .frame(width: Constants.Panel.iconColumn, height: Constants.Panel.iconColumn)

            VStack(alignment: .leading, spacing: 2) {
                Text(item.title)
                    .font(.system(size: 15, weight: .medium))
                    .lineLimit(1)
                Text(item.subtitle)
                    .font(.system(size: 11))
                    .foregroundStyle(subtitleColor)
                    .lineLimit(1)
            }
            Spacer(minLength: 8)
            if isSelected {
                Text("⏎")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(hintColor)
                    .padding(.trailing, 4)
            }
        }
        .padding(.horizontal, Constants.Panel.resultInsetX)
        .padding(.vertical, 8)
        .frame(height: SearchPanelController.resultRowHeight)
        .background(
            RoundedRectangle(cornerRadius: theme.rowCornerRadius, style: .continuous)
                .fill(isSelected ? highlight.color : Color.clear)
        )
        .foregroundStyle(titleColor)
        .padding(.horizontal, Constants.Panel.resultInsetX)
    }

    private var titleColor: Color {
        if isSelected && highlight.invertLabels { return .white }
        return .primary
    }

    private var subtitleColor: Color {
        if isSelected && highlight.invertLabels { return .white.opacity(0.85) }
        return .secondary
    }

    private var hintColor: Color {
        if highlight.invertLabels { return .white.opacity(0.9) }
        return .secondary
    }

    @ViewBuilder
    private var icon: some View {
        switch item.kind {
        case .app:
            if let app = item.app {
                Image(nsImage: app.icon(size: 32))
                    .resizable()
                    .interpolation(.high)
                    .frame(width: 32, height: 32)
            } else {
                Image(systemName: "app")
                    .frame(width: 32, height: 32)
            }
        case .calculation:
            Image(systemName: "function")
                .font(.system(size: 16, weight: .semibold))
                .frame(width: 32, height: 32)
                .background(Circle().fill(Color.orange.opacity(isSelected ? 0.35 : 0.2)))
        case .currency:
            Image(systemName: "dollarsign.circle")
                .font(.system(size: 18, weight: .semibold))
                .frame(width: 32, height: 32)
                .background(Circle().fill(Color.green.opacity(isSelected ? 0.35 : 0.2)))
        }
    }
}

extension Notification.Name {
    static let veloxHidePanel = Constants.Notify.hidePanel
}
