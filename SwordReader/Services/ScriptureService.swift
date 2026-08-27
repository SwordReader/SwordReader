import Foundation
import SwordKit

protocol ScriptureServing: Sendable {
    func installedBibles() async throws -> [BibleModule]
    func installedKeyedModules() async throws -> [KeyedModule]
    func keyedEntryKeys(moduleID: String) async throws -> [String]
    func keyedEntry(moduleID: String, key: String) async throws -> KeyedModuleEntry
    func books(moduleID: String) async throws -> [BibleBook]
    func chapter(_ reference: String, moduleID: String) async throws -> BibleChapter
    func parallelChapter(
        _ reference: String,
        moduleIDs: [String]
    ) async throws -> [ParallelVerse]
    func search(
        _ query: String,
        moduleID: String,
        mode: ScriptureSearchMode,
        scope: ScriptureSearchScope,
        progress: @escaping @Sendable (Int) -> Void
    ) async throws -> [BibleSearchResult]
    func catalog(at directory: URL) async throws -> LocalCatalog
    func install(moduleID: String, from catalog: LocalCatalog) async throws
    func remoteBibles(from source: ModuleSource) async throws -> [CatalogModule]
    func installRemote(
        moduleID: String,
        from source: ModuleSource,
        progress: @escaping @Sendable (ModuleTransferProgress) -> Void
    ) async throws
    func remove(moduleID: String) async throws
}

actor SwordScriptureService: ScriptureServing {
    private let library: SwordLibrary
    private let installer: SwordModuleInstaller

    init() throws {
        let location = try SwordModuleLocation.applicationSupport()
        let repository = try SwordModuleRepository(
            identifier: "crosswire",
            name: "CrossWire Bible Society",
            transport: .https,
            host: "www.crosswire.org",
            directory: "/ftpmirror/pub/sword/raw",
            packageDirectory: "/ftpmirror/pub/sword/packages/rawzip"
        )
        library = try SwordLibrary(location: location)
        installer = SwordModuleInstaller(
            configuration: SwordInstallerConfiguration(
                location: location,
                repositories: [repository]
            )
        )
    }

    func installedBibles() -> [BibleModule] {
        library.modules(category: .bible).map {
            BibleModule(
                id: $0.name,
                title: $0.title.isEmpty ? $0.name : $0.title,
                language: $0.language,
                version: $0.version,
                copyright: $0.copyright
            )
        }
        .sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
    }

    func installedKeyedModules() -> [KeyedModule] {
        library.modules
            .filter { $0.category.supportsKeyedEntries }
            .map {
                KeyedModule(
                    id: $0.name,
                    title: $0.title.isEmpty ? $0.name : $0.title,
                    language: $0.language,
                    version: $0.version,
                    copyright: $0.copyright,
                    category: $0.category.contentCategory
                )
            }
            .sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
    }

    func keyedEntryKeys(moduleID: String) throws -> [String] {
        guard let module = library.module(named: moduleID) else {
            throw SwordError.moduleNotFound(moduleID)
        }
        return try module.keyedEntryKeys()
    }

    func keyedEntry(moduleID: String, key: String) throws -> KeyedModuleEntry {
        guard let module = library.module(named: moduleID) else {
            throw SwordError.moduleNotFound(moduleID)
        }
        let entry = try module.keyedEntry(for: key)
        return KeyedModuleEntry(key: entry.key, text: entry.text, html: entry.html)
    }

    func books(moduleID: String) throws -> [BibleBook] {
        guard let module = library.module(named: moduleID) else {
            throw SwordError.moduleNotFound(moduleID)
        }

        return try module.books().map {
            BibleBook(
                id: $0.osisName,
                name: $0.name,
                abbreviation: $0.preferredAbbreviation,
                chapterCount: $0.chapterCount,
                testament: $0.testament == .old ? .old : .new
            )
        }
    }

    func chapter(_ reference: String, moduleID: String) async throws -> BibleChapter {
        guard let module = library.module(named: moduleID) else {
            throw SwordError.moduleNotFound(moduleID)
        }

        let chapter = try module.chapter(reference)
        let verses = chapter.verses.map { verse in
            BibleVerse(
                reference: verse.reference.value,
                number: Self.verseNumber(from: verse.reference.value),
                text: verse.text,
                content: (try? module.attributedString(verse.reference.value))
                    ?? AttributedString(verse.text),
                headings: verse.headings.map {
                    BibleHeading(
                        identifier: $0.identifier,
                        text: $0.body
                    )
                },
                footnotes: verse.footnotes.map {
                    BibleFootnote(
                        id: $0.identifier,
                        text: $0.body,
                        type: $0.type
                    )
                },
                crossReferences: verse.crossReferences.map {
                    BibleCrossReference(
                        id: $0.footnoteIdentifier,
                        references: $0.references.map(\.value)
                    )
                }
            )
        }
        return BibleChapter(
            reference: chapter.reference.value,
            moduleID: chapter.moduleName,
            verses: verses
        )
    }

    func parallelChapter(
        _ reference: String,
        moduleIDs: [String]
    ) async throws -> [ParallelVerse] {
        guard let primary = moduleIDs.first,
              let module = library.module(named: primary)
        else { throw SwordError.moduleNotFound(moduleIDs.first ?? "") }

        let chapter = try module.chapter(reference)
        guard let first = chapter.verses.first?.reference.value,
              let last = chapter.verses.last?.reference.value,
              let endingVerse = last.split(separator: ":").last
        else { return [] }

        let parallel = try await library.parallelPassageAsync(
            "\(first)-\(endingVerse)",
            modules: moduleIDs
        )
        return parallel.alignedVerses.map { row in
            ParallelVerse(
                reference: row.reference.value,
                texts: moduleIDs.map {
                    ParallelVerseText(
                        moduleID: $0,
                        text: row.versesByModule[$0]?.text
                    )
                },
                lexicalLinks: row.comparison.wordLinks.map { link in
                    OriginalLanguageLink(
                        strongsNumber: link.strongsNumber,
                        words: link.locations.map {
                            "\($0.moduleName): \($0.token.text)"
                        }
                    )
                }
            )
        }
    }

    func search(
        _ query: String,
        moduleID: String,
        mode: ScriptureSearchMode,
        scope: ScriptureSearchScope,
        progress: @escaping @Sendable (Int) -> Void
    ) async throws -> [BibleSearchResult] {
        guard let module = library.module(named: moduleID) else {
            throw SwordError.moduleNotFound(moduleID)
        }

        return try await module.searchAsync(
            query,
            type: mode.swordType,
            caseSensitive: false,
            scope: scope.swordScope,
            progress: progress
        ).rankedByRelevance().map {
            BibleSearchResult(
                reference: $0.reference.value,
                moduleID: $0.moduleName,
                text: ScriptureTextSanitizer.plainText($0.text),
                score: $0.score
            )
        }
    }

    func catalog(at directory: URL) throws -> LocalCatalog {
        let catalog = try SwordModuleCatalog(directory: directory)
        return LocalCatalog(
            directory: catalog.directory,
            modules: catalog.modules.map {
                CatalogModule(
                    id: $0.name,
                    title: $0.title.isEmpty ? $0.name : $0.title,
                    language: $0.language,
                    version: $0.version,
                    copyright: $0.copyright,
                    category: $0.category.contentCategory,
                    sourceID: "local"
                )
            }
        )
    }

    func install(moduleID: String, from catalog: LocalCatalog) throws {
        let source = try SwordModuleCatalog(directory: catalog.directory)
        try installer.install(moduleNamed: moduleID, from: source)
        library.refresh()
    }

    func remoteBibles(from source: ModuleSource) async throws -> [CatalogModule] {
        let repository = try Self.repository(for: source)
        let catalog = try await installer.refreshCatalog(
            for: repository,
            acknowledgingRemoteAccessRisks: true
        )
        return catalog.modules
            .map { Self.catalogModule($0, sourceID: source.id) }
            .sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
    }

    func installRemote(
        moduleID: String,
        from source: ModuleSource,
        progress: @escaping @Sendable (ModuleTransferProgress) -> Void
    ) async throws {
        let repository = try Self.repository(for: source)
        try await installer.install(
            moduleNamed: moduleID,
            from: repository,
            acknowledgingRemoteAccessRisks: true
        ) { transfer in
            progress(
                ModuleTransferProgress(
                    completedBytes: transfer.completedBytes,
                    totalBytes: transfer.totalBytes
                )
            )
        }
        library.refresh()
    }

    func remove(moduleID: String) throws {
        try installer.remove(moduleNamed: moduleID)
        library.refresh()
    }

    private static func verseNumber(from reference: String) -> String {
        reference.split(separator: ":").last.map(String.init) ?? reference
    }

    private static func catalogModule(
        _ module: SwordModuleCatalogEntry,
        sourceID: String
    ) -> CatalogModule {
        CatalogModule(
            id: module.name,
            title: module.title.isEmpty ? module.name : module.title,
            language: module.language,
            version: module.version,
            copyright: module.copyright,
            category: module.category.contentCategory,
            sourceID: sourceID
        )
    }

    private static func repository(for source: ModuleSource) throws -> SwordModuleRepository {
        try SwordModuleRepository(
            identifier: source.id,
            name: source.name,
            transport: .https,
            host: source.host,
            directory: source.catalogPath,
            packageDirectory: source.packagePath
        )
    }
}

private extension SwordModule.Category {
    var contentCategory: ModuleContentCategory {
        switch self {
        case .bible: .bible
        case .commentary: .commentary
        case .dictionary: .dictionary
        case .generalBook: .generalBook
        case .devotional: .devotional
        case .other: .other
        }
    }
}

private extension ScriptureSearchMode {
    var swordType: SwordSearchType {
        switch self {
        case .phrase: .phrase
        case .allWords: .multiWord
        case .regularExpression: .regularExpression
        case .strongs: .strongs
        case .morphology: .morphology
        }
    }
}

private extension ScriptureSearchScope {
    var swordScope: String? {
        switch self {
        case .wholeBible: nil
        case .oldTestament: "Gen-Mal"
        case .newTestament: "Matt-Rev"
        }
    }
}
