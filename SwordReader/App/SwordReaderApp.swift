import SwiftUI

@main
struct SwordReaderApp: App {
    var body: some Scene {
        WindowGroup {
            SwordReaderSceneView()
        }
        #if os(macOS)
        .defaultSize(width: 1_100, height: 760)
        .commands { SwordReaderCommands() }
        #endif

        WindowGroup("Passage", for: ReaderDestination.self) { destination in
            SwordReaderSceneView(initialDestination: destination.wrappedValue)
        }
        #if os(macOS)
        .defaultSize(width: 1_100, height: 760)
        #endif

        #if os(macOS)
        Settings {
            PreferencesSceneView()
        }
        #endif
    }
}

#if os(macOS)
private struct PreferencesSceneView: View {
    @State private var model = AppModel()

    var body: some View {
        NavigationStack {
            PreferencesView()
                .environment(model)
        }
        .frame(width: 560, height: 520)
        .task { await model.start() }
    }
}
#endif

private struct SwordReaderSceneView: View {
    @State private var model = AppModel()
    @SceneStorage("reader.sceneDestination") private var storedDestination = ""
    @SceneStorage("reader.sceneTabs") private var storedTabSession = ""
    let initialDestination: ReaderDestination?

    init(initialDestination: ReaderDestination? = nil) {
        self.initialDestination = initialDestination
    }

    var body: some View {
        RootView()
            .environment(model)
            .preferredColorScheme(model.appAppearance.colorScheme)
            #if os(macOS)
            .focusedSceneValue(\.swordReaderModel, model)
            #endif
            .task {
                #if canImport(MetricKit)
                MetricKitCrashMonitor.shared.start()
                #endif
                let sessionToRestore = ReaderTabSession(
                    encoded: storedTabSession
                )
                await model.start()
                if let initialDestination {
                    await model.open(destination: initialDestination)
                } else if let sessionToRestore {
                    await model.restoreReaderTabs(sessionToRestore)
                } else if let url = URL(string: storedDestination),
                          let restored = ReaderDestination(url: url) {
                    await model.open(destination: restored)
                }
            }
            .onOpenURL { url in
                Task { await model.open(url: url) }
            }
            .onContinueUserActivity(ReaderContinuityActivity.activityType) { activity in
                guard let destination = ReaderContinuityActivity.destination(from: activity) else {
                    return
                }
                Task { await model.continueReading(from: destination) }
            }
            .userActivity(
                ReaderContinuityActivity.activityType,
                element: model.currentDestination
            ) { destination, activity in
                ReaderContinuityActivity.update(activity, with: destination)
            }
            .onChange(of: model.currentDestination) { _, destination in
                storedDestination = destination?.url?.absoluteString ?? ""
            }
            .onChange(of: model.readerTabSession) { _, session in
                storedTabSession = session?.encoded ?? ""
            }
            .onReceive(NotificationCenter.default.publisher(
                for: UserDefaults.didChangeNotification
            )) { _ in
                model.reloadReaderPreferences()
            }
            .onReceive(NotificationCenter.default.publisher(
                for: .readerPreferencesDidChange
            )) { _ in
                model.reloadReaderPreferences()
            }
            .onReceive(NotificationCenter.default.publisher(
                for: CrashDiagnosticStore.didSaveNotification
            )) { _ in
                model.reloadPendingCrashDiagnostic()
            }
    }
}

private extension AppAppearance {
    var colorScheme: ColorScheme? {
        switch self {
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
    }
}
