import BibleKit
import BibleKitSword
import Foundation
import SwordKit

protocol ScriptureServing: Sendable {
    func installedBibles() async throws -> [BibleModule]
    func installedKeyedModules() async throws -> [KeyedModule]
    func keyedEntryKeys(moduleID: String) async throws -> [String]
    func keyedEntry(moduleID: String, key: String) async throws -> KeyedModuleEntry
    func books(moduleID: String) async throws -> [BibleBook]
    func chapter(_ reference: String, moduleID: String) async throws -> BibleChapter
    func parallelChapter(_ reference: String, moduleIDs: [String]) async throws -> [ParallelVerse]
    func search(_ query: String, moduleID: String, mode: ScriptureSearchMode, scope: ScriptureSearchScope,
                progress: @escaping @Sendable (Int) -> Void) async throws -> [BibleSearchResult]
    func catalog(at directory: URL) async throws -> LocalCatalog
    func install(moduleID: String, from catalog: LocalCatalog) async throws
    func remoteBibles(from source: ModuleSource) async throws -> [CatalogModule]
    func installRemote(moduleID: String, from source: ModuleSource,
                       progress: @escaping @Sendable (ModuleTransferProgress) -> Void) async throws
    func remove(moduleID: String) async throws
}

/// Maps framework content to the app's existing persistence and navigation models.
actor SwordScriptureService: ScriptureServing {
    private let provider: SwordContentProvider

    init() throws {
        let location = try SwordModuleLocation.applicationSupport()
        let repository = try Self.repository(for: .crossWire)
        provider = SwordContentProvider(library: try SwordLibrary(location: location),
            installer: SwordModuleInstaller(configuration: SwordInstallerConfiguration(location: location, repositories: [repository])))
    }

    func installedBibles() async throws -> [BibleModule] {
        try await provider.catalog().filter { $0.kind == .bible }.map {
            BibleModule(id: $0.contentID.rawValue, title: Self.title($0), language: $0.languageCode,
                        version: $0.version, copyright: $0.license.attribution)
        }.sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
    }

    func installedKeyedModules() async throws -> [KeyedModule] {
        try await provider.catalog().filter { [.dictionary, .generalBook, .devotional].contains($0.kind) }.map {
            KeyedModule(id: $0.contentID.rawValue, title: Self.title($0), language: $0.languageCode,
                        version: $0.version, copyright: $0.license.attribution, category: Self.category($0.kind))
        }.sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
    }

    func keyedEntryKeys(moduleID: String) async throws -> [String] {
        try await provider.entryKeys(contentID: BibleContentID(rawValue: moduleID))
    }

    func keyedEntry(moduleID: String, key: String) async throws -> KeyedModuleEntry {
        let entry = try await provider.read(contentID: BibleContentID(rawValue: moduleID), at: .keyedEntry(key))
        guard case .keyedEntry(let resolved) = entry.location else { throw BibleReadingError.unsupportedLocation(entry.location) }
        return KeyedModuleEntry(key: resolved, text: entry.text, html: entry.html)
    }

    func books(moduleID: String) async throws -> [BibleBook] {
        try await provider.books(contentID: BibleContentID(rawValue: moduleID)).map {
            BibleBook(id: $0.id, name: $0.name, abbreviation: $0.abbreviation,
                      chapterCount: $0.chapterCount, testament: $0.testament == .old ? .old : .new)
        }
    }

    func chapter(_ reference: String, moduleID: String) async throws -> BibleChapter {
        let chapter = try await provider.chapter(contentID: BibleContentID(rawValue: moduleID), reference: reference)
        return BibleChapter(reference: chapter.reference, moduleID: chapter.contentID.rawValue,
            verses: chapter.verses.map { verse in
                BibleVerse(reference: verse.reference, number: verse.reference.split(separator: ":").last.map(String.init) ?? verse.reference,
                    text: verse.text, content: verse.content,
                    headings: verse.annotations.filter { $0.kind == .heading }.map { BibleHeading(identifier: $0.id, text: $0.text) },
                    footnotes: verse.annotations.filter { $0.kind == .footnote }.map { BibleFootnote(id: $0.id, text: $0.text, type: $0.type) },
                    crossReferences: verse.annotations.filter { $0.kind == .crossReference }.map { BibleCrossReference(id: $0.id, references: $0.references) })
            })
    }

    func parallelChapter(_ reference: String, moduleIDs: [String]) async throws -> [ParallelVerse] {
        try await provider.parallelChapter(reference: reference, contentIDs: moduleIDs.map { BibleContentID(rawValue: $0) }).map { row in
            ParallelVerse(reference: row.reference,
                texts: row.texts.map { ParallelVerseText(moduleID: $0.contentID.rawValue, text: $0.text) },
                lexicalLinks: row.wordLinks.map { OriginalLanguageLink(strongsNumber: $0.strongsNumber, words: $0.words) })
        }
    }

    func search(_ query: String, moduleID: String, mode: ScriptureSearchMode, scope: ScriptureSearchScope,
                progress: @escaping @Sendable (Int) -> Void) async throws -> [BibleSearchResult] {
        let referenceScope: String?
        switch scope {
        case .wholeBible: referenceScope = nil
        case .oldTestament: referenceScope = "Gen-Mal"
        case .newTestament: referenceScope = "Matt-Rev"
        }
        return try await provider.search(contentID: BibleContentID(rawValue: moduleID), query: query,
            mode: BibleSearchMode(rawValue: mode.rawValue) ?? .phrase, scope: referenceScope, progress: progress).map {
                BibleSearchResult(reference: $0.reference, moduleID: $0.contentID.rawValue,
                                  text: ScriptureTextSanitizer.plainText($0.text), score: $0.score)
            }
    }

    func catalog(at directory: URL) async throws -> LocalCatalog {
        LocalCatalog(directory: directory, modules: try await provider.localCatalog(at: directory).map { Self.catalogModule($0, sourceID: "local") })
    }

    func install(moduleID: String, from catalog: LocalCatalog) async throws {
        try await provider.install(contentID: BibleContentID(rawValue: moduleID), from: catalog.directory)
    }

    func remoteBibles(from source: ModuleSource) async throws -> [CatalogModule] {
        try await provider.remoteCatalog(from: Self.repository(for: source), acknowledgingRemoteAccessRisks: true)
            .map { Self.catalogModule($0, sourceID: source.id) }
            .sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
    }

    func installRemote(moduleID: String, from source: ModuleSource,
                       progress: @escaping @Sendable (ModuleTransferProgress) -> Void) async throws {
        try await provider.install(contentID: BibleContentID(rawValue: moduleID), from: Self.repository(for: source),
            acknowledgingRemoteAccessRisks: true) {
                progress(ModuleTransferProgress(completedBytes: $0.completedBytes, totalBytes: $0.totalBytes))
            }
    }

    func remove(moduleID: String) async throws { try await provider.remove(contentID: BibleContentID(rawValue: moduleID)) }

    private static func title(_ content: BibleContentDescriptor) -> String { content.title.isEmpty ? content.contentID.rawValue : content.title }
    private static func category(_ kind: BibleContentKind) -> ModuleContentCategory {
        switch kind {
        case .bible: .bible
        case .commentary: .commentary
        case .dictionary: .dictionary
        case .devotional: .devotional
        case .generalBook: .generalBook
        case .readingPlan, .other: .other
        }
    }
    private static func catalogModule(_ content: BibleContentDescriptor, sourceID: String) -> CatalogModule {
        CatalogModule(id: content.contentID.rawValue, title: title(content), language: content.languageCode,
                      version: content.version, copyright: content.license.attribution,
                      category: category(content.kind), sourceID: sourceID)
    }
    private static func repository(for source: ModuleSource) throws -> SwordModuleRepository {
        try SwordModuleRepository(identifier: source.id, name: source.name, transport: .https,
            host: source.host, directory: source.catalogPath, packageDirectory: source.packagePath)
    }
}
