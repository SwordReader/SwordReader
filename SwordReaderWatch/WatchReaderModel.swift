import Foundation
import Observation
import SwordKit
import BibleKit
import BibleKitSword
import WatchConnectivity

struct WatchBible: Identifiable, Hashable, Sendable { let id: String; let title: String }
struct WatchBook: Identifiable, Hashable, Sendable { let id: String; let name: String; let chapterCount: Int }
struct WatchVerse: Identifiable, Hashable, Sendable { let id: String; let number: String; let text: String }
struct WatchCatalogBible: Identifiable, Hashable, Sendable { let id: String; let title: String; let language: String }

@MainActor @Observable
final class WatchReaderModel: NSObject, WCSessionDelegate {
    private(set) var modules: [WatchBible] = []
    private(set) var books: [WatchBook] = []
    private(set) var verses: [WatchVerse] = []
    private(set) var remoteModules: [WatchCatalogBible] = []
    private(set) var selectedModuleID: String?
    private(set) var selectedBookID: String?
    private(set) var selectedChapter = 1
    private(set) var isLoading = false
    private(set) var isInstalling = false
    private(set) var isLoadingChapter = false
    private(set) var installingModuleID: String?
    var presentedError: String?

    private let provider: SwordContentProvider
    private let repository: SwordModuleRepository
    private static let moduleKey = "watch.module"
    private static let bookKey = "watch.book"
    private static let chapterKey = "watch.chapter"
    private var chapterTask: Task<Void, Never>?
    private var chapterGeneration = UUID()
    private var activationGeneration = UUID()

    override init() {
        do {
            let location = try SwordModuleLocation.applicationSupport()
            let repository = try Self.crossWireRepository()
            provider = SwordContentProvider(library: try SwordLibrary(location: location),
                installer: SwordModuleInstaller(configuration: .init(location: location, repositories: [repository])))
            self.repository = repository
        } catch { fatalError("Unable to prepare SwordReader storage: \(error)") }
        super.init()
        if WCSession.isSupported() {
            WCSession.default.delegate = self
            WCSession.default.activate()
        }
    }

    var reference: String {
        guard let book = books.first(where: { $0.id == selectedBookID }) else { return "" }
        return "\(book.name) \(selectedChapter)"
    }
    var canMoveBackward: Bool {
        guard let id = selectedBookID, let index = books.firstIndex(where: { $0.id == id }) else { return false }
        return selectedChapter > 1 || index > books.startIndex
    }
    var canMoveForward: Bool {
        guard let book = books.first(where: { $0.id == selectedBookID }), let index = books.firstIndex(of: book) else { return false }
        return selectedChapter < book.chapterCount || index < books.index(before: books.endIndex)
    }

    func start() { Task { await refreshLibrary() } }
    func selectModule(_ id: String) {
        guard id != selectedModuleID else { return }
        Task { await activateModule(id, restoring: false) }
    }
    func selectBook(_ id: String) {
        guard books.contains(where: { $0.id == id }) else { return }
        selectedBookID = id; selectedChapter = 1; persistSelection(); loadChapter()
    }
    func selectChapter(_ chapter: Int) {
        guard let book = books.first(where: { $0.id == selectedBookID }), (1...book.chapterCount).contains(chapter) else { return }
        selectedChapter = chapter; persistSelection(); loadChapter()
    }
    func moveChapter(by offset: Int) {
        guard abs(offset) == 1, let book = books.first(where: { $0.id == selectedBookID }), let index = books.firstIndex(of: book) else { return }
        if offset < 0, selectedChapter > 1 { selectChapter(selectedChapter - 1) }
        else if offset < 0, index > books.startIndex {
            let previous = books[books.index(before: index)]; selectedBookID = previous.id; selectedChapter = previous.chapterCount; persistSelection(); loadChapter()
        } else if offset > 0, selectedChapter < book.chapterCount { selectChapter(selectedChapter + 1) }
        else if offset > 0, index < books.index(before: books.endIndex) {
            selectedBookID = books[books.index(after: index)].id; selectedChapter = 1; persistSelection(); loadChapter()
        }
    }

    func refreshRemoteCatalog() async {
        isLoading = true; defer { isLoading = false }
        do {
            let catalog = try await provider.remoteCatalog(from: repository, acknowledgingRemoteAccessRisks: true)
            remoteModules = catalog.filter { $0.kind == .bible }.map {
                WatchCatalogBible(id: $0.contentID.rawValue, title: $0.title.isEmpty ? $0.contentID.rawValue : $0.title, language: $0.languageCode)
            }.sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
        } catch { presentedError = error.localizedDescription }
    }
    func installRemote(_ module: WatchCatalogBible) async {
        guard !isInstalling else { return }
        isInstalling = true; installingModuleID = module.id
        defer { isInstalling = false; installingModuleID = nil }
        do {
            try await provider.install(contentID: BibleContentID(rawValue: module.id), from: repository,
                                       acknowledgingRemoteAccessRisks: true, progress: { _ in })
            await refreshLibrary(preferredModuleID: module.id)
        } catch { presentedError = error.localizedDescription }
    }

    nonisolated func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: (any Error)?) {}
    nonisolated func session(_ session: WCSession, didReceive file: WCSessionFile) {
        guard let moduleID = file.metadata?["moduleID"] as? String else { return }
        do {
            let received = FileManager.default.temporaryDirectory.appending(path: "\(UUID().uuidString).zip")
            try FileManager.default.copyItem(at: file.fileURL, to: received)
            Task { @MainActor in await self.installReceived(moduleID: moduleID, archive: received) }
        } catch {
            let message = error.localizedDescription
            Task { @MainActor in self.presentedError = message }
        }
    }

    private func installReceived(moduleID: String, archive: URL) async {
        defer { try? FileManager.default.removeItem(at: archive) }
        do {
            try await provider.install(contentID: BibleContentID(rawValue: moduleID), fromArchive: archive)
            await refreshLibrary(preferredModuleID: moduleID)
        }
        catch { presentedError = error.localizedDescription }
    }
    private func refreshLibrary(preferredModuleID: String? = nil) async {
        do {
            try await provider.refresh()
            modules = try await provider.catalog().filter { $0.kind == .bible }.map {
                WatchBible(id: $0.contentID.rawValue, title: $0.title.isEmpty ? $0.contentID.rawValue : $0.title)
            }
                .sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
            guard !modules.isEmpty else {
                activationGeneration = UUID(); chapterGeneration = UUID(); chapterTask?.cancel()
                selectedModuleID = nil; books = []; verses = []; isLoadingChapter = false; return
            }
            let requested = preferredModuleID ?? UserDefaults.standard.string(forKey: Self.moduleKey)
            let id = modules.first(where: { $0.id == requested })?.id ?? modules[0].id
            await activateModule(id, restoring: preferredModuleID == nil)
        } catch { presentedError = error.localizedDescription }
    }
    private func activateModule(_ id: String, restoring: Bool) async {
        let generation = UUID()
        activationGeneration = generation
        chapterGeneration = UUID(); chapterTask?.cancel()
        do {
            let loadedBooks = try await provider.books(contentID: BibleContentID(rawValue: id)).map {
                WatchBook(id: $0.id, name: $0.name, chapterCount: $0.chapterCount)
            }
            guard activationGeneration == generation else { return }
            books = loadedBooks
            selectedModuleID = id
            let saved = restoring ? UserDefaults.standard.string(forKey: Self.bookKey) : nil
            let book = books.first(where: { $0.id == saved }) ?? books.first(where: { $0.id == "John" }) ?? books.first
            selectedBookID = book?.id
            let savedChapter = restoring ? UserDefaults.standard.integer(forKey: Self.chapterKey) : 0
            selectedChapter = min(max(savedChapter, 1), book?.chapterCount ?? 1)
            persistSelection(); loadChapter()
        } catch {
            guard activationGeneration == generation else { return }
            isLoadingChapter = false
            presentedError = error.localizedDescription
        }
    }
    private func loadChapter() {
        chapterTask?.cancel()
        guard let moduleID = selectedModuleID,
              !reference.isEmpty
        else { return }

        let requestedReference = reference
        let generation = UUID()
        chapterGeneration = generation
        isLoadingChapter = true
        chapterTask = Task {
            do {
                let chapter = try await provider.chapter(contentID: BibleContentID(rawValue: moduleID), reference: requestedReference)
                let loaded = chapter.verses.map {
                    WatchVerse(
                        id: $0.reference,
                        number: $0.reference.split(separator: ":")
                            .last.map(String.init) ?? "",
                        text: $0.text
                    )
                }
                guard !Task.isCancelled,
                      chapterGeneration == generation
                else { return }
                verses = loaded
            } catch is CancellationError {
                // A newer chapter owns the visible state.
            } catch {
                guard chapterGeneration == generation else { return }
                presentedError = error.localizedDescription
            }
            guard chapterGeneration == generation else { return }
            isLoadingChapter = false
        }
    }
    private func persistSelection() {
        UserDefaults.standard.set(selectedModuleID, forKey: Self.moduleKey)
        UserDefaults.standard.set(selectedBookID, forKey: Self.bookKey)
        UserDefaults.standard.set(selectedChapter, forKey: Self.chapterKey)
    }
    private static func crossWireRepository() throws -> SwordModuleRepository {
        try .init(identifier: "crosswire", name: "CrossWire Bible Society", transport: .https, host: "www.crosswire.org", directory: "/ftpmirror/pub/sword/raw", packageDirectory: "/ftpmirror/pub/sword/packages/rawzip")
    }
}
