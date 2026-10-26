import SwiftUI
import AppKit
import Security

extension Notification.Name {
    static let showPermissionSetup = Notification.Name("showPermissionSetup")
}

enum PermissionStatus {
    case unknown, granted, denied
}

struct PermissionItem: Identifiable {
    let id: String
    let title: String
    let detail: String
    let icon: String
    let probePath: String
    var status: PermissionStatus = .unknown
}

class PermissionsManager: ObservableObject {
    @Published var items: [PermissionItem] = []
    @Published var hasFullDiskAccess = false
    @Published var isRequesting = false

    private static let setupKey = "permissionSetupCompletedForBuild"

    init() {
        items = Self.makeItems()
        refreshFullDiskAccess()
    }

    // macOS ties privacy grants to the app's code signature, and each rebuild of this
    // ad-hoc signed app gets a new one, so setup reruns whenever the signature changes
    private static let currentBuildID: String = {
        var staticCode: SecStaticCode?
        guard SecStaticCodeCreateWithPath(Bundle.main.bundleURL as CFURL, [], &staticCode) == errSecSuccess,
              let code = staticCode else { return "unknown" }
        var info: CFDictionary?
        guard SecCodeCopySigningInformation(code, [], &info) == errSecSuccess,
              let dict = info as? [String: Any],
              let unique = dict[kSecCodeInfoUnique as String] as? Data else { return "unknown" }
        return unique.map { String(format: "%02x", $0) }.joined()
    }()

    static var needsSetup: Bool {
        UserDefaults.standard.string(forKey: setupKey) != currentBuildID
    }

    static func markSetupComplete() {
        UserDefaults.standard.set(currentBuildID, forKey: setupKey)
    }

    private static func makeItems() -> [PermissionItem] {
        let fm = FileManager.default
        let home = fm.homeDirectoryForCurrentUser.path
        var items = [
            PermissionItem(id: "desktop", title: "Desktop", detail: "Files on your Desktop",
                           icon: "menubar.dock.rectangle", probePath: "\(home)/Desktop"),
            PermissionItem(id: "documents", title: "Documents", detail: "Your Documents folder",
                           icon: "doc.text", probePath: "\(home)/Documents"),
            PermissionItem(id: "downloads", title: "Downloads", detail: "Your Downloads folder",
                           icon: "arrow.down.circle", probePath: "\(home)/Downloads"),
        ]

        let iCloudPath = "\(home)/Library/Mobile Documents/com~apple~CloudDocs"
        if fm.fileExists(atPath: iCloudPath) {
            items.append(PermissionItem(id: "icloud", title: "iCloud Drive",
                                        detail: "Only scanned when \"Include iCloud Drive\" is checked",
                                        icon: "icloud", probePath: iCloudPath))
        }

        return items
    }

    func refreshFullDiskAccess() {
        // The TCC database is only readable with Full Disk Access, and reading it never prompts
        let tccPath = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/com.apple.TCC/TCC.db").path
        if let handle = FileHandle(forReadingAtPath: tccPath) {
            handle.closeFile()
            hasFullDiskAccess = true
            for index in items.indices { items[index].status = .granted }
        } else {
            hasFullDiskAccess = false
        }
    }

    // Probes each location one at a time; each probe blocks until the user answers its prompt
    func requestAll() {
        guard !isRequesting else { return }
        isRequesting = true
        let pending = items.filter { $0.status != .granted }

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            for item in pending {
                let granted = (try? FileManager.default.contentsOfDirectory(atPath: item.probePath)) != nil
                DispatchQueue.main.async {
                    if let index = self?.items.firstIndex(where: { $0.id == item.id }) {
                        self?.items[index].status = granted ? .granted : .denied
                    }
                }
            }
            DispatchQueue.main.async {
                self?.isRequesting = false
            }
        }
    }

    var allRequested: Bool {
        items.allSatisfy { $0.status != .unknown }
    }

    func openFullDiskAccessSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles") {
            NSWorkspace.shared.open(url)
        }
    }

    func openFilesAndFoldersSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_FilesAndFolders") {
            NSWorkspace.shared.open(url)
        }
    }
}

// MARK: - Views

struct PermissionSetupView: View {
    @StateObject private var manager = PermissionsManager()
    @State private var step = 0
    @State private var showSkipWarning = false
    let onDone: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            switch step {
            case 0: introStep
            case 1: fullDiskAccessStep
            default: foldersStep
            }
        }
        .padding(24)
        .frame(width: 560)
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            manager.refreshFullDiskAccess()
        }
        .alert("Skip Folder Access?", isPresented: $showSkipWarning) {
            Button("Go Back", role: .cancel) { }
            Button("Skip") { finish() }
        } message: {
            Text("macOS will ask about these folders during your scans instead, so a scan may stop and wait for you to answer.\n\nIf you deny access to a folder, Cache Cleaner won't be able to see that folder or anything in it, and it will be left out of your results.")
        }
    }

    private var introStep: some View {
        Group {
            stepHeader(icon: "lock.shield", title: "Set Up Permissions")
            Text("To show where all of your storage is going, Cache Cleaner needs to read folders that macOS protects, like Desktop, Documents, Downloads, iCloud Drive and other apps' data.")
            Text("Granting access now means scans won't stop to ask for permission halfway through, so you can start a scan and walk away.")
            Text("Nothing is uploaded, and nothing is deleted unless you choose to delete it.")
                .foregroundColor(.secondary)
            HStack {
                Button("Skip for Now") { finish() }
                Spacer()
                Button("Continue") { step = 1 }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
            }
            .padding(.top, 8)
        }
    }

    private var fullDiskAccessStep: some View {
        Group {
            stepHeader(icon: "externaldrive", title: "Full Disk Access (Recommended)")
            Text("Full Disk Access covers every location at once, including other apps' data and Mail, Messages and Safari data, which can't be granted any other way. macOS only lets you turn it on in System Settings.")
            VStack(alignment: .leading, spacing: 6) {
                Text("1. Click **Open System Settings**.")
                Text("2. Turn on **MacCacheCleaner**. If it's not listed, click **+** and choose the app. **Show App in Finder** shows you where it is.")
                Text("3. If macOS asks, choose **Quit & Reopen**, then come back to this window.")
            }
            .font(.callout)

            HStack(spacing: 8) {
                Button("Open System Settings") { manager.openFullDiskAccessSettings() }
                Button("Show App in Finder") {
                    NSWorkspace.shared.activateFileViewerSelecting([Bundle.main.bundleURL])
                }
                Spacer()
                statusLabel(manager.hasFullDiskAccess ? .granted : .unknown,
                            pendingText: "Not enabled")
            }

            HStack {
                Button("Back") { step = 0 }
                Spacer()
                Button(manager.hasFullDiskAccess ? "Continue" : "Skip") { step = 2 }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
            }
            .padding(.top, 8)
        }
    }

    private var foldersStep: some View {
        Group {
            stepHeader(icon: "folder.badge.questionmark", title: "Folder Access")
            if manager.hasFullDiskAccess {
                Text("Full Disk Access is on, so every location below is already covered.")
            } else {
                Text("These are the folders macOS most often asks about. Click **Request Access** and allow each one now so these pop-ups don't interrupt your scans later.")
            }

            VStack(spacing: 6) {
                ForEach(manager.items) { item in
                    HStack(spacing: 10) {
                        Image(systemName: item.icon)
                            .foregroundColor(.accentColor)
                            .frame(width: 22)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(item.title)
                            Text(item.detail)
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        Spacer()
                        statusLabel(item.status, pendingText: "Not requested")
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(
                        RoundedRectangle(cornerRadius: 6)
                            .fill(Color(nsColor: .controlBackgroundColor))
                    )
                }
            }

            if !manager.hasFullDiskAccess {
                Text("Scans may still ask about other folders not listed here, such as external drives or other apps' data. macOS remembers each answer, so you'll only be asked once per folder. Full Disk Access avoids these pop-ups entirely.")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if manager.items.contains(where: { $0.status == .denied }) {
                HStack(spacing: 4) {
                    Text("Denied by mistake? Turn it on in System Settings.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Button("Open Files & Folders") { manager.openFilesAndFoldersSettings() }
                        .buttonStyle(.link)
                        .font(.caption)
                }
            }

            HStack {
                Button("Back") { step = 1 }
                    .disabled(manager.isRequesting)
                if !manager.allRequested {
                    Button("Skip") { showSkipWarning = true }
                        .disabled(manager.isRequesting)
                }
                Spacer()
                if manager.isRequesting {
                    ProgressView().controlSize(.small)
                }
                if manager.allRequested {
                    Button("Done") { finish() }
                        .buttonStyle(.borderedProminent)
                        .keyboardShortcut(.defaultAction)
                } else {
                    Button("Request Access") { manager.requestAll() }
                        .buttonStyle(.borderedProminent)
                        .keyboardShortcut(.defaultAction)
                        .disabled(manager.isRequesting)
                }
            }
            .padding(.top, 8)
        }
    }

    private func stepHeader(icon: String, title: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.title)
                .foregroundColor(.accentColor)
            Text(title)
                .font(.title2)
                .fontWeight(.semibold)
        }
    }

    @ViewBuilder
    private func statusLabel(_ status: PermissionStatus, pendingText: String) -> some View {
        switch status {
        case .granted:
            Label("Allowed", systemImage: "checkmark.circle.fill")
                .foregroundColor(.green)
        case .denied:
            Label("Denied", systemImage: "xmark.circle.fill")
                .foregroundColor(.red)
        case .unknown:
            Text(pendingText)
                .foregroundColor(.secondary)
        }
    }

    private func finish() {
        PermissionsManager.markSetupComplete()
        onDone()
    }
}
