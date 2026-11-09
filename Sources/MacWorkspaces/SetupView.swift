import SwiftUI
import MacWorkspacesCore

struct SetupView: View {
    @EnvironmentObject var model: AppModel
    var onOpenSettings: () -> Void
    var onClose: () -> Void
    @State private var showingDiff = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text("Set up mac-workspaces").font(.title2.bold())
                Text("Keyboard-driven terminals, automatic tiling and numbered workspaces, powered by AeroSpace.")
                    .foregroundStyle(.secondary)

                GroupBox {
                    Text("Workspaces here are **AeroSpace virtual workspaces** (1–9). They are separate from native macOS Spaces and Mission Control: switching happens instantly by showing and hiding windows, and macOS Spaces are left alone.")
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                step(1, "Install AeroSpace", done: model.cliInstalled || AeroSpaceApp.isInstalled) {
                    Text("AeroSpace does the tiling and workspaces. Install it with Homebrew in Terminal:")
                    HStack {
                        Text(AeroSpaceApp.installCommand).font(.system(.body, design: .monospaced)).textSelection(.enabled)
                        Button("Copy") {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(AeroSpaceApp.installCommand, forType: .string)
                        }
                    }
                    Link("AeroSpace guide", destination: AeroSpaceApp.guideURL)
                }

                step(2, "Start AeroSpace and allow Accessibility", done: model.aerospaceReachable) {
                    Text("AeroSpace needs Accessibility permission to move and resize windows. macOS asks the first time AeroSpace starts.")
                    if let version = model.aerospaceVersion {
                        Text("Connected: \(version.replacingOccurrences(of: "\n", with: " "))").foregroundStyle(.secondary)
                    } else if AeroSpaceApp.isRunning {
                        Text("AeroSpace is running but not answering commands. Check that it is allowed under Accessibility, then restart it.").foregroundStyle(.orange)
                    }
                    HStack {
                        Button("Open AeroSpace") { AeroSpaceApp.launch() }.disabled(!AeroSpaceApp.isInstalled)
                        Button("Accessibility Settings…") { SystemSettings.openAccessibility() }
                    }
                }

                step(3, "Allow mac-workspaces to control Terminal", done: model.automationStatus == .granted) {
                    Text("To open a **new** Terminal window on every Command + Return press, mac-workspaces sends Terminal a \"new window\" command (Automation permission). Without it, the launch shortcut cannot work.")
                    Text("Status: \(model.automationStatus.label)").foregroundStyle(model.automationStatus == .denied ? .red : .secondary)
                    HStack {
                        Button("Request Permission") { model.checkAutomation(ask: true) }
                            .help("Opens Terminal if needed; macOS only asks while Terminal is running.")
                        Button("Automation Settings…") { SystemSettings.openAutomation() }
                    }
                }

                step(4, "Review shortcuts", done: !model.hasBlockingIssues) {
                    Text("These shortcuts become global AeroSpace bindings. **Command + Return** is used by some apps (e.g. to send a message); while bound, those apps will not receive it.")
                    BindingSummary()
                    IssueList(issues: model.issues)
                    Button("Change Shortcuts…", action: onOpenSettings)
                }

                step(5, "Apply the AeroSpace configuration", done: model.configPlan.map { $0.state == .managedUnchanged && !$0.hasChanges } ?? false) {
                    ConfigStatusView(showingDiff: $showingDiff)
                }

                HStack {
                    Spacer()
                    Button("Check Again") { model.refreshStatus() }
                    Button("Done") {
                        model.settings.setupCompleted = true
                        onClose()
                    }
                    .keyboardShortcut(.defaultAction)
                }
            }
            .padding(24)
        }
        .sheet(isPresented: $showingDiff) { ConfigReviewSheet(isPresented: $showingDiff) }
    }

    private func step<Content: View>(_ n: Int, _ title: String, done: Bool, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: done ? "checkmark.circle.fill" : "\(n).circle")
                    .foregroundStyle(done ? .green : .secondary)
                    .font(.title3)
                Text(title).font(.headline)
            }
            VStack(alignment: .leading, spacing: 8) { content() }
                .padding(.leading, 30)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

/// Config state + apply / review buttons. Never replaces a user's config without review.
struct ConfigStatusView: View {
    @EnvironmentObject var model: AppModel
    @Binding var showingDiff: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let problem = model.configProblem {
                Text(problem).foregroundStyle(.red)
            } else if let plan = model.configPlan {
                switch plan.state {
                case .missing:
                    Text("No AeroSpace config exists yet. A new one will be created at \(plan.target.path).")
                    Button("Create Configuration") { model.applyConfig() }.disabled(model.hasBlockingIssues)
                case .managedUnchanged:
                    Text(plan.hasChanges ? "Your shortcut changes are not applied yet." : "The mac-workspaces configuration is active at \(plan.target.path).")
                    if plan.hasChanges {
                        HStack {
                            Button("Review Changes…") { showingDiff = true }
                            Button("Apply") { model.applyConfig() }.disabled(model.hasBlockingIssues)
                        }
                    }
                case .managedEdited, .userOwned:
                    Text(plan.state == .userOwned
                         ? "An existing AeroSpace config was found at \(plan.target.path). It will not be changed until you review the proposed replacement. A backup is made first and can be restored any time."
                         : "The config at \(plan.target.path) was edited by hand. Review the differences before replacing it; a backup is made first.")
                    HStack {
                        Button("Review and Apply…") { showingDiff = true }.disabled(model.hasBlockingIssues)
                        Text("or keep your config and add the bindings yourself (see Settings › Configuration).")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
        }
    }
}

struct ConfigReviewSheet: View {
    @EnvironmentObject var model: AppModel
    @Binding var isPresented: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Review configuration changes").font(.title3.bold())
            if let plan = model.configPlan {
                Text("Target: \(plan.target.path)").font(.caption).foregroundStyle(.secondary)
                if plan.currentContents != nil {
                    Text("Lines starting with − will be removed, + will be added. The current file is backed up before anything is written.")
                        .font(.caption)
                }
                ScrollView([.vertical, .horizontal]) {
                    Text(diffText(plan))
                        .font(.system(size: 11, design: .monospaced))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(8)
                }
                .background(Color(nsColor: .textBackgroundColor))
                .border(Color.secondary.opacity(0.3))
            }
            HStack {
                Spacer()
                Button("Cancel") { isPresented = false }.keyboardShortcut(.cancelAction)
                Button("Back Up and Apply") {
                    model.applyConfig()
                    isPresented = false
                }
                .keyboardShortcut(.defaultAction)
                .disabled(model.hasBlockingIssues)
            }
        }
        .padding(20)
        .frame(minWidth: 640, minHeight: 520)
    }

    private func diffText(_ plan: ConfigPlan) -> AttributedString {
        var out = AttributedString()
        for line in LineDiff.render(plan.currentContents, plan.proposedContents).components(separatedBy: "\n") {
            var a = AttributedString(line + "\n")
            if line.hasPrefix("+ ") { a.foregroundColor = .green }
            else if line.hasPrefix("- ") { a.foregroundColor = .red }
            else { a.foregroundColor = .secondary }
            out += a
        }
        return out
    }
}

struct BindingSummary: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        let s = model.settings
        Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 4) {
            row("Open a new terminal window", s.shortcut(for: .launchTerminal))
            row("Focus left / down / up / right", group(Direction.allCases.map { s.shortcut(for: .focus($0)) }))
            row("Move window", group(Direction.allCases.map { s.shortcut(for: .move($0)) }))
            row("Switch workspace 1–9", rangeLabel(Action.workspaceNumbers.map { s.shortcut(for: .switchWorkspace($0)) }))
            row("Move window to workspace 1–9", rangeLabel(Action.workspaceNumbers.map { s.shortcut(for: .moveToWorkspace($0)) }))
            row("Shrink / grow", group([s.shortcut(for: .shrink), s.shortcut(for: .grow)]))
            row("Toggle horizontal / vertical", s.shortcut(for: .toggleOrientation))
        }
    }

    private func row(_ title: String, _ shortcut: Shortcut?) -> some View { row(title, shortcut?.symbolLabel ?? "—") }

    private func row(_ title: String, _ label: String) -> some View {
        GridRow {
            Text(title)
            Text(label).font(.system(.body, design: .monospaced))
        }
    }

    private func group(_ shortcuts: [Shortcut?]) -> String {
        shortcuts.map { $0?.symbolLabel ?? "—" }.joined(separator: " ")
    }

    private func rangeLabel(_ shortcuts: [Shortcut?]) -> String {
        guard let first = shortcuts.first ?? nil, let last = shortcuts.last ?? nil else { return group(shortcuts) }
        return "\(first.symbolLabel) … \(last.symbolLabel)"
    }
}

struct IssueList: View {
    let issues: [BindingIssue]

    var body: some View {
        if !issues.isEmpty {
            VStack(alignment: .leading, spacing: 4) {
                ForEach(issues, id: \.self) { issue in
                    Label(issue.description, systemImage: issue.severity == .error ? "xmark.octagon.fill" : "exclamationmark.triangle.fill")
                        .foregroundStyle(issue.severity == .error ? .red : .orange)
                        .font(.callout)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }
}
