#if os(macOS)
import AppKit
import SwiftUI

enum AppUpdateLink {
    static let latestReleaseURL = URL(
        string: "https://github.com/orbeavers14/SwordReader/releases/latest"
    )!
}

struct SwordReaderCommands: Commands {
    @FocusedValue(\.swordReaderModel) private var model

    var body: some Commands {
        CommandGroup(after: .appInfo) {
            Button("Check for Updates…") {
                NSWorkspace.shared.open(AppUpdateLink.latestReleaseURL)
            }
        }

        CommandMenu("Navigate") {
            Button("Previous Chapter") { model?.moveChapter(by: -1) }
                .keyboardShortcut(.leftArrow, modifiers: [.command])
                .disabled(model == nil)
            Button("Next Chapter") { model?.moveChapter(by: 1) }
                .keyboardShortcut(.rightArrow, modifiers: [.command])
                .disabled(model == nil)
            Divider()
            ForEach(AppSection.primarySections) { section in
                Button(section.title) { model?.section = section }
                    .keyboardShortcut(section.keyboardKey, modifiers: [.command])
                    .disabled(model == nil)
            }
        }
    }
}

private extension AppSection {
    var keyboardKey: KeyEquivalent {
        switch self {
        case .read: "1"
        case .study: "2"
        case .plans: "3"
        case .search: "4"
        case .library: "5"
        case .settings: "5"
        }
    }
}

private struct SwordReaderModelFocusedValueKey: FocusedValueKey {
    typealias Value = AppModel
}

extension FocusedValues {
    var swordReaderModel: AppModel? {
        get { self[SwordReaderModelFocusedValueKey.self] }
        set { self[SwordReaderModelFocusedValueKey.self] = newValue }
    }
}
#endif
