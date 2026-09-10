import SecretaryCore
import SwiftUI

@main
struct SecretaryApp: App {
    @StateObject private var store = LibraryStore()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(store)
                .tint(SecretaryTheme.accent)
                .onAppear {
                    store.bootstrap()
                    store.requestNotificationPermission()
                }
                #if os(macOS)
                .frame(
                    minWidth: SecretaryTheme.windowMinWidth,
                    minHeight: SecretaryTheme.windowMinHeight
                )
                #endif
        }
        #if os(macOS)
        .defaultSize(
            width: SecretaryTheme.windowDefaultWidth,
            height: SecretaryTheme.windowDefaultHeight
        )
        .commands {
            CommandGroup(replacing: .newItem) {}
            CommandGroup(after: .textEditing) {
                Button("Find in Document") {
                    NotificationCenter.default.post(name: .secretaryFindInDocument, object: nil)
                }
                .keyboardShortcut("f", modifiers: .command)
            }
            CommandMenu("Library") {
                Button("Scan Drop Folder") {
                    Task { await store.scanDropFolder() }
                }
                Button("Choose Library Folder…") {
                    store.chooseLibraryRoot()
                }
                Divider()
                Button("Rebuild Index") {
                    store.rebuildIndex()
                }
                .keyboardShortcut("r", modifiers: [.command, .shift])
            }
        }
        #endif

        #if os(macOS)
        Settings {
            SettingsView()
                .environmentObject(store)
                .tint(SecretaryTheme.accent)
        }
        #endif
    }
}
