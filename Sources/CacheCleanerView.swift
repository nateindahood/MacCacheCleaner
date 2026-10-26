import SwiftUI
import Foundation

struct CacheLocation: Identifiable {
    let id = UUID()
    let name: String
    let path: String
    let icon: String
    let description: String
    var size: Int64 = -1
    var itemCount: Int = 0
    var isCalculating: Bool = false
    var exists: Bool = true
    var error: String? = nil
}

class CacheCleanerViewModel: ObservableObject {
    @Published var locations: [CacheLocation] = []
    @Published var isRefreshingAll = false

    init() {
        setupLocations()
    }

    func setupLocations() {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let fm = FileManager.default

        var locs: [CacheLocation] = [
            CacheLocation(name: "User Caches", path: "\(home)/Library/Caches",
                          icon: "folder.badge.gearshape",
                          description: "Application cache files"),
            CacheLocation(name: "System Temp", path: "/tmp",
                          icon: "hourglass",
                          description: "System temporary files"),
            CacheLocation(name: "User Logs", path: "\(home)/Library/Logs",
                          icon: "doc.text",
                          description: "Application and system log files"),
            CacheLocation(name: "Crash Reports", path: "\(home)/Library/Logs/DiagnosticReports",
                          icon: "exclamationmark.triangle",
                          description: "Crash reports and diagnostics"),
            CacheLocation(name: "Xcode Derived Data", path: "\(home)/Library/Developer/Xcode/DerivedData",
                          icon: "hammer",
                          description: "Xcode build intermediates"),
            CacheLocation(name: "Xcode Archives", path: "\(home)/Library/Developer/Xcode/Archives",
                          icon: "archivebox",
                          description: "Xcode project archives"),
            CacheLocation(name: "Homebrew Cache", path: "\(home)/Library/Caches/Homebrew",
                          icon: "cup.and.saucer",
                          description: "Homebrew package downloads"),
            CacheLocation(name: "Trash", path: "\(home)/.Trash",
                          icon: "trash",
                          description: "Files in Trash"),
            CacheLocation(name: "Downloads", path: "\(home)/Downloads",
                          icon: "arrow.down.circle",
                          description: "Downloaded files"),
            CacheLocation(name: "Safari Cache", path: "\(home)/Library/Caches/com.apple.Safari",
                          icon: "safari",
                          description: "Safari browser cache"),
            CacheLocation(name: "Cookies", path: "\(home)/Library/Cookies",
                          icon: "lock.shield",
                          description: "Browser and app cookies"),
            CacheLocation(name: "Saved Application State", path: "\(home)/Library/Saved Application State",
                          icon: "square.stack.3d.up",
                          description: "Saved window positions and state"),
        ]

        // Mark non-existent paths
        for i in locs.indices {
            locs[i].exists = fm.fileExists(atPath: locs[i].path)
        }

        locations = locs
    }

    func refreshAll() {
        isRefreshingAll = true
        for i in locations.indices where locations[i].exists {
            calculateSize(for: i)
        }
    }

    func calculateSize(for index: Int) {
        guard locations[index].exists else { return }
        locations[index].isCalculating = true
        locations[index].error = nil
        let path = locations[index].path

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let result = directorySize(at: path)
            DispatchQueue.main.async {
                guard let self = self, index < self.locations.count else { return }
                self.locations[index].size = result.size
                self.locations[index].itemCount = result.count
                self.locations[index].isCalculating = false

                // Check if all done
                if !self.locations.contains(where: { $0.isCalculating }) {
                    self.isRefreshingAll = false
                }
            }
        }
    }

    func clearLocation(at index: Int) {
        let path = locations[index].path
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            do {
                _ = try deleteContents(of: path)
                let result = directorySize(at: path)
                DispatchQueue.main.async {
                    guard let self = self, index < self.locations.count else { return }
                    self.locations[index].size = result.size
                    self.locations[index].itemCount = result.count
                    self.locations[index].error = nil
                }
            } catch {
                DispatchQueue.main.async {
                    guard let self = self, index < self.locations.count else { return }
                    self.locations[index].error = error.localizedDescription
                }
            }
        }
    }

    var totalSize: Int64 {
        locations.filter { $0.size > 0 }.reduce(0) { $0 + $1.size }
    }
}

// MARK: - Views

struct CacheCleanerView: View {
    @StateObject private var viewModel = CacheCleanerViewModel()
    @State private var confirmClearIndex: Int? = nil
    @State private var showConfirmClear = false

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Cache & Temporary Files")
                        .font(.title2)
                        .fontWeight(.semibold)
                    if viewModel.locations.contains(where: { $0.size >= 0 }) {
                        Text("Total: \(formatSize(viewModel.totalSize))")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                }
                Spacer()
                Button(action: { viewModel.refreshAll() }) {
                    Label("Calculate All Sizes", systemImage: "arrow.clockwise")
                }
                .disabled(viewModel.isRefreshingAll)
            }
            .padding(.bottom, 12)

            // Location List
            ScrollView {
                LazyVStack(spacing: 8) {
                    ForEach(Array(viewModel.locations.enumerated()), id: \.element.id) { index, location in
                        CacheLocationRow(
                            location: location,
                            onCalculate: { viewModel.calculateSize(for: index) },
                            onClear: {
                                confirmClearIndex = index
                                showConfirmClear = true
                            },
                            onOpenFinder: { revealInFinder(path: location.path) }
                        )
                    }
                }
            }
        }
        .padding()
        .alert("Clear Contents?", isPresented: $showConfirmClear) {
            Button("Cancel", role: .cancel) { }
            Button("Clear", role: .destructive) {
                if let index = confirmClearIndex {
                    viewModel.clearLocation(at: index)
                }
            }
        } message: {
            if let index = confirmClearIndex, index < viewModel.locations.count {
                Text("This will permanently delete all contents of \"\(viewModel.locations[index].name)\" at:\n\(viewModel.locations[index].path)\n\nThis action cannot be undone.")
            }
        }
    }
}

struct CacheLocationRow: View {
    let location: CacheLocation
    let onCalculate: () -> Void
    let onClear: () -> Void
    let onOpenFinder: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            // Icon
            Image(systemName: location.icon)
                .font(.title2)
                .foregroundColor(location.exists ? .accentColor : .secondary)
                .frame(width: 32)

            // Info
            VStack(alignment: .leading, spacing: 2) {
                Text(location.name)
                    .font(.headline)
                    .foregroundColor(location.exists ? .primary : .secondary)
                Text(location.path)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                if let error = location.error {
                    Text(error)
                        .font(.caption)
                        .foregroundColor(.red)
                        .lineLimit(2)
                }
                if !location.exists {
                    Text("Directory not found")
                        .font(.caption)
                        .foregroundColor(.orange)
                }
            }

            Spacer()

            // Size
            if location.isCalculating {
                ProgressView()
                    .controlSize(.small)
                    .frame(width: 80)
            } else if location.size >= 0 {
                VStack(alignment: .trailing, spacing: 2) {
                    Text(formatSize(location.size))
                        .font(.system(.body, design: .monospaced))
                        .fontWeight(.medium)
                        .foregroundColor(location.size > 1_000_000_000 ? .red :
                                            location.size > 100_000_000 ? .orange : .primary)
                    Text("\(location.itemCount) files")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .frame(width: 100, alignment: .trailing)
            } else {
                Text("--")
                    .foregroundColor(.secondary)
                    .frame(width: 100, alignment: .trailing)
            }

            // Actions
            HStack(spacing: 4) {
                Button(action: onCalculate) {
                    Image(systemName: "arrow.clockwise")
                        .frame(width: 28, height: 28)
                }
                .buttonStyle(.borderless)
                .disabled(!location.exists || location.isCalculating)
                .help("Calculate size")

                Button(action: onOpenFinder) {
                    Image(systemName: "folder")
                        .frame(width: 28, height: 28)
                }
                .buttonStyle(.borderless)
                .disabled(!location.exists)
                .help("Open in Finder")

                Button(action: onClear) {
                    Image(systemName: "xmark.circle")
                        .frame(width: 28, height: 28)
                        .foregroundColor(.red)
                }
                .buttonStyle(.borderless)
                .disabled(!location.exists || location.size <= 0)
                .help("Clear contents")
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color(nsColor: .controlBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color(nsColor: .separatorColor), lineWidth: 0.5)
        )
    }
}
