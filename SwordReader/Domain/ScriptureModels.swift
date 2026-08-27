import Foundation

struct BibleModule: Identifiable, Hashable, Sendable {
    let id: String
    let title: String
    let language: String
    let version: String?
    let copyright: String?
}

enum ModuleContentCategory: String, Hashable, Sendable {
    case bible
    case commentary
    case dictionary
    case generalBook
    case devotional
    case other

    var title: String {
        switch self {
        case .bible: String(localized: "Bible")
        case .commentary: String(localized: "Commentary")
        case .dictionary: String(localized: "Dictionary")
        case .generalBook: String(localized: "Book")
        case .devotional: String(localized: "Devotional")
        case .other: String(localized: "Other")
        }
    }

    var supportsReading: Bool {
        switch self {
        case .bible, .dictionary, .generalBook, .devotional: true
        case .commentary, .other: false
        }
    }
}

struct KeyedModule: Identifiable, Hashable, Sendable {
    let id: String
    let title: String
    let language: String
    let version: String?
    let copyright: String?
    let category: ModuleContentCategory
}

struct KeyedModuleEntry: Hashable, Sendable {
    let key: String
    let text: String
    let html: String
}

struct BibleBook: Identifiable, Hashable, Sendable {
    enum Testament: Hashable, Sendable {
        case old
        case new
    }

    let id: String
    let name: String
    let abbreviation: String
    let chapterCount: Int
    let testament: Testament
}

struct BibleVerse: Identifiable, Hashable, Sendable {
    var id: String { reference }
    let reference: String
    let number: String
    let text: String
    let content: AttributedString
    let headings: [BibleHeading]
    let footnotes: [BibleFootnote]
    let crossReferences: [BibleCrossReference]

    var annotationCount: Int {
        footnotes.count + crossReferences.reduce(0) { $0 + $1.references.count }
    }
}

struct BibleHeading: Identifiable, Hashable, Sendable {
    var id: String { identifier }
    let identifier: String
    let text: String
}

struct BibleFootnote: Identifiable, Hashable, Sendable {
    let id: String
    let text: String
    let type: String?
}

struct BibleCrossReference: Identifiable, Hashable, Sendable {
    let id: String
    let references: [String]
}

struct BibleChapter: Hashable, Sendable {
    let reference: String
    let moduleID: String
    let verses: [BibleVerse]
}

struct ParallelVerse: Identifiable, Hashable, Sendable {
    var id: String { reference }
    let reference: String
    let texts: [ParallelVerseText]
    let lexicalLinks: [OriginalLanguageLink]
}

struct ParallelVerseText: Identifiable, Hashable, Sendable {
    var id: String { moduleID }
    let moduleID: String
    let text: String?
}

struct OriginalLanguageLink: Identifiable, Hashable, Sendable {
    var id: String { strongsNumber }
    let strongsNumber: String
    let words: [String]
}

struct BibleSearchResult: Identifiable, Hashable, Sendable {
    var id: String { "\(moduleID):\(reference)" }
    let reference: String
    let moduleID: String
    let text: String
    let score: Int
}

enum ScriptureSearchMode: String, CaseIterable, Identifiable, Sendable {
    case phrase
    case allWords
    case regularExpression
    case strongs
    case morphology

    var id: Self { self }

    var title: String {
        switch self {
        case .phrase: String(localized: "Phrase")
        case .allWords: String(localized: "All Words")
        case .regularExpression: String(localized: "Pattern")
        case .strongs: String(localized: "Strong’s")
        case .morphology: String(localized: "Morphology")
        }
    }
}

enum ScriptureSearchScope: String, CaseIterable, Identifiable, Sendable {
    case wholeBible
    case oldTestament
    case newTestament

    var id: Self { self }

    var title: String {
        switch self {
        case .wholeBible: String(localized: "Whole Bible")
        case .oldTestament: String(localized: "Old Testament")
        case .newTestament: String(localized: "New Testament")
        }
    }
}

struct CatalogModule: Identifiable, Hashable, Sendable {
    let id: String
    let title: String
    let language: String
    let version: String?
    let copyright: String?
    let category: ModuleContentCategory
    let sourceID: String

    var isBible: Bool { category == .bible }

    init(
        id: String,
        title: String,
        language: String,
        version: String?,
        copyright: String?,
        category: ModuleContentCategory,
        sourceID: String
    ) {
        self.id = id
        self.title = title
        self.language = language
        self.version = version
        self.copyright = copyright
        self.category = category
        self.sourceID = sourceID
    }

    init(
        id: String,
        title: String,
        language: String,
        version: String?,
        copyright: String?,
        isBible: Bool,
        sourceID: String
    ) {
        self.init(
            id: id,
            title: title,
            language: language,
            version: version,
            copyright: copyright,
            category: isBible ? .bible : .other,
            sourceID: sourceID
        )
    }

    var compatibility: ModuleCompatibility {
        if !category.supportsReading { return .unsupportedCategory }
        if id.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
            language.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return .missingMetadata
        }
        return .compatible
    }
}

enum ModuleCompatibility: String, Hashable, Sendable {
    case compatible
    case unsupportedCategory
    case missingMetadata

    var title: String {
        switch self {
        case .compatible: String(localized: "Compatible")
        case .unsupportedCategory: String(localized: "Unsupported module category")
        case .missingMetadata: String(localized: "Missing required metadata")
        }
    }
}

enum CatalogFilter {
    static func availableLanguages(in modules: [CatalogModule]) -> [String] {
        Array(Set(modules.lazy
            .map(\.language)
            .filter { !$0.isEmpty }))
            .sorted { languageName(for: $0).localizedStandardCompare(languageName(for: $1)) == .orderedAscending }
    }

    static func apply(
        to modules: [CatalogModule],
        query: String,
        language: String?
    ) -> [CatalogModule] {
        modules.filter { module in
            guard language == nil || module.language == language else { return false }
            guard !query.isEmpty else { return true }
            return [module.title, module.id, module.language, languageName(for: module.language)]
                .contains { $0.localizedCaseInsensitiveContains(query) }
        }
    }

    static func languageName(for code: String) -> String {
        Locale.current.localizedString(forLanguageCode: code) ?? code
    }
}

enum CatalogLanguagePreference {
    static let defaultsKey = "catalog.selectedLanguage"
    static let allLanguagesValue = "*"

    static func selection(
        available: [String],
        preferredLanguages: [String],
        savedValue: String?
    ) -> String? {
        if savedValue == allLanguagesValue { return nil }
        if let savedValue,
           let saved = available.first(where: {
               $0.caseInsensitiveCompare(savedValue) == .orderedSame
           }) {
            return saved
        }

        for preferredLanguage in preferredLanguages {
            let languageCode = preferredLanguage
                .split(whereSeparator: { $0 == "-" || $0 == "_" })
                .first
                .map(String.init)
            if let languageCode,
               let match = available.first(where: {
                   $0.caseInsensitiveCompare(languageCode) == .orderedSame
               }) {
                return match
            }
        }

        return available.first {
            $0.caseInsensitiveCompare("en") == .orderedSame
        }
    }
}

struct ModuleSource: Codable, Hashable, Identifiable, Sendable {
    let id: String
    let name: String
    let host: String
    let catalogPath: String
    let packagePath: String
    let isCurated: Bool

    static let crossWire = ModuleSource(
        id: "crosswire",
        name: "CrossWire Bible Society",
        host: "www.crosswire.org",
        catalogPath: "/ftpmirror/pub/sword/raw",
        packagePath: "/ftpmirror/pub/sword/packages/rawzip",
        isCurated: true
    )

    static let eBible = ModuleSource(
        id: "ebible",
        name: "eBible.org",
        host: "ebible.org",
        catalogPath: "/sword",
        packagePath: "/sword/zip",
        isCurated: true
    )

    static func validated(
        name: String,
        host: String,
        catalogPath: String,
        packagePath: String
    ) throws -> ModuleSource {
        let cleanName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanHost = host.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let cleanCatalog = catalogPath.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanPackages = packagePath.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanName.isEmpty,
              !cleanHost.isEmpty,
              !cleanHost.contains("://"),
              !cleanHost.contains("/"),
              cleanHost.contains("."),
              Self.isSafePath(cleanCatalog),
              Self.isSafePath(cleanPackages)
        else { throw ModuleSourceError.invalidEndpoint }

        let identifier = "custom-" + cleanHost + "-" + String(
            cleanCatalog.unicodeScalars.reduce(into: UInt64(5381)) {
                $0 = (($0 << 5) &+ $0) &+ UInt64($1.value)
            },
            radix: 16
        )
        return ModuleSource(
            id: identifier,
            name: cleanName,
            host: cleanHost,
            catalogPath: cleanCatalog,
            packagePath: cleanPackages,
            isCurated: false
        )
    }

    private static func isSafePath(_ path: String) -> Bool {
        path.hasPrefix("/") && !path.contains("..") && !path.contains("\\")
    }
}

enum ModuleSourceError: LocalizedError {
    case invalidEndpoint

    var errorDescription: String? {
        String(localized: "Enter a valid HTTPS host and absolute catalog and package paths.")
    }
}

struct LocalCatalog: Hashable, Sendable {
    let directory: URL
    let modules: [CatalogModule]
}

struct ModuleTransferProgress: Hashable, Sendable {
    let completedBytes: UInt64
    let totalBytes: UInt64

    var fractionCompleted: Double? {
        guard totalBytes > 0 else { return nil }
        return min(Double(completedBytes) / Double(totalBytes), 1)
    }
}

enum ReaderFont: String, CaseIterable, Identifiable, Sendable {
    case system
    case serif
    case rounded

    var id: Self { self }

    var title: String {
        switch self {
        case .system: String(localized: "System")
        case .serif: String(localized: "Serif")
        case .rounded: String(localized: "Rounded")
        }
    }
}

enum ReaderTextSize: String, CaseIterable, Identifiable, Sendable {
    case small
    case standard
    case large
    case extraLarge

    var id: Self { self }

    var title: String {
        switch self {
        case .small: String(localized: "Small")
        case .standard: String(localized: "Default")
        case .large: String(localized: "Large")
        case .extraLarge: String(localized: "Extra Large")
        }
    }
}

enum ReaderSpacing: String, CaseIterable, Identifiable, Sendable {
    case compact
    case comfortable
    case relaxed

    var id: Self { self }

    var title: String {
        switch self {
        case .compact: String(localized: "Compact")
        case .comfortable: String(localized: "Comfortable")
        case .relaxed: String(localized: "Relaxed")
        }
    }
}

enum AppAppearance: String, CaseIterable, Identifiable, Sendable {
    case system
    case light
    case dark

    var id: Self { self }

    var title: String {
        switch self {
        case .system: String(localized: "System")
        case .light: String(localized: "Light")
        case .dark: String(localized: "Dark")
        }
    }
}

struct StudyItem: Identifiable, Hashable, Sendable {
    enum Kind: String, Hashable, Sendable {
        case bookmark
        case note
        case highlight
    }

    var id: String { "\(kind.rawValue):\(moduleID):\(reference)" }
    let kind: Kind
    let moduleID: String
    let reference: String
    let text: String?
}

enum AppSection: String, CaseIterable, Identifiable, Sendable {
    case read
    case study
    case plans
    case search
    case library
    case settings

    var id: Self { self }

    static var primarySections: [Self] {
        allCases.filter { $0 != .settings }
    }

    var title: String {
        switch self {
        case .read: String(localized: "Read")
        case .study: String(localized: "Notes & Highlights")
        case .plans: String(localized: "Plans")
        case .search: String(localized: "Search")
        case .library: String(localized: "Library")
        case .settings: String(localized: "Settings")
        }
    }

    var systemImage: String {
        switch self {
        case .read: "book.pages"
        case .study: "highlighter"
        case .plans: "calendar"
        case .search: "magnifyingglass"
        case .library: "books.vertical"
        case .settings: "gearshape"
        }
    }
}

struct ReadingPlanSelection: Codable, Hashable, Sendable {
    let planID: String
    let startedAt: Date
    var completedDayIDs: Set<Int>
}

struct ReaderDestination: Codable, Hashable, Sendable {
    let moduleID: String?
    let reference: String

    init(moduleID: String? = nil, reference: String) {
        self.moduleID = moduleID
        self.reference = reference
    }

    init?(url: URL) {
        guard url.scheme?.lowercased() == "swordreader",
              url.host?.lowercased() == "read",
              let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let reference = components.queryItems?.first(
                where: { $0.name == "reference" }
              )?.value,
              !reference.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else { return nil }

        self.reference = reference
        moduleID = components.queryItems?.first { $0.name == "module" }?.value
    }

    var url: URL? {
        var components = URLComponents()
        components.scheme = "swordreader"
        components.host = "read"
        components.queryItems = [
            URLQueryItem(name: "reference", value: reference),
            moduleID.map { URLQueryItem(name: "module", value: $0) }
        ].compactMap { $0 }
        return components.url
    }
}

struct ReaderTab: Codable, Identifiable, Hashable, Sendable {
    let id: UUID
    var destination: ReaderDestination

    init(id: UUID = UUID(), destination: ReaderDestination) {
        self.id = id
        self.destination = destination
    }
}

struct SideBySideReaderPane: Identifiable, Hashable, Sendable {
    let id: ReaderTab.ID
    let destination: ReaderDestination
    let chapter: BibleChapter
}

struct SideBySideReaderPair: Hashable, Sendable {
    let leading: SideBySideReaderPane
    let trailing: SideBySideReaderPane
}

struct ReaderTabSession: Codable, Hashable, Sendable {
    let tabs: [ReaderTab]
    let selectedTabID: ReaderTab.ID

    init?(tabs: [ReaderTab], selectedTabID: ReaderTab.ID) {
        guard !tabs.isEmpty,
              tabs.contains(where: { $0.id == selectedTabID })
        else { return nil }
        self.tabs = tabs
        self.selectedTabID = selectedTabID
    }

    init?(encoded: String) {
        guard let data = Data(base64Encoded: encoded),
              let session = try? JSONDecoder().decode(Self.self, from: data),
              !session.tabs.isEmpty,
              session.tabs.contains(where: { $0.id == session.selectedTabID })
        else { return nil }
        self = session
    }

    var encoded: String? {
        try? JSONEncoder().encode(self).base64EncodedString()
    }
}

struct KeyedReaderTab: Identifiable, Hashable, Sendable {
    let id: UUID
    var moduleID: String
    var key: String

    init(id: UUID = UUID(), moduleID: String = "", key: String) {
        self.id = id
        self.moduleID = moduleID
        self.key = key
    }
}

struct KeyedReaderTabPair: Hashable, Sendable {
    let leading: KeyedReaderTab
    let trailing: KeyedReaderTab
}

struct KeyedReaderTabs: Hashable, Sendable {
    private(set) var tabs: [KeyedReaderTab]
    private(set) var selectedTabID: KeyedReaderTab.ID

    init(initialModuleID: String = "", initialKey: String) {
        let tab = KeyedReaderTab(moduleID: initialModuleID, key: initialKey)
        tabs = [tab]
        selectedTabID = tab.id
    }

    var selectedKey: String {
        tabs.first { $0.id == selectedTabID }?.key ?? tabs[0].key
    }

    mutating func createTab() {
        let selected = tabs.first { $0.id == selectedTabID } ?? tabs[0]
        let tab = KeyedReaderTab(moduleID: selected.moduleID, key: selected.key)
        tabs.append(tab)
        selectedTabID = tab.id
    }

    mutating func selectTab(_ id: KeyedReaderTab.ID) {
        guard tabs.contains(where: { $0.id == id }) else { return }
        selectedTabID = id
    }

    mutating func selectKey(_ key: String) {
        guard let index = tabs.firstIndex(where: { $0.id == selectedTabID }) else {
            return
        }
        tabs[index].key = key
    }

    mutating func selectModule(_ moduleID: String, key: String) {
        selectModule(moduleID, key: key, in: selectedTabID)
    }

    mutating func selectModule(
        _ moduleID: String,
        key: String,
        in tabID: KeyedReaderTab.ID
    ) {
        guard let index = tabs.firstIndex(where: { $0.id == tabID }) else {
            return
        }
        tabs[index].moduleID = moduleID
        tabs[index].key = key
    }

    mutating func moveTab(_ id: KeyedReaderTab.ID, to targetID: KeyedReaderTab.ID) {
        guard id != targetID,
              let sourceIndex = tabs.firstIndex(where: { $0.id == id }),
              let targetIndex = tabs.firstIndex(where: { $0.id == targetID })
        else { return }

        let tab = tabs.remove(at: sourceIndex)
        tabs.insert(tab, at: targetIndex)
    }

    mutating func closeTab(_ id: KeyedReaderTab.ID) {
        guard tabs.count > 1,
              let index = tabs.firstIndex(where: { $0.id == id })
        else { return }

        let wasSelected = selectedTabID == id
        tabs.remove(at: index)
        if wasSelected {
            selectedTabID = tabs[min(index, tabs.count - 1)].id
        }
    }
}

struct ReadingHistoryEntry: Codable, Identifiable, Hashable, Sendable {
    var id: String { "\(moduleID):\(reference)" }
    let moduleID: String
    let reference: String
    let visitedAt: Date
}
