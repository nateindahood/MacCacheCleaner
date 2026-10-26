import SwiftUI
import AppKit

@main
struct MacCacheCleanerApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
                .frame(minWidth: 860, minHeight: 620)
        }
        .defaultSize(width: 960, height: 700)
        .commands {
            CommandGroup(after: .appSettings) {
                Button("Permissions...") {
                    NotificationCenter.default.post(name: .showPermissionSetup, object: nil)
                }
            }
        }
    }
}

struct ContentView: View {
    @State private var showPermissionSetup = PermissionsManager.needsSetup

    var body: some View {
        TabView {
            DiskUsageView()
                .tabItem {
                    Label("Disk Usage", systemImage: "chart.bar.doc.horizontal")
                }
            CacheCleanerView()
                .tabItem {
                    Label("Cache Cleaner", systemImage: "trash")
                }
            LargeFileScannerView()
                .tabItem {
                    Label("Large Files", systemImage: "externaldrive.badge.questionmark")
                }
        }
        .padding()
        .sheet(isPresented: $showPermissionSetup) {
            PermissionSetupView(onDone: { showPermissionSetup = false })
        }
        .onReceive(NotificationCenter.default.publisher(for: .showPermissionSetup)) { _ in
            showPermissionSetup = true
        }
    }
}
