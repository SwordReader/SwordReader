import Foundation
import SwiftUI
import BibleKit
import BibleUI
import UniformTypeIdentifiers

struct LibraryView: View {
    @Environment(AppModel.self) private var model
    @State private var isImporting = false
    @State private var isShowingContentFeeds = false
    @State private var modulePendingRemoval: BibleModule?
    @State private var keyedModulePendingRemoval: KeyedModule?
    @State private var isShowingRemoteAccessWarning = false
    @State private var isShowingModuleBrowser = false
    @State private var isShowingPrivacyAndLicenses = false
    @State private var isShowingFeedback = false

    var body: some View {
        List {
            Section("Installed Bibles") {
                if model.modules.isEmpty {
                    Text("No Bibles installed").foregroundStyle(.secondary)
                }
                ForEach(model.modules) { module in
                    Button {
                        model.selectModule(module.id)
                    } label: {
                        HStack {
                            moduleDescription(
                                title: module.title,
                                details: [module.id, module.language, module.version]
                            )
                            Spacer()
                            if module.id == model.selectedModuleID {
                                Image(systemName: "checkmark")
                                    .foregroundStyle(.tint)
                                    .accessibilityLabel("Selected")
                            }
                        }
                    }
                    .buttonStyle(.plain)
                    .contextMenu {
                        if let copyright = module.copyright {
                            Text(copyright)
                        }
                        #if os(iOS)
                        Button("Send to Apple Watch", systemImage: "applewatch") {
                            Task { await model.sendModuleToWatch(module.id) }
                        }
                        .disabled(model.sendingModuleID != nil)
                        #endif
                        Button("Remove Bible", systemImage: "trash", role: .destructive) {
                            modulePendingRemoval = module
                        }
                    }
                    #if !os(macOS)
                    .swipeActions {
                        Button("Remove", systemImage: "trash", role: .destructive) {
                            modulePendingRemoval = module
                        }
                    }
                    #endif
                    .disabled(model.removingModuleID != nil)
                }
            }

            Section("Books, Dictionaries & Devotionals") {
                if model.keyedModules.isEmpty {
                    Text("No books, dictionaries, or devotionals installed")
                        .foregroundStyle(.secondary)
                }
                ForEach(model.keyedModules) { module in
                    NavigationLink {
                        KeyedModuleReaderView(module: module)
                            .environment(model)
                    } label: {
                        moduleDescription(
                            title: module.title,
                            details: [module.category.title, module.language, module.version]
                        )
                    }
                    .contextMenu {
                        if let copyright = module.copyright { Text(copyright) }
                        Button("Remove", systemImage: "trash", role: .destructive) {
                            keyedModulePendingRemoval = module
                        }
                    }
                }
            }

            if let catalog = model.catalog {
                Section("Available in \(catalog.directory.lastPathComponent)") {
                    ForEach(catalog.modules.filter { $0.compatibility == .compatible }) { module in
                        HStack {
                            moduleDescription(
                                title: module.title,
                                details: [module.id, module.language, module.version]
                            )
                            Spacer()
                            if model.modules.contains(where: { $0.id == module.id })
                                || model.keyedModules.contains(where: { $0.id == module.id }) {
                                Text("Installed")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            } else {
                                Button("Install") { Task { await model.install(module) } }
                                    .disabled(model.isInstalling)
                            }
                        }
                        if let copyright = module.copyright {
                            Text(copyright)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
        .navigationTitle("Library")
        .toolbar {
            ToolbarItem(placement: .secondaryAction) {
                Button("Open Content Feed…", systemImage: "network") { isShowingContentFeeds = true }
            }
            ToolbarItem(placement: .primaryAction) {
                Button("Get Modules", systemImage: "arrow.down.circle") {
                    isShowingRemoteAccessWarning = true
                }
                .help("Get Modules")
            }
            ToolbarItem(placement: .secondaryAction) {
                Button("Import Local Catalog", systemImage: "folder.badge.plus") {
                    isImporting = true
                }
                .help("Import Local Catalog")
            }
            ToolbarItem(placement: .secondaryAction) {
                Button("Feedback", systemImage: "bubble.left.and.exclamationmark.bubble.right") {
                    isShowingFeedback = true
                }
                .help("Send Feedback")
            }
            ToolbarItem(placement: .secondaryAction) {
                Button("Privacy & Licenses", systemImage: "info.circle") {
                    isShowingPrivacyAndLicenses = true
                }
                .help("Privacy & Licenses")
            }
        }
        .confirmationDialog(
            "Connect to CrossWire?",
            isPresented: $isShowingRemoteAccessWarning,
            titleVisibility: .visible
        ) {
            Button("Continue") {
                isShowingModuleBrowser = true
                Task { await model.refreshRemoteCatalog() }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("SwordReader will contact the CrossWire Bible Society to retrieve its module catalog. This network request may reveal that you use a Bible reader. Modules are supplied by their publishers and have separate licenses.")
        }
        .sheet(isPresented: $isShowingModuleBrowser) {
            RemoteModuleBrowser().environment(model)
        }
        .sheet(isPresented: $isShowingContentFeeds) {
            ContentFeedBrowser().environment(model)
        }
        .sheet(isPresented: $isShowingPrivacyAndLicenses) {
            PrivacyAndLicensesView().environment(model)
        }
        .sheet(isPresented: $isShowingFeedback) {
            FeedbackView().environment(model)
        }
        .fileImporter(isPresented: $isImporting, allowedContentTypes: [.folder]) { result in
            if case .success(let url) = result {
                Task { await model.inspectCatalog(at: url) }
            } else if case .failure(let error) = result {
                model.presentedError = PresentedError(error)
            }
        }
        .confirmationDialog(
            "Remove \(modulePendingRemoval?.title ?? "Bible")?",
            isPresented: Binding(
                get: { modulePendingRemoval != nil },
                set: { if !$0 { modulePendingRemoval = nil } }
            ),
            titleVisibility: .visible,
            presenting: modulePendingRemoval
        ) { module in
            Button("Remove Bible", role: .destructive) {
                modulePendingRemoval = nil
                Task { await model.removeModule(id: module.id) }
            }
            Button("Cancel", role: .cancel) { modulePendingRemoval = nil }
        } message: { module in
            Text("\(module.title) will be removed from this device. You can install it again from its source catalog.")
        }
        .confirmationDialog(
            "Remove \(keyedModulePendingRemoval?.title ?? "module")?",
            isPresented: Binding(
                get: { keyedModulePendingRemoval != nil },
                set: { if !$0 { keyedModulePendingRemoval = nil } }
            ),
            titleVisibility: .visible,
            presenting: keyedModulePendingRemoval
        ) { module in
            Button("Remove", role: .destructive) {
                keyedModulePendingRemoval = nil
                Task { await model.removeKeyedModule(id: module.id) }
            }
            Button("Cancel", role: .cancel) { keyedModulePendingRemoval = nil }
        } message: { module in
            Text("\(module.title) will be removed from this device.")
        }
        .overlay {
            if model.isInstalling {
                ProgressView("Installing…")
                    .padding()
                    .background(.regularMaterial, in: .rect(cornerRadius: 12))
            } else if let moduleID = model.sendingModuleID {
                ProgressView("Sending \(moduleID) to Apple Watch…")
                    .padding()
                    .background(.regularMaterial, in: .rect(cornerRadius: 12))
            } else if model.removingModuleID != nil {
                ProgressView("Removing…")
                    .padding()
                    .background(.regularMaterial, in: .rect(cornerRadius: 12))
            }
        }
    }

    private func moduleDescription(
        title: String,
        details: [String?]
    ) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
            Text(details.compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · "))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

private struct KeyedModuleReaderView: View {
    @Environment(AppModel.self) private var model
    let module: KeyedModule
    @State private var keys: [String] = []
    @State private var isLoading = true

    var body: some View {
        Group {
            if isLoading {
                ProgressView("Opening \(module.category.title)…")
            } else if keys.isEmpty {
                ContentUnavailableView(
                    "No Readable Entries",
                    systemImage: "text.book.closed",
                    description: Text("This module did not provide any navigable entries.")
                )
            } else {
                List(keys, id: \.self) { key in
                    NavigationLink {
                        KeyedEntryView(module: module, keys: keys, initialKey: key)
                            .environment(model)
                    } label: {
                        Text(Self.displayTitle(for: key))
                    }
                }
            }
        }
        .navigationTitle(module.title)
        .task {
            do {
                keys = try await model.keyedEntryKeys(moduleID: module.id)
            } catch {
                model.presentedError = PresentedError(error)
            }
            isLoading = false
        }
    }

    private static func displayTitle(for key: String) -> String {
        key.split(separator: "/").last.map(String.init) ?? key
    }
}

private struct KeyedEntryView: View {
    @Environment(AppModel.self) private var model
    let module: KeyedModule
    let keys: [String]
    @State private var readerTabs: KeyedReaderTabs
    @State private var keysByModule: [String: [String]]
    @State private var entry: KeyedModuleEntry?
    @State private var splitTabIDs: Set<KeyedReaderTab.ID> = []

    init(module: KeyedModule, keys: [String], initialKey: String) {
        self.module = module
        self.keys = keys
        _readerTabs = State(initialValue: KeyedReaderTabs(
            initialModuleID: module.id,
            initialKey: initialKey
        ))
        _keysByModule = State(initialValue: [module.id: keys])
    }

    private var selectedTab: KeyedReaderTab {
        readerTabs.tabs.first { $0.id == readerTabs.selectedTabID }
            ?? readerTabs.tabs[0]
    }

    private var selectedKeys: [String] {
        keysByModule[selectedTab.moduleID, default: []]
    }

    private var previousKey: String? {
        KeyedEntryNavigation.adjacentKey(
            to: selectedTab.key,
            offset: -1,
            in: selectedKeys
        )
    }

    private var nextKey: String? {
        KeyedEntryNavigation.adjacentKey(
            to: selectedTab.key,
            offset: 1,
            in: selectedKeys
        )
    }

    private var splitPair: KeyedReaderTabPair? {
        let tabs = readerTabs.tabs.filter { splitTabIDs.contains($0.id) }
        guard tabs.count == 2 else { return nil }
        return KeyedReaderTabPair(leading: tabs[0], trailing: tabs[1])
    }

    var body: some View {
        Group {
            if let splitPair {
                GeometryReader { proxy in
                    if proxy.size.width >= 700 {
                        HStack(spacing: 0) {
                            keyedPane(splitPair.leading)
                            Divider()
                            keyedPane(splitPair.trailing)
                        }
                    } else {
                        VStack(spacing: 0) {
                            keyedPane(splitPair.leading)
                            Divider()
                            keyedPane(splitPair.trailing)
                        }
                    }
                }
            } else {
                ScrollView {
                    if let entry {
                        BibleReaderText(content: KeyedEntryFormatter.attributedString(for: entry))
                            .font(.system(size: model.readerFontSize, design: model.readerFont.design))
                    } else {
                        ProgressView()
                            .frame(maxWidth: .infinity)
                            .padding()
                    }
                }
            }
        }
        .safeAreaInset(edge: .top, spacing: 0) {
            keyedReaderTabBar
        }
        .navigationTitle(Self.displayTitle(for: selectedTab.key))
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Button("Previous Entry", systemImage: "chevron.left") {
                    if let previousKey { readerTabs.selectKey(previousKey) }
                }
                .labelStyle(.iconOnly)
                .disabled(previousKey == nil)
                .help("Previous Entry")

                Button("Next Entry", systemImage: "chevron.right") {
                    if let nextKey { readerTabs.selectKey(nextKey) }
                }
                .labelStyle(.iconOnly)
                .disabled(nextKey == nil)
                .help("Next Entry")
            }
        }
        .task(id: selectedTab) {
            guard splitPair == nil else { return }
            entry = nil
            do {
                let availableKeys = try await keys(for: selectedTab.moduleID)
                guard let fallback = availableKeys.first else { return }
                if !availableKeys.contains(selectedTab.key) {
                    readerTabs.selectModule(
                        selectedTab.moduleID,
                        key: fallback,
                        in: selectedTab.id
                    )
                    return
                }
                entry = try await model.keyedEntry(
                    moduleID: selectedTab.moduleID,
                    key: selectedTab.key
                )
            } catch {
                model.presentedError = PresentedError(error)
            }
        }
    }

    private var keyedReaderTabBar: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 6) {
                ForEach(readerTabs.tabs) { tab in
                    HStack(spacing: 4) {
                        Button(Self.displayTitle(for: tab.key)) {
                            readerTabs.selectTab(tab.id)
                        }
                        .lineLimit(1)

                        Button("Close Tab", systemImage: "xmark") {
                            splitTabIDs.remove(tab.id)
                            readerTabs.closeTab(tab.id)
                        }
                        .labelStyle(.iconOnly)
                        .disabled(readerTabs.tabs.count == 1)
                        .help("Close Tab")
                    }
                    .buttonStyle(.plain)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 7)
                    .background(
                        tab.id == readerTabs.selectedTabID
                            ? Color.accentColor.opacity(0.16)
                            : Color.secondary.opacity(0.08),
                        in: .rect(cornerRadius: 8)
                    )
                    .draggable(tab.id.uuidString)
                    .dropDestination(for: String.self) { identifiers, _ in
                        guard let draggedID = identifiers.compactMap({
                            UUID(uuidString: $0)
                        }).first else { return false }
                        readerTabs.moveTab(draggedID, to: tab.id)
                        return true
                    }
                    .contextMenu {
                        Menu("Module", systemImage: "books.vertical") {
                            ForEach(model.keyedModules) { availableModule in
                                Button {
                                    Task {
                                        await select(
                                            module: availableModule,
                                            for: tab
                                        )
                                    }
                                } label: {
                                    if tab.moduleID == availableModule.id {
                                        Label(availableModule.title, systemImage: "checkmark")
                                    } else {
                                        Text(availableModule.title)
                                    }
                                }
                            }
                        }
                        if let neighbor = neighbor(of: tab.id) {
                            Button(
                                "Show Side by Side with \(tabTitle(neighbor))",
                                systemImage: "rectangle.split.2x1"
                            ) {
                                splitTabIDs = [tab.id, neighbor.id]
                            }
                        }
                    }
                }

                Button("New Tab", systemImage: "plus") {
                    readerTabs.createTab()
                }
                .labelStyle(.iconOnly)
                .buttonStyle(.borderless)
                .help("New Reading Tab")

                if splitPair != nil {
                    Button("Split Back into Tabs", systemImage: "rectangle.split.1x2") {
                        splitTabIDs = []
                    }
                    .labelStyle(.iconOnly)
                    .buttonStyle(.borderless)
                    .help("Split Back into Tabs")
                } else if let neighbor = neighbor(of: readerTabs.selectedTabID) {
                    Button(
                        "Show Side by Side with \(tabTitle(neighbor))",
                        systemImage: "rectangle.split.2x1"
                    ) {
                        splitTabIDs = [readerTabs.selectedTabID, neighbor.id]
                    }
                    .labelStyle(.iconOnly)
                    .buttonStyle(.borderless)
                    .help("Show Side by Side with \(tabTitle(neighbor))")
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
        }
        .background(.bar)
        .accessibilityLabel("Reading Tabs")
    }

    private static func displayTitle(for key: String) -> String {
        key.split(separator: "/").last.map(String.init) ?? key
    }

    private func tabTitle(_ tab: KeyedReaderTab) -> String {
        let title = model.keyedModules.first { $0.id == tab.moduleID }?.title
            ?? tab.moduleID
        return "\(title) · \(Self.displayTitle(for: tab.key))"
    }

    private func neighbor(of tabID: KeyedReaderTab.ID) -> KeyedReaderTab? {
        guard readerTabs.tabs.count > 1,
              let index = readerTabs.tabs.firstIndex(where: { $0.id == tabID })
        else { return nil }
        let neighborIndex = index < readerTabs.tabs.count - 1 ? index + 1 : index - 1
        return readerTabs.tabs[neighborIndex]
    }

    private func keys(for moduleID: String) async throws -> [String] {
        if let cached = keysByModule[moduleID] { return cached }
        let loaded = try await model.keyedEntryKeys(moduleID: moduleID)
        keysByModule[moduleID] = loaded
        return loaded
    }

    private func select(module: KeyedModule, for tab: KeyedReaderTab) async {
        do {
            let availableKeys = try await keys(for: module.id)
            guard let fallback = availableKeys.first else { return }
            readerTabs.selectModule(
                module.id,
                key: availableKeys.contains(tab.key) ? tab.key : fallback,
                in: tab.id
            )
        } catch {
            model.presentedError = PresentedError(error)
        }
    }

    private func keyedPane(_ tab: KeyedReaderTab) -> some View {
        KeyedTabPane(tab: tab)
            .environment(model)
    }
}

private struct KeyedTabPane: View {
    @Environment(AppModel.self) private var model
    let tab: KeyedReaderTab
    @State private var entry: KeyedModuleEntry?

    var body: some View {
        VStack(spacing: 0) {
            Text(title)
                .font(.headline)
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding()
                .background(.bar)
            ScrollView {
                if let entry {
                    Text(KeyedEntryFormatter.attributedString(for: entry))
                        .font(.system(size: model.readerFontSize, design: model.readerFont.design))
                        .textSelection(.enabled)
                        .frame(maxWidth: 720, alignment: .leading)
                        .padding()
                } else {
                    ProgressView().padding()
                }
            }
        }
        .task(id: tab) {
            do {
                entry = try await model.keyedEntry(moduleID: tab.moduleID, key: tab.key)
            } catch {
                model.presentedError = PresentedError(error)
            }
        }
    }

    private var title: String {
        let moduleTitle = model.keyedModules.first { $0.id == tab.moduleID }?.title
            ?? tab.moduleID
        let entryTitle = tab.key.split(separator: "/").last.map(String.init) ?? tab.key
        return "\(moduleTitle) · \(entryTitle)"
    }
}

typealias KeyedEntryNavigation = BibleEntryNavigation

@MainActor
enum KeyedEntryFormatter {
    static func attributedString(for entry: KeyedModuleEntry) -> AttributedString {
        BibleRichTextFormatter.attributedString(text: entry.text, html: entry.html)
    }
}
