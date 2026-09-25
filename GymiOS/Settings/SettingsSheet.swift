import SwiftUI
import ThubanGymCore
import UniformTypeIdentifiers

/// Settings (board Settings, from Today's sliders): the eight Thuban schemes and the mode, the display unit, the
/// rest timer switches, and Data — import / export gym.json through Files, AirDrop or the share sheet.
struct SettingsSheet: View {
    @Environment(AppModel.self) private var app
    @Environment(\.thubanTheme) private var theme
    @Environment(\.dismiss) private var dismiss
    var embedded = false

    var body: some View {
        if embedded {
            SettingsContent(showsTitle: true).phoneScreen(theme).pageNavigationTitle("Settings")
        } else {
            NavigationStack {
                SettingsContent()
                    .phoneScreen(theme)
                    .navigationTitle("Settings")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() }.fontWeight(.semibold) }
                    }
            }
            .presentationBackground(theme.bgColor)
        }
    }
}

struct SettingsContent: View {
    @Environment(AppModel.self) private var app
    @Environment(\.thubanTheme) private var theme
    /// iPad sidebar: the page draws its own serif title.
    var showsTitle = false

    @State private var importing = false
    @State private var exporting = false
    @State private var message: String?
    @State private var errorText: String?

    var body: some View {
        @Bindable var app = app
        ScrollViewReader { proxy in
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                if showsTitle { PageTitle("Settings").padding(.bottom, 16) }
                SectionHeading("Appearance")
                Card {
                    VStack(alignment: .leading, spacing: 12) {
                        schemes
                        (Text(app.schemeLabel).fontWeight(.semibold).foregroundColor(theme.inkColor)
                         + Text(" · the eight Thuban schemes, shared with the Mac").foregroundColor(theme.inkDimColor))
                            .font(.subheadline)
                    }
                    .padding(16)
                    RowDivider(inset: 0)
                    row("Mode") {
                        PhoneSegmented(options: AppearanceMode.allCases.map { ($0, $0.label) },
                                       selection: Binding(get: { app.themeSelection.mode }, set: { app.setAppearanceMode($0) }),
                                       accessibilityLabel: "Appearance mode")
                            .frame(maxWidth: 220)
                    }
                }

                SectionHeading("Units").padding(.top, 22)
                Card {
                    row("Weight") {
                        PhoneSegmented(options: [(WeightUnit.lbs, "lb"), (WeightUnit.kg, "kg")],
                                       selection: Binding(get: { app.unit }, set: { app.setUnit($0) }),
                                       accessibilityLabel: "Weight unit")
                            .frame(maxWidth: 220)
                    }
                }
                CardFootnote(text: "Display only. Weights are stored in kg, so switching never rounds your history.")

                SectionHeading("During a workout").padding(.top, 22)
                Card {
                    row("Default rest") {
                        Menu {
                            ForEach([60, 75, 90, 105, 120, 150, 180, 240, 300], id: \.self) { seconds in
                                Button(PhoneFormat.rest(seconds)) { app.updateSettings { $0.restSeconds = seconds } }
                            }
                        } label: {
                            HStack(spacing: 6) {
                                Text(PhoneFormat.rest(app.settings.restSeconds)).font(PhoneFont.mono(17)).foregroundStyle(theme.inkDimColor)
                                Icon(.reorder, size: 14).foregroundStyle(theme.inkFaintColor)
                            }
                            .frame(minHeight: PhoneMetrics.hit)
                        }
                        .accessibilityLabel("Default rest, \(PhoneFormat.rest(app.settings.restSeconds))")
                    }
                    RowDivider()
                    toggle("Start rest when a set is logged", isOn: $app.preferences.restAutoStart)
                    RowDivider()
                    toggle("Haptic and sound at 0:00", isOn: $app.preferences.restAlert)
                    RowDivider()
                    toggle("Keep the screen awake", isOn: $app.preferences.keepScreenAwake)
                }
                CardFootnote(text: "A workout's own rest (Workouts ▸ a workout) wins over the default.")

                SectionHeading("Data").padding(.top, 22).id(SettingsAnchor.data)
                Card {
                    toggle("iCloud Sync", isOn: $app.preferences.iCloudSync)
                    RowDivider()
                    syncStatusRow
                    RowDivider()
                    actionRow("Import gym.json…", icon: .download) { importing = true }
                    RowDivider()
                    actionRow("Export gym.json…", icon: .file) { exporting = true }
                }
                CardFootnote(text: dataFootnote)
                if let message {
                    Text(message).font(.footnote.weight(.semibold)).foregroundStyle(theme.posTextColor).padding(.horizontal, 4).padding(.top, 6)
                }

                SectionHeading("About").padding(.top, 22)
                Card {
                    HStack(spacing: 12) {
                        AppArtView(size: 28, theme: theme)
                        VStack(alignment: .leading, spacing: 1) {
                            Text("Thuban Gym").font(PhoneFont.serif(17, relativeTo: .headline)).foregroundStyle(theme.inkColor)
                            Text("Version \(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "–")")
                                .font(.footnote).foregroundStyle(theme.inkDimColor)
                        }
                        Spacer()
                    }
                    .padding(16)
                }
            }
            .padding(.horizontal, PhoneMetrics.gutter)
            .padding(.top, 12)
            .padding(.bottom, 32)
        }
        .onChange(of: app.smokeSettingsAnchor, initial: true) { _, anchor in
            guard let anchor else { return }
            proxy.scrollTo(anchor, anchor: .top)
        }
        }
        .fileExporter(isPresented: $exporting, document: app.exportDocument, contentType: .json, defaultFilename: "gym") { result in
            if case .failure(let error) = result { errorText = error.localizedDescription } else { message = "Exported gym.json." }
        }
        .gymImport(isPresented: $importing) { text in message = text }
        .alert("Could not use that file", isPresented: Binding(get: { errorText != nil }, set: { if !$0 { errorText = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorText ?? "")
        }
    }

    // MARK: Pieces

    private var schemes: some View {
        HStack(spacing: 0) {
            ForEach(SchemePresets.all) { scheme in
                let selected = scheme.id == app.themeSelection.schemeId
                Button { app.selectScheme(id: scheme.id) } label: {
                    Circle()
                        .fill(Color(hex: scheme.accent))
                        .frame(width: 28, height: 28)
                        .padding(4)
                        .overlay(Circle().strokeBorder(selected ? theme.inkColor : .clear, lineWidth: 2))
                        .frame(width: 40, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .frame(maxWidth: .infinity)
                .accessibilityLabel(scheme.label)
                .accessibilityAddTraits(selected ? [.isSelected, .isButton] : .isButton)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Color scheme")
    }

    private func row<T: View>(_ label: String, @ViewBuilder trailing: () -> T) -> some View {
        HStack(spacing: 12) {
            Text(label).font(.body).foregroundStyle(theme.inkColor)
            Spacer(minLength: 8)
            trailing()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .frame(minHeight: 58)
    }

    private func toggle(_ label: String, isOn: Binding<Bool>) -> some View {
        Toggle(label, isOn: isOn)
            .font(.body)
            .foregroundStyle(theme.inkColor)
            .tint(theme.accentColor)
            .padding(.horizontal, 16)
            .frame(minHeight: 58)
    }

    private func actionRow(_ label: String, icon: IconName, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Icon(icon, size: 20).foregroundStyle(theme.brassInkColor)
                Text(label).font(.body).foregroundStyle(theme.inkColor)
                Spacer()
                RowChevron()
            }
            .padding(.horizontal, 16)
            .frame(minHeight: 58)
            .contentShape(Rectangle())
        }
        .buttonStyle(RowPressStyle())
    }

    private var dataFootnote: String {
        let local = app.localContents
        let sync = app.syncStatus.hint(device: "iPhone").map { $0 + " " } ?? ""
        return sync + "With iCloud Sync on, this phone and the Mac share one log through your own iCloud, merged set by set. Import and export still move a gym.json by hand (AirDrop, Files). On this phone: "
            + PhoneFormat.contents(local) + "."
    }

    /// "Up to date · last synced 9:41 AM" with a status dot, and Sync now.
    private var syncStatusRow: some View {
        let status = app.syncStatus
        return HStack(spacing: 10) {
            Circle().fill(syncDot(status.tone)).frame(width: 8, height: 8)
            Text(status.text())
                .font(.subheadline)
                .foregroundStyle(status.tone == .bad ? theme.negTextColor : theme.inkDimColor)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityLabel("Sync status: \(status.text())")
            Spacer(minLength: 8)
            Button("Sync now") { app.syncNow() }
                .font(.body.weight(.semibold))
                .foregroundStyle(app.canSyncNow ? theme.brassInkColor : theme.inkFaintColor)
                .disabled(!app.canSyncNow)
                .frame(minHeight: PhoneMetrics.hit)
                .accessibilityHint("Merges this phone's log with the copy in iCloud")
        }
        .padding(.horizontal, 16)
        .frame(minHeight: 58)
    }

    private func syncDot(_ tone: SyncTone) -> Color {
        switch tone {
        case .good: return theme.posColor
        case .busy: return theme.signalColor
        case .idle: return theme.line2Color
        case .bad: return theme.negColor
        }
    }

}

/// "Import gym.json…": pick a file, show what it holds, confirm, snapshot the phone's log, replace it.
struct GymImportModifier: ViewModifier {
    @Environment(AppModel.self) private var app
    @Binding var isPresented: Bool
    var onDone: (String) -> Void
    @State private var pending: AppModel.PendingImport?
    @State private var errorText: String?

    func body(content: Content) -> some View {
        content
            .fileImporter(isPresented: $isPresented, allowedContentTypes: [.json, .data]) { result in
                switch result {
                case .success(let url):
                    do { pending = try app.readImport(url) } catch { errorText = error.localizedDescription }
                case .failure(let error):
                    errorText = error.localizedDescription
                }
            }
            .confirmationDialog(pending.map { app.isFirstRun ? "Import \($0.fileName)?" : "Replace this phone's log with \($0.fileName)?" } ?? "",
                                isPresented: Binding(get: { pending != nil }, set: { if !$0 { pending = nil } }),
                                titleVisibility: .visible, presenting: pending) { pending in
                Button(app.isFirstRun ? "Import" : "Replace with \(pending.fileName)", role: app.isFirstRun ? nil : .destructive) {
                    do {
                        try app.applyImport(pending)
                        onDone("Imported \(PhoneFormat.count(pending.contents.workouts, "workout")) and \(PhoneFormat.count(pending.contents.sets, "set")). The previous log was saved as a snapshot.")
                    } catch { errorText = error.localizedDescription }
                }
                Button("Cancel", role: .cancel) {}
            } message: { pending in
                Text(PhoneFormat.contents(pending.contents) + (app.isFirstRun ? "." : ". A snapshot of the phone's current log is kept first.")
                     + (!app.isFirstRun && app.iCloudSyncEnabled && app.syncStatus.isOn ? " With iCloud Sync on, the Mac gets this log too." : ""))
            }
            .alert("Could not use that file", isPresented: Binding(get: { errorText != nil }, set: { if !$0 { errorText = nil } })) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(errorText ?? "")
            }
    }
}

extension View {
    func gymImport(isPresented: Binding<Bool>, onDone: @escaping (String) -> Void = { _ in }) -> some View {
        modifier(GymImportModifier(isPresented: isPresented, onDone: onDone))
    }
}

/// Scroll targets inside Settings.
enum SettingsAnchor {
    static let data = "settings-data"
}
