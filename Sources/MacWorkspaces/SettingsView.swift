import SwiftUI
import MacWorkspacesCore

struct SettingsView: View {
    var body: some View {
        TabView {
            GeneralTab().tabItem { Label("General", systemImage: "gearshape") }
            ShortcutsTab().tabItem { Label("Shortcuts", systemImage: "keyboard") }
            WorkspacesTab().tabItem { Label("Workspaces", systemImage: "square.grid.3x3") }
            ConfigurationTab().tabItem { Label("Configuration", systemImage: "doc.text") }
        }
        .padding(16)
        .frame(minWidth: 640, minHeight: 520)
    }
}

struct GeneralTab: View {
    @EnvironmentObject var model: AppModel
    @State private var loginItemOn = LoginItem.isEnabled
    @State private var loginError: String?

    var body: some View {
        Form {
            Section("Companion") {
                Toggle("Open mac-workspaces at login", isOn: $loginItemOn)
                    .onChange(of: loginItemOn) { _, on in
                        do { try LoginItem.set(on); loginError = nil } catch { loginError = error.localizedDescription }
                        loginItemOn = LoginItem.isEnabled
                    }
                Text(loginError ?? LoginItem.statusDescription).font(.caption).foregroundStyle(loginError == nil ? Color.secondary : Color.red)
                HStack {
                    Text(model.isPaused ? "Shortcuts are paused." : "Shortcuts are active.")
                    Spacer()
                    Button(model.isPaused ? "Resume" : "Pause") { model.togglePause() }
                        .disabled(!model.aerospaceReachable)
                }
                Text("Pausing switches AeroSpace to an empty binding mode, so product shortcuts stop intercepting keys while tiling keeps working.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("Tiling") {
                Picker("Default layout", selection: $model.settings.orientation) {
                    ForEach(TilingOrientation.allCases, id: \.self) { Text($0.title).tag($0) }
                }
                Toggle("Start AeroSpace at login", isOn: $model.settings.startAeroSpaceAtLogin)
                Text("Changes here are written to the AeroSpace config when you apply it (Configuration tab).")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("Status") {
                LabeledContent("AeroSpace", value: model.aerospaceReachable ? (model.aerospaceVersion ?? "Connected") : (model.statusProblem ?? "Not connected"))
                LabeledContent("Terminal control", value: model.automationStatus.label)
            }
        }
        .formStyle(.grouped)
    }
}

struct ShortcutsTab: View {
    @EnvironmentObject var model: AppModel

    private var groups: [(String, [Action])] {
        var order: [String] = []
        var map: [String: [Action]] = [:]
        for a in Action.allCases {
            if map[a.group] == nil { order.append(a.group) }
            map[a.group, default: []].append(a)
        }
        return order.map { ($0, map[$0]!) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            List {
                ForEach(groups, id: \.0) { group in
                    Section(group.0) {
                        ForEach(group.1, id: \.self) { action in
                            HStack {
                                Text(action.title)
                                Spacer()
                                ShortcutRecorder(shortcut: Binding(
                                    get: { model.settings.shortcut(for: action) },
                                    set: { model.settings.setShortcut($0, for: action) }
                                ))
                                .frame(width: 130)
                                Button { model.settings.setShortcut(nil, for: action) } label: { Image(systemName: "xmark.circle") }
                                    .buttonStyle(.borderless).help("Remove shortcut (menu only)")
                                Button { model.settings.setShortcut(action.defaultShortcut, for: action) } label: { Image(systemName: "arrow.uturn.backward") }
                                    .buttonStyle(.borderless).help("Restore default")
                                    .disabled(model.settings.shortcut(for: action) == action.defaultShortcut)
                            }
                            .foregroundStyle(issueColor(for: action))
                        }
                    }
                }
            }
            IssueList(issues: model.issues)
            HStack {
                Button("Restore All Defaults") { model.settings.resetBindings() }
                Spacer()
                ApplyBar()
            }
        }
    }

    private func issueColor(for action: Action) -> Color {
        model.issues.contains { $0.severity == .error && $0.actions.contains(action) } ? .red : .primary
    }
}

/// Shows whether edits are applied and offers Apply / Review.
struct ApplyBar: View {
    @EnvironmentObject var model: AppModel
    @State private var showingDiff = false

    var body: some View {
        HStack {
            if let plan = model.configPlan, plan.hasChanges {
                Text("Not applied yet").font(.caption).foregroundStyle(.orange)
                if plan.requiresReview || plan.state == .managedUnchanged {
                    Button("Review…") { showingDiff = true }
                }
                if !plan.requiresReview {
                    Button("Apply") { model.applyConfig() }.keyboardShortcut(.defaultAction)
                }
            } else if model.configPlan != nil {
                Text("Applied").font(.caption).foregroundStyle(.secondary)
            }
        }
        .disabled(model.hasBlockingIssues)
        .sheet(isPresented: $showingDiff) { ConfigReviewSheet(isPresented: $showingDiff) }
    }
}

struct WorkspacesTab: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        Form {
            Section {
                ForEach(Action.workspaceNumbers, id: \.self) { n in
                    TextField("Workspace \(n)", text: Binding(
                        get: { model.settings.workspaceNames[String(n)] ?? "" },
                        set: { model.settings.workspaceNames[String(n)] = $0 }
                    ), prompt: Text("Optional name"))
                }
            } header: {
                Text("Workspace names")
            } footer: {
                Text("Names appear in the menu bar and menu. They are saved immediately and kept across restarts. These are AeroSpace virtual workspaces, not macOS Spaces.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("Always float these apps (bundle IDs)") {
                TextField("One per line", text: Binding(
                    get: { model.settings.floatingAppBundleIDs.joined(separator: "\n") },
                    set: { model.settings.floatingAppBundleIDs = $0.split(whereSeparator: \.isNewline).map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty } }
                ), axis: .vertical)
                .lineLimit(3...8)
                .font(.system(.body, design: .monospaced))
                Text("Dialogs and utility windows float automatically. Find an app's ID with: aerospace list-apps")
                    .font(.caption).foregroundStyle(.secondary)
            }
            HStack { Spacer(); ApplyBar() }
        }
        .formStyle(.grouped)
    }
}

struct ConfigurationTab: View {
    @EnvironmentObject var model: AppModel
    @State private var showingDiff = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            GroupBox("AeroSpace configuration") {
                ConfigStatusView(showingDiff: $showingDiff)
                    .frame(maxWidth: .infinity, alignment: .leading)
                HStack {
                    Button("Show Generated Config…") { showingDiff = true }
                    Button("Copy Generated Config") {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(model.generator.render(model.settings), forType: .string)
                    }
                    if let plan = model.configPlan, plan.currentContents != nil {
                        Button("Reveal in Finder") { NSWorkspace.shared.activateFileViewerSelecting([plan.target]) }
                    }
                }
                Text("Prefer to keep your own config? Copy the generated file and merge the [mode.main.binding] and [mode.paused.binding] sections yourself.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            GroupBox("Backups") {
                if model.backups.isEmpty {
                    Text("No backups yet. A backup is created automatically before any config is replaced.")
                        .foregroundStyle(.secondary).frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    List(model.backups, id: \.self) { url in
                        HStack {
                            Text(url.lastPathComponent).font(.system(.body, design: .monospaced))
                            Spacer()
                            Button("Reveal") { NSWorkspace.shared.activateFileViewerSelecting([url]) }
                            Button("Restore") { model.restore(url) }
                        }
                    }
                    .frame(minHeight: 160)
                }
                Text("Restoring backs up the current file first, so it can be undone.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
        }
        .sheet(isPresented: $showingDiff) { ConfigReviewSheet(isPresented: $showingDiff) }
    }
}

struct ShortcutReferenceView: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        List {
            if model.isPaused {
                Text("Shortcuts are paused. Resume from the menu bar.").foregroundStyle(.orange)
            }
            ForEach(["Terminal", "Windows", "Workspaces", "Monitors", "Companion"], id: \.self) { group in
                Section(group) {
                    ForEach(Action.allCases.filter { $0.group == group }, id: \.self) { action in
                        HStack {
                            Text(action.title)
                            Spacer()
                            Text(model.settings.shortcut(for: action)?.symbolLabel ?? "Menu only")
                                .font(.system(.body, design: .monospaced))
                                .foregroundStyle(model.settings.shortcut(for: action) == nil ? .secondary : .primary)
                        }
                    }
                }
            }
        }
    }
}
