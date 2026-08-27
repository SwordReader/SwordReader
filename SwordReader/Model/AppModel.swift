import Foundation
import Observation
import SwordKit

extension Notification.Name {
    static let readerPreferencesDidChange = Notification.Name(
        "SwordReader.readerPreferencesDidChange"
    )
}

@MainActor
@Observable
final class AppModel {
    var section: AppSection = .read
    private(set) var readerFont: ReaderFont
    private(set) var readerTextSize: ReaderTextSize
    private(set) var readerFontSize: Double
    private(set) var readerSpacing: ReaderSpacing
    private(set) var showsVerseNumbers: Bool
    private(set) var showsRedLetterText: Bool
    private(set) var appAppearance: AppAppearance
    private(set) var modules: [BibleModule] = []
    private(set) var keyedModules: [KeyedModule] = []
    private(set) var readerTabs: [ReaderTab] = []
    private(set) var selectedReaderTabID: ReaderTab.ID?
    private(set) var sideBySidePanes: [SideBySideReaderPane] = []
    private(set) var selectedModuleID: String?
    private(set) var books: [BibleBook] = []
    private(set) var selectedBookID: String?
    private(set) var selectedChapter = 1
    private(set) var chapter: BibleChapter?
    private(set) var parallelVerses: [ParallelVerse] = []
    private(set) var comparisonModuleID: String?
    private(set) var isLoadingComparison = false
    private(set) var searchResults: [BibleSearchResult] = []
    private(set) var searchResultCount = 0
    private(set) var searchMode: ScriptureSearchMode
    private(set) var searchScope: ScriptureSearchScope
    private(set) var searchProgress: Int?
    private(set) var recentSearches: [String]
    private(set) var studyItems: [StudyItem] = []
    private(set) var readingHistory: [ReadingHistoryEntry]
    private(set) var readingPlanSelection: ReadingPlanSelection?
    private(set) var readingPlanReminderTime: Date?
    private(set) var catalog: LocalCatalog?
    private(set) var remoteModules: [CatalogModule] = []
    private(set) var moduleSources: [ModuleSource]
    private(set) var selectedModuleSourceID: String
    private(set) var isLoading = false
    private(set) var isSearching = false
    private(set) var isInstalling = false
    private(set) var isRefreshingRemoteCatalog = false
    private(set) var installingModuleID: String?
    private(set) var installProgress: ModuleTransferProgress?
    private(set) var removingModuleID: String?
    private(set) var sendingModuleID: String?
    private(set) var isPresentingOnboarding = false
    var presentedError: PresentedError?
    var continuityNotice: ContinuityNotice?
    private(set) var pendingCrashDiagnostic: CrashDiagnosticReport?

    private let service: any ScriptureServing
    private let defaults: UserDefaults
    private let studyStore: (any StudyDataServing)?
    private let companionSync: (any CompanionSyncing)?
    private let reminderScheduler: (any ReadingPlanReminderScheduling)?
    private var chapterTask: Task<Void, Never>?
    private var searchTask: Task<Void, Never>?
    private var searchGeneration = UUID()
    private var remoteInstallTask: Task<Void, Error>?
    private var comparisonTask: Task<Void, Never>?
    private static let moduleKey = "selectedBibleModule"
    private static let bookKeyPrefix = "readerBook."
    private static let chapterKeyPrefix = "readerChapter."
    private static let completedOnboardingKey = "completedOnboarding"
    private static let readerFontKey = "reader.font"
    private static let readerTextSizeKey = "reader.textSize"
    private static let readerFontSizeKey = "reader.fontSize"
    private static let readerSpacingKey = "reader.spacing"
    private static let showsVerseNumbersKey = "reader.showsVerseNumbers"
    private static let showsRedLetterTextKey = "reader.showsRedLetterText"
    private static let appAppearanceKey = "app.appearance"
    private static let searchModeKey = "search.mode"
    private static let searchScopeKey = "search.scope"
    private static let recentSearchesKey = "search.recents"
    private static let readingHistoryKey = "reader.history"
    private static let readingPlanKey = "plans.selection"
    private static let readingPlanReminderHourKey = "plans.reminder.hour"
    private static let readingPlanReminderMinuteKey = "plans.reminder.minute"
    private static let moduleSourcesKey = "modules.approvedSources"
    private static let selectedModuleSourceKey = "modules.selectedSource"
    private static let maximumVisibleSearchResults = 250

    var searchResultsWereLimited: Bool {
        searchResultCount > searchResults.count
    }

    init(
        service: any ScriptureServing,
        studyStore: (any StudyDataServing)? = nil,
        companionSync: (any CompanionSyncing)? = nil,
        reminderScheduler: (any ReadingPlanReminderScheduling)? = nil,
        defaults: UserDefaults = .standard
    ) {
        self.service = service
        self.studyStore = studyStore
        self.companionSync = companionSync
        self.reminderScheduler = reminderScheduler
        self.defaults = defaults
        pendingCrashDiagnostic = CrashDiagnosticStore(
            defaults: defaults
        ).pendingReport()
        readerFont = ReaderFont(
            rawValue: defaults.string(forKey: Self.readerFontKey) ?? ""
        ) ?? .system
        readerTextSize = ReaderTextSize(
            rawValue: defaults.string(forKey: Self.readerTextSizeKey) ?? ""
        ) ?? .standard
        readerFontSize = defaults.object(forKey: Self.readerFontSizeKey) == nil
            ? 17
            : defaults.double(forKey: Self.readerFontSizeKey)
        readerSpacing = ReaderSpacing(
            rawValue: defaults.string(forKey: Self.readerSpacingKey) ?? ""
        ) ?? .comfortable
        showsVerseNumbers = defaults.object(
            forKey: Self.showsVerseNumbersKey
        ).map { _ in defaults.bool(forKey: Self.showsVerseNumbersKey) } ?? true
        showsRedLetterText = defaults.object(
            forKey: Self.showsRedLetterTextKey
        ).map { _ in defaults.bool(forKey: Self.showsRedLetterTextKey) } ?? true
        appAppearance = AppAppearance(
            rawValue: defaults.string(forKey: Self.appAppearanceKey) ?? ""
        ) ?? .system
        searchMode = ScriptureSearchMode(
            rawValue: defaults.string(forKey: Self.searchModeKey) ?? ""
        ) ?? .phrase
        searchScope = ScriptureSearchScope(
            rawValue: defaults.string(forKey: Self.searchScopeKey) ?? ""
        ) ?? .wholeBible
        recentSearches = defaults.stringArray(
            forKey: Self.recentSearchesKey
        ) ?? []
        readingHistory = defaults.data(forKey: Self.readingHistoryKey)
            .flatMap { try? JSONDecoder().decode([ReadingHistoryEntry].self, from: $0) }
            ?? []
        readingPlanSelection = defaults.data(forKey: Self.readingPlanKey)
            .flatMap { try? JSONDecoder().decode(ReadingPlanSelection.self, from: $0) }
        let savedSources = defaults.data(forKey: Self.moduleSourcesKey)
            .flatMap { try? JSONDecoder().decode([ModuleSource].self, from: $0) }
            ?? []
        let approvedSources = [ModuleSource.crossWire] + savedSources.filter { $0.id != ModuleSource.crossWire.id }
        moduleSources = approvedSources
        let savedSourceID = defaults.string(forKey: Self.selectedModuleSourceKey)
        selectedModuleSourceID = approvedSources.contains(where: { $0.id == savedSourceID })
            ? (savedSourceID ?? ModuleSource.crossWire.id)
            : ModuleSource.crossWire.id
        if defaults.object(forKey: Self.readingPlanReminderHourKey) != nil {
            readingPlanReminderTime = Calendar.current.date(
                from: DateComponents(
                    hour: defaults.integer(forKey: Self.readingPlanReminderHourKey),
                    minute: defaults.integer(forKey: Self.readingPlanReminderMinuteKey)
                )
            )
        }
    }

    var readingPlans: [SwordReadingPlan] { BuiltInReadingPlans.all }

    var selectedReadingPlan: SwordReadingPlan? {
        guard let id = readingPlanSelection?.planID else { return nil }
        return readingPlans.first { $0.id == id }
    }

    func startReadingPlan(_ planID: String) {
        guard readingPlans.contains(where: { $0.id == planID }) else { return }
        readingPlanSelection = ReadingPlanSelection(
            planID: planID,
            startedAt: .now,
            completedDayIDs: []
        )
        persistReadingPlanSelection()
    }

    func stopReadingPlan() {
        readingPlanSelection = nil
        defaults.removeObject(forKey: Self.readingPlanKey)
        disableReadingPlanReminder()
    }

    func setReadingPlanReminder(at time: Date) async {
        guard readingPlanSelection != nil, let reminderScheduler else { return }
        let components = Calendar.current.dateComponents([.hour, .minute], from: time)
        guard let hour = components.hour, let minute = components.minute else { return }
        do {
            try await reminderScheduler.scheduleDaily(hour: hour, minute: minute)
            readingPlanReminderTime = time
            defaults.set(hour, forKey: Self.readingPlanReminderHourKey)
            defaults.set(minute, forKey: Self.readingPlanReminderMinuteKey)
        } catch { presentedError = PresentedError(error) }
    }

    func disableReadingPlanReminder() {
        reminderScheduler?.disable()
        readingPlanReminderTime = nil
        defaults.removeObject(forKey: Self.readingPlanReminderHourKey)
        defaults.removeObject(forKey: Self.readingPlanReminderMinuteKey)
    }

    func toggleReadingPlanDay(_ dayID: Int) {
        guard var selection = readingPlanSelection,
              selectedReadingPlan?.days.contains(where: { $0.id == dayID }) == true
        else { return }
        if selection.completedDayIDs.contains(dayID) {
            selection.completedDayIDs.remove(dayID)
        } else {
            selection.completedDayIDs.insert(dayID)
        }
        readingPlanSelection = selection
        persistReadingPlanSelection()
    }

    func openPlanReading(_ reference: String) {
        section = .read
        open(reference: reference)
    }

    private func persistReadingPlanSelection() {
        guard let readingPlanSelection,
              let data = try? JSONEncoder().encode(readingPlanSelection)
        else { return }
        defaults.set(data, forKey: Self.readingPlanKey)
    }

    convenience init() {
        do {
            let service = try SwordScriptureService()
            let studyStore = try? StudyStore()
            #if canImport(WatchConnectivity) && !os(watchOS)
            let companionSync: (any CompanionSyncing)? = WatchPassageSync()
            #else
            let companionSync: (any CompanionSyncing)? = nil
            #endif
            self.init(
                service: service,
                studyStore: studyStore,
                companionSync: companionSync,
                reminderScheduler: ReadingPlanReminderScheduler()
            )
        } catch {
            self.init(service: UnavailableScriptureService(error: error))
            presentedError = PresentedError(error)
        }
    }

    func start() async {
        let hasCompletedOnboarding = defaults.bool(
            forKey: Self.completedOnboardingKey
        )
        do {
            studyItems = try studyStore?.fetchAll() ?? []
            modules = try await service.installedBibles()
            keyedModules = try await service.installedKeyedModules()
            isPresentingOnboarding = modules.isEmpty || !hasCompletedOnboarding
            let saved = defaults.string(forKey: Self.moduleKey)
            let moduleID = modules.contains(where: { $0.id == saved })
                ? saved
                : modules.first?.id

            if let moduleID {
                try await activateModule(moduleID, restoring: true)
            }
        } catch {
            isPresentingOnboarding = !hasCompletedOnboarding
            presentedError = PresentedError(error)
        }
    }

    func completeOnboarding() {
        defaults.set(true, forKey: Self.completedOnboardingKey)
        isPresentingOnboarding = false
        if modules.isEmpty {
            section = .library
        }
    }

    func setReaderFont(_ font: ReaderFont) {
        readerFont = font
        defaults.set(font.rawValue, forKey: Self.readerFontKey)
    }

    func setReaderTextSize(_ size: ReaderTextSize) {
        readerTextSize = size
        defaults.set(size.rawValue, forKey: Self.readerTextSizeKey)
        let fontSize: Double
        switch size {
        case .small: fontSize = 14
        case .standard: fontSize = 17
        case .large: fontSize = 21
        case .extraLarge: fontSize = 26
        }
        setReaderFontSize(fontSize)
    }

    func setReaderFontSize(_ size: Double) {
        readerFontSize = min(max(size, 12), 32)
        defaults.set(readerFontSize, forKey: Self.readerFontSizeKey)
        NotificationCenter.default.post(name: .readerPreferencesDidChange, object: nil)
    }

    func setReaderSpacing(_ spacing: ReaderSpacing) {
        readerSpacing = spacing
        defaults.set(spacing.rawValue, forKey: Self.readerSpacingKey)
    }

    func setShowsVerseNumbers(_ shows: Bool) {
        showsVerseNumbers = shows
        defaults.set(shows, forKey: Self.showsVerseNumbersKey)
    }

    func setShowsRedLetterText(_ shows: Bool) {
        showsRedLetterText = shows
        defaults.set(shows, forKey: Self.showsRedLetterTextKey)
        NotificationCenter.default.post(name: .readerPreferencesDidChange, object: nil)
    }

    func reloadReaderPreferences() {
        if defaults.object(forKey: Self.readerFontSizeKey) != nil {
            readerFontSize = min(max(defaults.double(forKey: Self.readerFontSizeKey), 12), 32)
        }
        showsRedLetterText = defaults.object(
            forKey: Self.showsRedLetterTextKey
        ).map { _ in defaults.bool(forKey: Self.showsRedLetterTextKey) } ?? true
    }

    func reloadPendingCrashDiagnostic() {
        pendingCrashDiagnostic = CrashDiagnosticStore(
            defaults: defaults
        ).pendingReport()
    }

    func clearPendingCrashDiagnostic() {
        CrashDiagnosticStore(defaults: defaults).clear()
        pendingCrashDiagnostic = nil
    }

    func setAppAppearance(_ appearance: AppAppearance) {
        appAppearance = appearance
        defaults.set(appearance.rawValue, forKey: Self.appAppearanceKey)
    }

    func setSearchMode(_ mode: ScriptureSearchMode) {
        searchMode = mode
        defaults.set(mode.rawValue, forKey: Self.searchModeKey)
    }

    func setSearchScope(_ scope: ScriptureSearchScope) {
        searchScope = scope
        defaults.set(scope.rawValue, forKey: Self.searchScopeKey)
    }

    func clearRecentSearches() {
        recentSearches = []
        defaults.removeObject(forKey: Self.recentSearchesKey)
    }

    func isBookmarked(reference: String) -> Bool {
        guard let selectedModuleID else { return false }
        return studyItems.contains {
            $0.kind == .bookmark
                && $0.moduleID == selectedModuleID
                && $0.reference == reference
        }
    }

    func note(reference: String) -> String? {
        guard let selectedModuleID else { return nil }
        return studyItems.first {
            $0.kind == .note
                && $0.moduleID == selectedModuleID
                && $0.reference == reference
        }?.text
    }

    func toggleBookmark(reference: String) async {
        guard let selectedModuleID, let studyStore else { return }
        do {
            try studyStore.toggleBookmark(
                moduleID: selectedModuleID,
                reference: reference
            )
            studyItems = try studyStore.fetchAll()
        } catch {
            presentedError = PresentedError(error)
        }
    }

    func saveNote(_ text: String, reference: String) async {
        guard let selectedModuleID, let studyStore else { return }
        do {
            try studyStore.saveNote(
                text,
                moduleID: selectedModuleID,
                reference: reference
            )
            studyItems = try studyStore.fetchAll()
        } catch {
            presentedError = PresentedError(error)
        }
    }

    var reference: String {
        guard let selectedBook else { return "" }
        return "\(selectedBook.name) \(selectedChapter)"
    }

    var selectedBook: BibleBook? {
        books.first { $0.id == selectedBookID }
    }

    var currentDestination: ReaderDestination? {
        guard let selectedModuleID, !reference.isEmpty else { return nil }
        return ReaderDestination(moduleID: selectedModuleID, reference: reference)
    }

    var readerTabSession: ReaderTabSession? {
        guard let selectedReaderTabID else { return nil }
        return ReaderTabSession(
            tabs: readerTabs,
            selectedTabID: selectedReaderTabID
        )
    }

    func readerTabTitle(_ tab: ReaderTab) -> String {
        let moduleTitle = modules.first {
            $0.id == tab.destination.moduleID
        }?.title ?? tab.destination.moduleID ?? "Bible"
        return "\(moduleTitle) · \(tab.destination.reference)"
    }

    func createReaderTab() {
        guard let currentDestination else { return }
        let tab = ReaderTab(destination: currentDestination)
        readerTabs.append(tab)
        selectedReaderTabID = tab.id
    }

    func selectReaderTab(_ tabID: ReaderTab.ID) async {
        guard tabID != selectedReaderTabID,
              let tab = readerTabs.first(where: { $0.id == tabID })
        else { return }
        selectedReaderTabID = tabID
        await open(destination: tab.destination)
    }

    func moveReaderTab(_ tabID: ReaderTab.ID, to targetID: ReaderTab.ID) {
        guard tabID != targetID,
              let sourceIndex = readerTabs.firstIndex(where: { $0.id == tabID }),
              let targetIndex = readerTabs.firstIndex(where: { $0.id == targetID })
        else { return }

        let tab = readerTabs.remove(at: sourceIndex)
        readerTabs.insert(tab, at: targetIndex)
    }

    func setReaderTabModule(_ tabID: ReaderTab.ID, moduleID: String) async {
        guard modules.contains(where: { $0.id == moduleID }),
              let index = readerTabs.firstIndex(where: { $0.id == tabID }),
              readerTabs[index].destination.moduleID != moduleID
        else { return }

        let currentReference = readerTabs[index].destination.reference
        let destination: ReaderDestination
        do {
            _ = try await service.chapter(currentReference, moduleID: moduleID)
            destination = ReaderDestination(
                moduleID: moduleID,
                reference: currentReference
            )
        } catch {
            do {
                guard let firstBook = try await service.books(moduleID: moduleID).first else {
                    throw error
                }
                destination = ReaderDestination(
                    moduleID: moduleID,
                    reference: "\(firstBook.name) 1"
                )
            } catch {
                presentedError = PresentedError(error)
                return
            }
        }

        readerTabs[index].destination = destination
        if selectedReaderTabID == tabID {
            await open(destination: destination)
        }
    }

    var canShowSelectedTabsSideBySide: Bool {
        readerTabs.count > 1 && selectedReaderTabID != nil
    }

    var sideBySidePair: SideBySideReaderPair? {
        guard sideBySidePanes.count == 2 else { return nil }
        return SideBySideReaderPair(
            leading: sideBySidePanes[0],
            trailing: sideBySidePanes[1]
        )
    }

    func neighboringReaderTab(for tabID: ReaderTab.ID) -> ReaderTab? {
        guard readerTabs.count > 1,
              let index = readerTabs.firstIndex(where: { $0.id == tabID })
        else { return nil }
        let neighborIndex = index < readerTabs.count - 1 ? index + 1 : index - 1
        return readerTabs[neighborIndex]
    }

    func showSelectedTabsSideBySide() async {
        guard let selectedReaderTabID else { return }
        await showTabsSideBySide(startingWith: selectedReaderTabID)
    }

    func showTabsSideBySide(startingWith tabID: ReaderTab.ID) async {
        guard let neighbor = neighboringReaderTab(for: tabID) else { return }
        let paneIDs = Set([tabID, neighbor.id])
        let tabs = readerTabs.filter { paneIDs.contains($0.id) }

        do {
            var panes: [SideBySideReaderPane] = []
            for tab in tabs {
                guard let moduleID = tab.destination.moduleID else { continue }
                let chapter = try await service.chapter(
                    tab.destination.reference,
                    moduleID: moduleID
                )
                panes.append(
                    SideBySideReaderPane(
                        id: tab.id,
                        destination: tab.destination,
                        chapter: chapter
                    )
                )
            }
            guard panes.count == 2 else { return }
            sideBySidePanes = panes
        } catch {
            presentedError = PresentedError(error)
        }
    }

    func splitSideBySideTabs() {
        sideBySidePanes = []
    }

    func closeReaderTab(_ tabID: ReaderTab.ID) async {
        guard readerTabs.count > 1,
              let index = readerTabs.firstIndex(where: { $0.id == tabID })
        else { return }

        let wasSelected = selectedReaderTabID == tabID
        readerTabs.remove(at: index)
        if sideBySidePanes.contains(where: { $0.id == tabID }) {
            splitSideBySideTabs()
        }
        guard wasSelected else { return }

        let replacement = readerTabs[min(index, readerTabs.count - 1)]
        selectedReaderTabID = replacement.id
        await open(destination: replacement.destination)
    }

    func restoreReaderTabs(_ session: ReaderTabSession) async {
        let availableTabs = session.tabs.filter { tab in
            guard let moduleID = tab.destination.moduleID else { return true }
            return modules.contains { $0.id == moduleID }
        }
        guard !availableTabs.isEmpty else { return }

        readerTabs = availableTabs
        let selectedTab = availableTabs.first {
            $0.id == session.selectedTabID
        } ?? availableTabs[0]
        selectedReaderTabID = selectedTab.id
        await open(destination: selectedTab.destination)
    }

    var canMoveToPreviousChapter: Bool {
        guard let selectedBookID,
              let index = books.firstIndex(where: { $0.id == selectedBookID })
        else { return false }
        return selectedChapter > 1 || index > books.startIndex
    }

    var canMoveToNextChapter: Bool {
        guard let selectedBook,
              let index = books.firstIndex(of: selectedBook)
        else { return false }
        return selectedChapter < selectedBook.chapterCount
            || index < books.index(before: books.endIndex)
    }

    func selectModule(_ moduleID: String) {
        guard moduleID != selectedModuleID else { return }
        Task {
            do {
                try await activateModule(moduleID, restoring: true)
            } catch {
                presentedError = PresentedError(error)
            }
        }
    }

    func select(bookID: String, chapter: Int) {
        guard
            let book = books.first(where: { $0.id == bookID }),
            (1...book.chapterCount).contains(chapter)
        else { return }

        selectedBookID = book.id
        selectedChapter = chapter
        persistLocation()
        rememberReadingLocation()
        loadChapter()
    }

    func open(reference newReference: String) {
        section = .read
        guard let location = location(from: newReference) else { return }
        select(bookID: location.book.id, chapter: location.chapter)
    }

    func open(destination: ReaderDestination) async {
        if let moduleID = destination.moduleID,
           modules.contains(where: { $0.id == moduleID }),
           moduleID != selectedModuleID {
            do {
                try await activateModule(moduleID, restoring: true)
            } catch {
                presentedError = PresentedError(error)
                return
            }
        }
        open(reference: destination.reference)
    }

    func continueReading(from destination: ReaderDestination) async {
        let requestedModuleID = destination.moduleID
        let isMissingRequestedModule = requestedModuleID.map { requested in
            !modules.contains { $0.id.caseInsensitiveCompare(requested) == .orderedSame }
        } ?? false

        await open(destination: destination)

        if isMissingRequestedModule, requestedModuleID != nil {
            if let selectedModule = modules.first(where: { $0.id == selectedModuleID }) {
                continuityNotice = ContinuityNotice(
                    destination: destination,
                    currentTranslationTitle: selectedModule.title
                )
            } else {
                section = .library
                continuityNotice = ContinuityNotice(
                    destination: destination,
                    currentTranslationTitle: nil
                )
            }
        }
    }

    func downloadContinuityModule() async {
        guard let notice = continuityNotice,
              let moduleID = notice.destination.moduleID,
              installingModuleID == nil
        else { return }
        continuityNotice = nil
        installingModuleID = moduleID
        installProgress = nil
        defer {
            installingModuleID = nil
            installProgress = nil
        }

        do {
            let source = moduleSources.first(where: { $0.id == selectedModuleSourceID }) ?? .crossWire
            let available = try await service.remoteBibles(from: source)
            guard available.contains(where: {
                $0.id.caseInsensitiveCompare(moduleID) == .orderedSame
            }) else {
                throw ContinuityError.moduleUnavailable(moduleID)
            }
            try await service.installRemote(moduleID: moduleID, from: source) { [weak self] progress in
                Task { @MainActor in self?.installProgress = progress }
            }
            modules = try await service.installedBibles()
            try await activateModule(moduleID, restoring: false)
            open(reference: notice.destination.reference)
        } catch {
            presentedError = PresentedError(error)
        }
    }

    func open(url: URL) async {
        guard let destination = ReaderDestination(url: url) else { return }
        await open(destination: destination)
    }

    func clearReadingHistory() {
        readingHistory = []
        defaults.removeObject(forKey: Self.readingHistoryKey)
    }

    func moveChapter(by offset: Int) {
        guard offset == -1 || offset == 1,
              let selectedBook,
              let index = books.firstIndex(of: selectedBook)
        else { return }

        if offset < 0, selectedChapter > 1 {
            select(bookID: selectedBook.id, chapter: selectedChapter - 1)
        } else if offset < 0, index > books.startIndex {
            let previous = books[books.index(before: index)]
            select(bookID: previous.id, chapter: previous.chapterCount)
        } else if offset > 0, selectedChapter < selectedBook.chapterCount {
            select(bookID: selectedBook.id, chapter: selectedChapter + 1)
        } else if offset > 0, index < books.index(before: books.endIndex) {
            let next = books[books.index(after: index)]
            select(bookID: next.id, chapter: 1)
        }
    }

    func compare(with moduleID: String) async {
        guard let selectedModuleID,
              moduleID != selectedModuleID,
              !reference.isEmpty
        else { return }
        comparisonTask?.cancel()
        comparisonModuleID = moduleID
        isLoadingComparison = true
        let task = Task {
            do {
                parallelVerses = try await service.parallelChapter(
                    reference,
                    moduleIDs: [selectedModuleID, moduleID]
                )
            } catch is CancellationError {
                return
            } catch {
                presentedError = PresentedError(error)
            }
            isLoadingComparison = false
        }
        comparisonTask = task
        await task.value
    }

    func endComparison() {
        comparisonTask?.cancel()
        comparisonTask = nil
        comparisonModuleID = nil
        parallelVerses = []
        isLoadingComparison = false
    }

    func search(_ query: String) {
        searchTask?.cancel()
        let normalized = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty, let selectedModuleID else {
            searchResults = []
            searchResultCount = 0
            isSearching = false
            searchProgress = nil
            return
        }

        isSearching = true
        searchProgress = 0
        rememberSearch(normalized)
        let mode = searchMode
        let scope = searchScope
        let generation = UUID()
        searchGeneration = generation
        searchTask = Task {
            do {
                let results = try await service.search(
                    normalized,
                    moduleID: selectedModuleID,
                    mode: mode,
                    scope: scope
                ) { [weak self] percentage in
                    Task { @MainActor in
                        guard self?.searchGeneration == generation else { return }
                        self?.searchProgress = percentage
                    }
                }
                guard searchGeneration == generation else { return }
                searchResultCount = results.count
                searchResults = Array(
                    results.prefix(Self.maximumVisibleSearchResults)
                )
            } catch is CancellationError {
                // A newer search owns the visible state.
            } catch {
                presentedError = PresentedError(error)
            }
            guard searchGeneration == generation else { return }
            isSearching = false
            searchProgress = nil
        }
    }

    private func rememberSearch(_ query: String) {
        recentSearches.removeAll {
            $0.caseInsensitiveCompare(query) == .orderedSame
        }
        recentSearches.insert(query, at: 0)
        recentSearches = Array(recentSearches.prefix(8))
        defaults.set(recentSearches, forKey: Self.recentSearchesKey)
    }

    func inspectCatalog(at directory: URL) async {
        let hasAccess = directory.startAccessingSecurityScopedResource()
        defer { if hasAccess { directory.stopAccessingSecurityScopedResource() } }
        do {
            catalog = try await service.catalog(at: directory)
        } catch {
            presentedError = PresentedError(error)
        }
    }

    func install(_ module: CatalogModule) async {
        guard let catalog else { return }
        let hasAccess = catalog.directory.startAccessingSecurityScopedResource()
        defer { if hasAccess { catalog.directory.stopAccessingSecurityScopedResource() } }
        isInstalling = true
        defer { isInstalling = false }
        do {
            try await service.install(moduleID: module.id, from: catalog)
            modules = try await service.installedBibles()
            keyedModules = try await service.installedKeyedModules()
            if module.isBible {
                try await activateModule(module.id, restoring: true)
            }
            self.catalog = nil
        } catch {
            presentedError = PresentedError(error)
        }
    }

    func refreshRemoteCatalog(sourceID: String? = nil) async {
        guard !isRefreshingRemoteCatalog else { return }
        if let sourceID, moduleSources.contains(where: { $0.id == sourceID }) {
            selectedModuleSourceID = sourceID
            defaults.set(sourceID, forKey: Self.selectedModuleSourceKey)
        }
        guard let source = moduleSources.first(where: { $0.id == selectedModuleSourceID }) else { return }
        isRefreshingRemoteCatalog = true
        defer { isRefreshingRemoteCatalog = false }
        do {
            remoteModules = try await service.remoteBibles(from: source).sorted {
                if $0.id == "ASV" { return true }
                if $1.id == "ASV" { return false }
                return $0.title.localizedStandardCompare($1.title) == .orderedAscending
            }
        } catch is CancellationError {
            return
        } catch {
            presentedError = PresentedError(error)
        }
    }

    func installRemote(_ module: CatalogModule) async {
        guard installingModuleID == nil else { return }
        installingModuleID = module.id
        installProgress = nil

        let task = Task {
            guard let source = moduleSources.first(where: { $0.id == module.sourceID }) else {
                throw ModuleSourceError.invalidEndpoint
            }
            try await service.installRemote(moduleID: module.id, from: source) { [weak self] progress in
                Task { @MainActor in self?.installProgress = progress }
            }
        }
        remoteInstallTask = task

        do {
            try await task.value
            modules = try await service.installedBibles()
            keyedModules = try await service.installedKeyedModules()
            if module.isBible {
                try await activateModule(module.id, restoring: true)
            }
        } catch is CancellationError {
            // Cancellation is an explicit user action, not an error to present.
        } catch {
            presentedError = PresentedError(error)
        }
        remoteInstallTask = nil
        installingModuleID = nil
        installProgress = nil
    }

    func cancelRemoteInstall() {
        remoteInstallTask?.cancel()
    }

    func approveModuleSource(_ source: ModuleSource) {
        guard !moduleSources.contains(where: { $0.id == source.id }) else { return }
        moduleSources.append(source)
        persistModuleSources()
    }

    func removeModuleSource(_ sourceID: String) {
        guard sourceID != ModuleSource.crossWire.id else { return }
        moduleSources.removeAll { $0.id == sourceID }
        if selectedModuleSourceID == sourceID {
            selectedModuleSourceID = ModuleSource.crossWire.id
            remoteModules = []
            defaults.set(selectedModuleSourceID, forKey: Self.selectedModuleSourceKey)
        }
        persistModuleSources()
    }

    private func persistModuleSources() {
        let saved = moduleSources.filter { $0.id != ModuleSource.crossWire.id }
        if let data = try? JSONEncoder().encode(saved) {
            defaults.set(data, forKey: Self.moduleSourcesKey)
        }
    }

    func removeModule(id moduleID: String) async {
        guard modules.contains(where: { $0.id == moduleID }) else { return }
        removingModuleID = moduleID
        defer { removingModuleID = nil }

        do {
            try await service.remove(moduleID: moduleID)
            defaults.removeObject(forKey: Self.bookKeyPrefix + moduleID)
            defaults.removeObject(forKey: Self.chapterKeyPrefix + moduleID)
            modules = try await service.installedBibles()

            guard selectedModuleID == moduleID else { return }
            chapterTask?.cancel()
            searchTask?.cancel()
            isLoading = false
            isSearching = false
            if let replacement = modules.first?.id {
                try await activateModule(replacement, restoring: true)
            } else {
                defaults.removeObject(forKey: Self.moduleKey)
                selectedModuleID = nil
                selectedBookID = nil
                selectedChapter = 1
                books = []
                chapter = nil
                readerTabs = []
                selectedReaderTabID = nil
                searchResults = []
                section = .library
            }
        } catch {
            presentedError = PresentedError(error)
        }
    }

    func removeKeyedModule(id moduleID: String) async {
        guard keyedModules.contains(where: { $0.id == moduleID }) else { return }
        removingModuleID = moduleID
        defer { removingModuleID = nil }
        do {
            try await service.remove(moduleID: moduleID)
            keyedModules = try await service.installedKeyedModules()
        } catch {
            presentedError = PresentedError(error)
        }
    }

    func keyedEntryKeys(moduleID: String) async throws -> [String] {
        try await service.keyedEntryKeys(moduleID: moduleID)
    }

    func keyedEntry(moduleID: String, key: String) async throws -> KeyedModuleEntry {
        try await service.keyedEntry(moduleID: moduleID, key: key)
    }

    func sendModuleToWatch(_ moduleID: String) async {
        guard sendingModuleID == nil, let companionSync else { return }
        sendingModuleID = moduleID
        defer { sendingModuleID = nil }
        do {
            try await companionSync.sendModule(moduleID: moduleID)
        } catch {
            presentedError = PresentedError(error)
        }
    }

    private func loadChapter() {
        chapterTask?.cancel()
        synchronizeSelectedReaderTab()
        guard let selectedModuleID, !reference.isEmpty else {
            chapter = nil
            return
        }
        isLoading = true
        chapterTask = Task {
            do {
                let loaded = try await service.chapter(reference, moduleID: selectedModuleID)
                chapter = loaded
                companionSync?.send(chapter: loaded)
            } catch is CancellationError {
                return
            } catch {
                presentedError = PresentedError(error)
            }
            isLoading = false
        }
    }

    private func synchronizeSelectedReaderTab() {
        guard let currentDestination else { return }

        if let selectedReaderTabID,
           let index = readerTabs.firstIndex(where: { $0.id == selectedReaderTabID }) {
            readerTabs[index].destination = currentDestination
        } else {
            let tab = ReaderTab(destination: currentDestination)
            readerTabs = [tab]
            selectedReaderTabID = tab.id
        }
    }

    private func activateModule(
        _ moduleID: String,
        restoring: Bool
    ) async throws {
        let availableBooks = try await service.books(moduleID: moduleID)
        selectedModuleID = moduleID
        defaults.set(moduleID, forKey: Self.moduleKey)
        books = availableBooks

        guard !availableBooks.isEmpty else {
            selectedBookID = nil
            chapter = nil
            return
        }

        let savedBookID = restoring
            ? defaults.string(forKey: Self.bookKeyPrefix + moduleID)
            : nil
        let savedChapter = restoring
            ? defaults.integer(forKey: Self.chapterKeyPrefix + moduleID)
            : 0
        let savedBook = availableBooks.first { $0.id == savedBookID }
        let fallback = availableBooks.first { $0.id == "John" }
            ?? availableBooks[0]
        let book = savedBook ?? fallback
        let chapter = savedBook.map {
            min(max(savedChapter, 1), $0.chapterCount)
        } ?? min(3, book.chapterCount)

        selectedBookID = book.id
        selectedChapter = chapter
        persistLocation()
        loadChapter()
    }

    private func persistLocation() {
        guard let selectedModuleID, let selectedBookID else { return }
        defaults.set(
            selectedBookID,
            forKey: Self.bookKeyPrefix + selectedModuleID
        )
        defaults.set(
            selectedChapter,
            forKey: Self.chapterKeyPrefix + selectedModuleID
        )
    }

    private func rememberReadingLocation() {
        guard let selectedModuleID, !reference.isEmpty else { return }
        readingHistory.removeAll {
            $0.moduleID == selectedModuleID && $0.reference == reference
        }
        readingHistory.insert(
            ReadingHistoryEntry(
                moduleID: selectedModuleID,
                reference: reference,
                visitedAt: .now
            ),
            at: 0
        )
        readingHistory = Array(readingHistory.prefix(50))
        if let data = try? JSONEncoder().encode(readingHistory) {
            defaults.set(data, forKey: Self.readingHistoryKey)
        }
    }

    private func location(
        from reference: String
    ) -> (book: BibleBook, chapter: Int)? {
        let chapterReference = Self.chapterReference(from: reference)
        let parts = chapterReference.split(whereSeparator: \.isWhitespace)

        guard let chapterPart = parts.last,
              let chapter = Int(chapterPart)
        else { return nil }

        let bookPart = parts.dropLast().joined(separator: " ")
        let book = books.first {
            [$0.id, $0.name, $0.abbreviation].contains {
                $0.caseInsensitiveCompare(bookPart) == .orderedSame
            }
        }

        guard let book, (1...book.chapterCount).contains(chapter) else {
            return nil
        }
        return (book, chapter)
    }

    static func chapterReference(from reference: String) -> String {
        reference.split(separator: ":", maxSplits: 1).first.map(String.init) ?? reference
    }
}

struct PresentedError: Identifiable {
    let id = UUID()
    let message: String

    init(_ error: any Error) {
        message = error.localizedDescription
    }
}

struct ContinuityNotice: Identifiable {
    let id = UUID()
    let destination: ReaderDestination
    let currentTranslationTitle: String?

    var message: String {
        let moduleID = destination.moduleID ?? "That Bible"
        if let currentTranslationTitle {
            return "\(moduleID) isn’t installed on this device. Keep \(destination.reference) open in \(currentTranslationTitle), or download \(moduleID) and continue there."
        }
        return "\(moduleID) isn’t installed on this device. Download it to continue at \(destination.reference)."
    }
}

enum ContinuityError: LocalizedError {
    case moduleUnavailable(String)

    var errorDescription: String? {
        switch self {
        case .moduleUnavailable(let moduleID):
            String(localized: "\(moduleID) is not currently available from CrossWire.")
        }
    }
}

private actor UnavailableScriptureService: ScriptureServing {
    let error: any Error

    init(error: any Error) {
        self.error = error
    }

    func installedBibles() async throws -> [BibleModule] { throw error }
    func installedKeyedModules() async throws -> [KeyedModule] { throw error }
    func keyedEntryKeys(moduleID: String) async throws -> [String] { throw error }
    func keyedEntry(moduleID: String, key: String) async throws -> KeyedModuleEntry { throw error }
    func books(moduleID: String) async throws -> [BibleBook] { throw error }
    func chapter(_ reference: String, moduleID: String) async throws -> BibleChapter { throw error }
    func parallelChapter(
        _ reference: String,
        moduleIDs: [String]
    ) async throws -> [ParallelVerse] { throw error }
    func search(
        _ query: String,
        moduleID: String,
        mode: ScriptureSearchMode,
        scope: ScriptureSearchScope,
        progress: @escaping @Sendable (Int) -> Void
    ) async throws -> [BibleSearchResult] { throw error }
    func catalog(at directory: URL) async throws -> LocalCatalog { throw error }
    func install(moduleID: String, from catalog: LocalCatalog) async throws { throw error }
    func remoteBibles(from source: ModuleSource) async throws -> [CatalogModule] { throw error }
    func installRemote(
        moduleID: String,
        from source: ModuleSource,
        progress: @escaping @Sendable (ModuleTransferProgress) -> Void
    ) async throws { throw error }
    func remove(moduleID: String) async throws { throw error }
}
