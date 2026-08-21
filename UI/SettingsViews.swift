import SwiftUI
import AppKit
import Combine

enum SettingsFooter {
    static let rebuildIndex = "Rebuild App Index"
    static let resetPosition = "Reset Position"
    static let leading = [rebuildIndex, resetPosition]
}

enum SettingsSearchCard {
    static let launchAtLogin = "Start at login"
}

enum SettingsChrome {
    static let pagePadding: CGFloat = 12
    static let cardPadding: CGFloat = 10
    static let cardStackSpacing: CGFloat = 10
    static let themeToControlsGap: CGFloat = 16
    static let footerGap: CGFloat = 8
    static let themeColumns = 8
}

struct SettingsRootView: View {
    @ObservedObject private var prefs = Preferences.shared

    var body: some View {
        VStack(spacing: SettingsChrome.cardStackSpacing) {
            HStack(alignment: .top, spacing: 10) {
                hotkeyCard
                searchCard
            }

            appearanceCard

            HStack {
                Button(SettingsFooter.rebuildIndex) {
                    Task { await AppIndex.shared.rebuild() }
                }
                .controlSize(.small)
                Button(SettingsFooter.resetPosition) {
                    prefs.resetPanelPosition()
                }
                .controlSize(.small)
                Spacer()
                Text(AppVersion.label())
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .monospacedDigit()
                Spacer()
                Button("Quit \(Constants.App.name)", role: .destructive) {
                    NSApp.terminate(nil)
                }
                .controlSize(.small)
            }
            .padding(.top, SettingsChrome.footerGap)
        }
        .padding(SettingsChrome.pagePadding)
        .frame(width: SettingsWindowPlacement.windowSize.width)
        .fixedSize(horizontal: false, vertical: true)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private var hotkeyCard: some View {
        settingsCard(title: "Open \(Constants.App.name) Hotkey", icon: "keyboard", tint: .purple) {
            HotKeyRecorder(shortcut: $prefs.openShortcut)
            Text("Opens \(Constants.App.name) from anywhere")
                .font(.system(size: 13, weight: .medium))
            Text("Click the keys to remap. Disable Spotlight’s shortcut if you pick ⌘Space")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            if HotKey.lastRegistrationFailed {
                Text("Could not register this shortcut. Try another combo")
                    .font(.caption)
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var searchCard: some View {
        settingsCard {
            symbolRow(icon: "power", tint: .blue, title: SettingsSearchCard.launchAtLogin) {
                Toggle("", isOn: $prefs.launchAtLogin)
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .controlSize(.small)
            }
            symbolRow(icon: "list.number", tint: .blue, title: "Max app results") {
                Stepper(value: $prefs.maxResults, in: Constants.Defaults.maxResultsRange) {
                    Text("\(prefs.maxResults)")
                        .monospacedDigit()
                        .frame(minWidth: 22, alignment: .trailing)
                }
                .controlSize(.small)
            }
            symbolRow(icon: "apple.logo", tint: .pink, title: "Include system apps") {
                Toggle("", isOn: $prefs.includeSystemApps)
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .controlSize(.small)
            }
            symbolRow(icon: "folder", tint: .orange, title: "Show full path") {
                Toggle("", isOn: $prefs.showPathInSubtitle)
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .controlSize(.small)
            }
            symbolRow(icon: "function", tint: .purple, title: "Math") {
                Toggle("", isOn: $prefs.mathEnabled)
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .controlSize(.small)
            }
            symbolRow(icon: "dollarsign.circle", tint: .green, title: "Currency conversion") {
                Toggle("", isOn: $prefs.currencyEnabled)
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .controlSize(.small)
            }
        }
    }

    private var appearanceCard: some View {
        settingsCard(title: "Appearance", icon: "paintpalette", tint: .teal) {
            HStack(spacing: 6) {
                ForEach(ThemeCatalog.all) { theme in
                    themeSwatch(theme)
                }
            }
            .padding(.bottom, SettingsChrome.themeToControlsGap)
            symbolRow(icon: "paintbrush.pointed", tint: .orange, title: "Highlight") {
                Picker("", selection: $prefs.highlightID) {
                    ForEach(HighlightCatalog.all) { id in
                        Text(id.title).tag(id)
                    }
                }
                .labelsHidden()
                .pickerStyle(.segmented)
                .controlSize(.small)
                .frame(maxWidth: 240)
            }
            symbolRow(icon: "square.dashed", tint: .teal, title: "Corner radius") {
                Slider(
                    value: radiusBinding,
                    in: Double(PanelMetrics.cornerRadiusRange.lowerBound)...Double(PanelMetrics.cornerRadiusRange.upperBound),
                    step: Double(PanelMetrics.cornerRadiusStep)
                )
                .controlSize(.small)
                .frame(width: 120)
                Text("\(Int(prefs.panelCornerRadius.rounded()))")
                    .font(.caption)
                    .monospacedDigit()
                    .frame(minWidth: 18, alignment: .trailing)
            }
            symbolRow(icon: "display", tint: .indigo, title: "Show on") {
                Picker("", selection: $prefs.panelScreenPolicy) {
                    ForEach(PanelScreenPolicy.allCases) { policy in
                        Text(policy.title).tag(policy)
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .controlSize(.small)
                .frame(maxWidth: 210)
            }
        }
    }

    private func themeSwatch(_ theme: Theme) -> some View {
        let selected = prefs.themeID == theme.id
        return Button {
            prefs.themeID = theme.id
        } label: {
            VStack(spacing: 6) {
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(theme.previewColor)
                    .overlay(
                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .strokeBorder(selected ? Color.accentColor : Color.primary.opacity(0.12), lineWidth: selected ? 2 : 1)
                    )
                    .frame(width: 44, height: 28)
                Text(theme.name)
                    .font(.system(size: 10, weight: selected ? .semibold : .regular))
                    .foregroundStyle(selected ? Color.primary : Color.secondary)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.plain)
        .help(theme.name)
    }

    private var radiusBinding: Binding<Double> {
        Binding(
            get: { Double(prefs.panelCornerRadius) },
            set: { prefs.panelCornerRadius = PanelMetrics.clampedRadius(CGFloat($0)) }
        )
    }

    private func settingsCard<Content: View>(
        title: String? = nil,
        icon: String? = nil,
        tint: Color = .blue,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            if let title, let icon {
                HStack(spacing: 8) {
                    Image(systemName: icon)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: 22, height: 22)
                        .background(tint.gradient, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                    Text(title)
                        .font(.system(size: 13, weight: .semibold))
                }
            }
            content()
        }
        .padding(SettingsChrome.cardPadding)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor))
        )
    }

    private func symbolRow<Content: View>(
        icon: String,
        tint: Color,
        title: String,
        @ViewBuilder control: () -> Content
    ) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 22, height: 22)
                .background(tint.gradient, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
            Text(title)
                .lineLimit(1)
            Spacer(minLength: 8)
            control()
        }
    }
}

struct HotKeyRecorder: View {
    @Binding var shortcut: KeyShortcut
    @State private var isRecording = false
    @StateObject private var capture = HotKeyCaptureMonitor()

    var body: some View {
        Button(action: toggleRecording) {
            HStack(spacing: 6) {
                if isRecording {
                    Text("Press shortcut")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(Array(shortcut.symbols.enumerated()), id: \.offset) { _, symbol in
                        Keycap(label: symbol)
                    }
                }
            }
            .padding(.horizontal, 4)
            .padding(.vertical, 3)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(isRecording ? Color.accentColor : Color.clear, lineWidth: 1.5)
            )
        }
        .buttonStyle(.plain)
        .help(isRecording ? "Press a new shortcut, Esc to cancel" : "Click to change the shortcut")
        .onDisappear { stopRecording(resume: true) }
        .onReceive(NotificationCenter.default.publisher(for: .veloxCancelHotKeyCapture)) { _ in
            stopRecording(resume: true)
        }
    }

    private func toggleRecording() {
        if isRecording {
            stopRecording(resume: true)
        } else {
            startRecording()
        }
    }

    private func startRecording() {
        isRecording = true
        capture.start(
            onCapture: { newShortcut in
                shortcut = newShortcut
                stopRecording(resume: false)
            },
            onCancel: {
                stopRecording(resume: true)
            }
        )
    }

    private func stopRecording(resume: Bool) {
        capture.stop()
        isRecording = false
        if resume {
            NotificationCenter.default.post(name: .veloxResumeOpenHotKey, object: nil)
        }
    }
}

@MainActor
final class HotKeyCaptureMonitor: ObservableObject {
    private var monitor: Any?

    func start(onCapture: @escaping (KeyShortcut) -> Void, onCancel: @escaping () -> Void) {
        stop()
        NotificationCenter.default.post(name: .veloxSuspendOpenHotKey, object: nil)
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            if event.keyCode == 53 {
                onCancel()
                return nil
            }
            if let shortcut = KeyShortcut.from(event: event) {
                onCapture(shortcut)
                return nil
            }
            return nil
        }
    }

    func stop() {
        if let monitor {
            NSEvent.removeMonitor(monitor)
            self.monitor = nil
        }
    }

    deinit {
        if let monitor {
            NSEvent.removeMonitor(monitor)
        }
    }
}

struct Keycap: View {
    let label: String

    var body: some View {
        Text(label)
            .font(.system(size: 13, weight: .semibold, design: .rounded))
            .padding(.horizontal, 9)
            .padding(.vertical, 5)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(Color(nsColor: .quaternaryLabelColor).opacity(0.22))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
            )
    }
}
