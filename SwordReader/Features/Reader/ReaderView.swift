import SwiftUI
#if os(macOS)
import AppKit
#else
import UIKit
#endif

struct ReaderView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.openWindow) private var openWindow
    @Environment(\.supportsMultipleWindows) private var supportsMultipleWindows
    @State private var isChoosingBook = false
    @State private var isChoosingChapter = false
    @State private var isShowingComparison = false
    @State private var sideBySideRatio = 0.5
    @State private var sideBySideDragStartRatio: Double?

    var body: some View {
        Group {
            if model.modules.isEmpty {
                ContentUnavailableView {
                    Label("No Bibles Installed", systemImage: "book.closed")
                } description: {
                    Text("Get a Bible from the Library to begin reading.")
                } actions: {
                    Button("Open Library") { model.section = .library }
                }
            } else if model.isLoading && model.chapter == nil {
                ProgressView("Loading chapter…")
            } else if let pair = model.sideBySidePair {
                sideBySideContent(pair)
            } else if let chapter = model.chapter {
                chapterContent(chapter)
            } else {
                ContentUnavailableView(
                    "Choose a Chapter",
                    systemImage: "text.book.closed"
                )
            }
        }
        .safeAreaInset(edge: .top, spacing: 0) {
            if !model.readerTabs.isEmpty {
                ReaderTabBar()
                    .environment(model)
            }
        }
        .navigationTitle(model.reference.isEmpty ? "Read" : model.reference)
        .toolbarTitleDisplayMode(.inline)
        .toolbar { readerToolbar }
        #if os(macOS)
        .sheet(isPresented: $isChoosingBook) {
            BookNavigationView()
                .environment(model)
                .frame(minWidth: 420, minHeight: 560)
        }
        .sheet(isPresented: $isChoosingChapter) {
            chapterNavigation
                .frame(minWidth: 420, minHeight: 560)
        }
        #else
        .popover(isPresented: $isChoosingBook) {
            BookNavigationView()
                .environment(model)
                .frame(minWidth: 340, idealWidth: 420, minHeight: 480)
                .presentationCompactAdaptation(.sheet)
        }
        .popover(isPresented: $isChoosingChapter) {
            chapterNavigation
                .frame(minWidth: 340, idealWidth: 420, minHeight: 480)
                .presentationCompactAdaptation(.sheet)
        }
        #endif
        .sheet(isPresented: $isShowingComparison, onDismiss: { model.endComparison() }) {
            TranslationComparisonView().environment(model)
        }
    }

    private func chapterContent(_ chapter: BibleChapter) -> some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: model.readerSpacing.verseSpacing) {
                ForEach(chapter.verses) { verse in
                    VerseView(verse: verse)
                }
            }
            .frame(maxWidth: 720, alignment: .leading)
            .padding(.horizontal)
            .padding(.vertical, 24)
        }
        .contentMargins(.bottom, 56, for: .scrollContent)
        .gesture(
            DragGesture(minimumDistance: 60).onEnded { value in
                guard abs(value.translation.width)
                    > abs(value.translation.height) * 1.5
                else { return }

                model.moveChapter(
                    by: value.translation.width < 0 ? 1 : -1
                )
            }
        )
    }

    @ToolbarContentBuilder
    private var readerToolbar: some ToolbarContent {
        #if os(macOS)
        ToolbarItem(placement: .principal) {
            HStack(spacing: 12) {
                previousChapterButton
                referenceChooser
                nextChapterButton
            }
        }
        #else
        ToolbarItem(placement: .navigation) {
            previousChapterButton
        }

        ToolbarItem(placement: .principal) {
            referenceChooser
        }

        ToolbarItem(placement: .primaryAction) {
            nextChapterButton
        }
        #endif

        ToolbarItem(placement: .secondaryAction) {
            ReaderAppearanceMenu()
        }

        if model.sideBySidePair != nil {
            ToolbarItem(placement: .secondaryAction) {
                Button("Split Back into Tabs", systemImage: "rectangle.split.1x2") {
                    model.splitSideBySideTabs()
                }
                .help("Split Back into Tabs")
            }
        } else if model.canShowSelectedTabsSideBySide {
            ToolbarItem(placement: .secondaryAction) {
                Button("Show Adjacent Tab Side by Side", systemImage: "rectangle.split.2x1") {
                    Task { await model.showSelectedTabsSideBySide() }
                }
                .help("Show Adjacent Tab Side by Side")
            }
        }

        if model.modules.count > 1 {
            ToolbarItem(placement: .secondaryAction) {
                Menu("Compare Translation", systemImage: "rectangle.split.2x1") {
                    ForEach(model.modules.filter { $0.id != model.selectedModuleID }) { module in
                        Button(module.title) {
                            isShowingComparison = true
                            Task { await model.compare(with: module.id) }
                        }
                    }
                }
                .help("Compare Translations")
            }
        }

        if !model.readingHistory.isEmpty {
            ToolbarItem(placement: .secondaryAction) {
                Menu("Reading History", systemImage: "clock.arrow.circlepath") {
                    ForEach(model.readingHistory.prefix(10)) { entry in
                        Button(entry.reference) {
                            Task {
                                await model.open(
                                    destination: ReaderDestination(
                                        moduleID: entry.moduleID,
                                        reference: entry.reference
                                    )
                                )
                            }
                        }
                    }
                    Divider()
                    Button("Clear History", role: .destructive) {
                        model.clearReadingHistory()
                    }
                }
                .help("Reading History")
            }
        }

        if supportsMultipleWindows, let destination = model.currentDestination {
            ToolbarItem(placement: .secondaryAction) {
                Button("Open in New Window", systemImage: "plus.rectangle.on.rectangle") {
                    openWindow(value: destination)
                }
                .help("Open in New Window")
            }
        }

        ToolbarItem(placement: .secondaryAction) {
            Menu {
                ForEach(model.modules) { module in
                    Button {
                        model.selectModule(module.id)
                    } label: {
                        if module.id == model.selectedModuleID {
                            Label(module.title, systemImage: "checkmark")
                        } else {
                            Text(module.title)
                        }
                    }
                }
            } label: {
                Label(
                    model.selectedModuleID ?? "Translation",
                    systemImage: "character.book.closed"
                )
            }
            .accessibilityLabel("Translation")
            .help("Translation: \(model.selectedModuleID ?? "None Selected")")
        }
    }

    private var chapterNavigation: some View {
        ChapterNavigationView().environment(model)
    }

    private func sideBySideContent(_ pair: SideBySideReaderPair) -> some View {
        GeometryReader { proxy in
            let isWide = proxy.size.width >= 700
            Group {
                if isWide {
                    HStack(spacing: 0) {
                        sideBySidePane(pair.leading)
                            .frame(width: max(0, (proxy.size.width - 12) * sideBySideRatio))
                        resizablePaneDivider(totalWidth: proxy.size.width)
                        sideBySidePane(pair.trailing)
                    }
                } else {
                    VStack(spacing: 0) {
                        sideBySidePane(pair.leading)
                        Divider()
                        sideBySidePane(pair.trailing)
                    }
                }
            }
        }
    }

    private func resizablePaneDivider(totalWidth: CGFloat) -> some View {
        Rectangle()
            .fill(Color.secondary.opacity(0.18))
            .frame(width: 12)
            .overlay {
                Capsule()
                    .fill(Color.secondary)
                    .frame(width: 3, height: 36)
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 1)
                    .onChanged { value in
                        let startingRatio = sideBySideDragStartRatio ?? sideBySideRatio
                        sideBySideDragStartRatio = startingRatio
                        sideBySideRatio = ReaderPaneLayout.ratio(
                            startingAt: startingRatio,
                            translation: value.translation.width,
                            totalWidth: totalWidth
                        )
                    }
                    .onEnded { _ in sideBySideDragStartRatio = nil }
            )
            .accessibilityLabel("Resize Reading Panes")
            .accessibilityHint("Drag left or right to resize both reading panes")
    }

    private func sideBySidePane(_ pane: SideBySideReaderPane) -> some View {
        VStack(spacing: 0) {
            SideBySidePaneHeader(pane: pane)
                .environment(model)

            ScrollView {
                LazyVStack(alignment: .leading, spacing: model.readerSpacing.verseSpacing) {
                    ForEach(pane.chapter.verses) { verse in
                        HStack(alignment: .firstTextBaseline, spacing: 6) {
                            if model.showsVerseNumbers {
                                Text(verse.number)
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(.secondary)
                            }
                            Text(displayedContent(for: verse))
                                .font(.system(size: model.readerFontSize, design: model.readerFont.design))
                                .lineSpacing(model.readerSpacing.lineSpacing)
                                .textSelection(.enabled)
                        }
                    }
                }
                .frame(maxWidth: 720, alignment: .leading)
                .padding()
            }
        }
    }

    private func displayedContent(for verse: BibleVerse) -> AttributedString {
        guard !model.showsRedLetterText else { return verse.content }
        var content = verse.content
        content.foregroundColor = nil
        return content
    }

    private var previousChapterButton: some View {
        Button("Previous Chapter", systemImage: "chevron.left") {
            model.moveChapter(by: -1)
        }
        .labelStyle(.iconOnly)
        .disabled(!model.canMoveToPreviousChapter)
        .keyboardShortcut(.leftArrow, modifiers: [.command])
        .help("Previous Chapter")
    }

    private var referenceChooser: some View {
        HStack(spacing: 2) {
            Button {
                isChoosingBook = true
            } label: {
                Text(model.selectedBook?.name ?? "Choose Book")
                    .fontWeight(.semibold)
            }
            .accessibilityHint("Shows Bible books")

            Button {
                isChoosingChapter = true
            } label: {
                HStack(spacing: 4) {
                    Text(model.selectedBook == nil ? "Chapter" : "\(model.selectedChapter)")
                        .fontWeight(.semibold)
                        .monospacedDigit()
                    Image(systemName: "chevron.down")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
            }
            .disabled(model.selectedBook == nil)
            .accessibilityLabel("Choose Chapter")
        }
        .buttonStyle(.plain)
    }

    private var nextChapterButton: some View {
        Button("Next Chapter", systemImage: "chevron.right") {
            model.moveChapter(by: 1)
        }
        .labelStyle(.iconOnly)
        .disabled(!model.canMoveToNextChapter)
        .keyboardShortcut(.rightArrow, modifiers: [.command])
        .help("Next Chapter")
    }
}

private struct SideBySidePaneHeader: View {
    @Environment(AppModel.self) private var model
    let pane: SideBySideReaderPane
    @State private var books: [BibleBook] = []

    private var moduleTitle: String {
        model.modules.first { $0.id == pane.destination.moduleID }?.title
            ?? pane.destination.moduleID
            ?? "Bible"
    }

    var body: some View {
        HStack(spacing: 12) {
            Menu {
                ForEach(model.modules) { module in
                    Button {
                        Task {
                            await model.setReaderTabModule(pane.id, moduleID: module.id)
                        }
                    } label: {
                        if module.id == pane.destination.moduleID {
                            Label(module.title, systemImage: "checkmark")
                        } else {
                            Text(module.title)
                        }
                    }
                }
            } label: {
                HStack(spacing: 4) {
                    Text(moduleTitle)
                    Image(systemName: "chevron.down")
                        .font(.caption.weight(.semibold))
                }
                .font(.headline)
            }
            .menuIndicator(.hidden)
            .help("Change Module")

            Menu {
                ForEach(books) { book in
                    Menu(book.name) {
                        ForEach(1...book.chapterCount, id: \.self) { chapter in
                            Button("Chapter \(chapter)") {
                                Task {
                                    await model.setReaderTabReference(
                                        pane.id,
                                        book: book,
                                        chapter: chapter
                                    )
                                }
                            }
                        }
                    }
                }
            } label: {
                HStack(spacing: 4) {
                    Text(pane.destination.reference)
                    Image(systemName: "chevron.down")
                        .font(.caption.weight(.semibold))
                }
                .font(.headline)
            }
            .menuIndicator(.hidden)
            .help("Change Book or Chapter")

            Spacer(minLength: 0)
        }
        .lineLimit(1)
        .padding(.horizontal)
        .padding(.vertical, 10)
        .background(.bar)
        .task(id: pane.destination.moduleID) {
            guard let moduleID = pane.destination.moduleID else {
                books = []
                return
            }
            books = await model.readerBooks(moduleID: moduleID)
        }
    }
}

enum ReaderPaneLayout {
    static func ratio(
        startingAt ratio: Double,
        translation: CGFloat,
        totalWidth: CGFloat
    ) -> Double {
        guard totalWidth > 0 else { return ratio }
        return min(max(ratio + translation / totalWidth, 0.25), 0.75)
    }
}

private struct ReaderTabBar: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 6) {
                ForEach(model.readerTabs) { tab in
                    HStack(spacing: 4) {
                        Button(model.readerTabTitle(tab)) {
                            Task { await model.selectReaderTab(tab.id) }
                        }
                        .lineLimit(1)

                        Button("Close Tab", systemImage: "xmark") {
                            Task { await model.closeReaderTab(tab.id) }
                        }
                        .labelStyle(.iconOnly)
                        .disabled(model.readerTabs.count == 1)
                        .help("Close Tab")
                    }
                    .buttonStyle(.plain)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 7)
                    .background(
                        tab.id == model.selectedReaderTabID
                            ? Color.accentColor.opacity(0.16)
                            : Color.secondary.opacity(0.08),
                        in: .rect(cornerRadius: 8)
                    )
                    .draggable(tab.id.uuidString)
                    .dropDestination(for: String.self) { identifiers, _ in
                        guard let draggedID = identifiers.compactMap({
                            UUID(uuidString: $0)
                        }).first else { return false }
                        model.moveReaderTab(draggedID, to: tab.id)
                        return true
                    }
                    .contextMenu {
                        Menu("Translation", systemImage: "character.book.closed") {
                            ForEach(model.modules) { module in
                                Button {
                                    Task {
                                        await model.setReaderTabModule(
                                            tab.id,
                                            moduleID: module.id
                                        )
                                    }
                                } label: {
                                    if tab.destination.moduleID == module.id {
                                        Label(module.title, systemImage: "checkmark")
                                    } else {
                                        Text(module.title)
                                    }
                                }
                            }
                        }
                        if let neighbor = model.neighboringReaderTab(for: tab.id) {
                            Divider()
                            Button(
                                "Show Side by Side with \(model.readerTabTitle(neighbor))",
                                systemImage: "rectangle.split.2x1"
                            ) {
                                Task {
                                    await model.showTabsSideBySide(startingWith: tab.id)
                                }
                            }
                        }
                    }
                }

                Button("New Tab", systemImage: "plus") {
                    model.createReaderTab()
                }
                .labelStyle(.iconOnly)
                .buttonStyle(.borderless)
                .help("New Reading Tab")

                if model.sideBySidePair != nil {
                    Button("Split Back into Tabs", systemImage: "rectangle.split.1x2") {
                        model.splitSideBySideTabs()
                    }
                    .labelStyle(.iconOnly)
                    .buttonStyle(.borderless)
                    .help("Split Back into Tabs")
                } else if let selectedTabID = model.selectedReaderTabID,
                          let neighbor = model.neighboringReaderTab(for: selectedTabID) {
                    Button(
                        "Show Side by Side with \(model.readerTabTitle(neighbor))",
                        systemImage: "rectangle.split.2x1"
                    ) {
                        Task { await model.showSelectedTabsSideBySide() }
                    }
                    .labelStyle(.iconOnly)
                    .buttonStyle(.borderless)
                    .help("Show Side by Side with \(model.readerTabTitle(neighbor))")
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
        }
        .background(.bar)
        .accessibilityLabel("Reading Tabs")
    }
}

private struct TranslationComparisonView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    private var moduleIDs: [String] {
        [model.selectedModuleID, model.comparisonModuleID].compactMap { $0 }
    }

    var body: some View {
        NavigationStack {
            Group {
                if model.isLoadingComparison {
                    ProgressView("Aligning translations…")
                } else if model.parallelVerses.isEmpty {
                    ContentUnavailableView(
                        "No Aligned Verses",
                        systemImage: "rectangle.split.2x1"
                    )
                } else {
                    List(model.parallelVerses) { row in
                        VStack(alignment: .leading, spacing: 12) {
                            Text(row.reference)
                                .font(.headline)
                                .accessibilityAddTraits(.isHeader)

                            if horizontalSizeClass == .compact {
                                VStack(alignment: .leading, spacing: 12) {
                                    ForEach(row.texts) { comparisonText($0) }
                                }
                            } else {
                                HStack(alignment: .top, spacing: 20) {
                                    ForEach(row.texts) { comparisonText($0) }
                                }
                            }

                            if !row.lexicalLinks.isEmpty {
                                DisclosureGroup("Original-Language Links") {
                                    ForEach(row.lexicalLinks) { link in
                                        VStack(alignment: .leading, spacing: 3) {
                                            Text(link.strongsNumber).font(.caption.bold())
                                            Text(link.words.joined(separator: " · "))
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                        }
                                    }
                                }
                            }
                        }
                        .padding(.vertical, 6)
                    }
                }
            }
            .navigationTitle("Compare \(model.reference)")
            .toolbarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .frame(idealWidth: 760, idealHeight: 620)
    }

    private func comparisonText(_ value: ParallelVerseText) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(moduleTitle(value.moduleID))
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            Text(value.text ?? "Verse unavailable")
                .font(.body)
                .foregroundStyle(value.text == nil ? .secondary : .primary)
                .textSelection(.enabled)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func moduleTitle(_ id: String) -> String {
        model.modules.first { $0.id == id }?.title ?? id
    }
}

private struct VerseView: View {
    @Environment(AppModel.self) private var model
    let verse: BibleVerse
    @State private var isShowingAnnotations = false
    @State private var isEditingNote = false
    @State private var selectedTextForNote: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(verse.headings) { heading in
                Text(heading.text)
                    .font(.system(.title3, design: model.readerFont.design, weight: .semibold))
                    .accessibilityAddTraits(.isHeader)
                    .padding(.top, 8)
            }

            verseText
                .font(.system(size: model.readerFontSize, design: model.readerFont.design))
                .lineSpacing(model.readerSpacing.lineSpacing)
                .textSelection(.enabled)

            if verse.annotationCount > 0 {
                Button {
                    isShowingAnnotations = true
                } label: {
                    Label(
                        "\(verse.annotationCount) \(verse.annotationCount == 1 ? "note" : "notes")",
                        systemImage: "text.bubble"
                    )
                }
                .font(.caption)
                .buttonStyle(.plain)
                .foregroundStyle(.tint)
                .accessibilityHint("Shows notes and Scripture references for \(verse.reference)")
            }
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 4)
        .contentShape(Rectangle())
        .contextMenu {
            if selectedText() != nil {
                Button("Copy", systemImage: "doc.on.doc") {
                    guard let selectedText = selectedText() else { return }
                    copyToPasteboard(selectedText)
                }
                Button("Highlight", systemImage: "highlighter") {
                    guard let selectedText = selectedText() else { return }
                    Task {
                        await model.saveHighlight(selectedText, reference: verse.reference)
                    }
                }
                Button("Add Note…", systemImage: "square.and.pencil") {
                    guard let selectedText = selectedText() else { return }
                    selectedTextForNote = selectedText
                    isEditingNote = true
                }
                Divider()
                Button(
                    model.isBookmarked(reference: verse.reference)
                        ? "Remove Bookmark"
                        : "Bookmark Verse",
                    systemImage: model.isBookmarked(reference: verse.reference)
                        ? "bookmark.slash"
                        : "bookmark"
                ) {
                    Task { await model.toggleBookmark(reference: verse.reference) }
                }
            }
        }
        .accessibilityAction(named: "Highlight Verse") {
            Task {
                await model.saveHighlight(
                    String(verse.content.characters),
                    reference: verse.reference
                )
            }
        }
        .accessibilityAction(named: "Add or Edit Note") {
            isEditingNote = true
        }
        .sheet(isPresented: $isShowingAnnotations) {
            VerseAnnotationsView(verse: verse)
                .environment(model)
        }
        .sheet(isPresented: $isEditingNote) {
            StudyNoteEditor(
                reference: verse.reference,
                initialText: model.note(reference: verse.reference)
                    ?? selectedTextForNote.map { "“\($0)”\n\n" }
                    ?? ""
            )
            .environment(model)
        }
    }

    private var verseText: Text {
        if model.showsVerseNumbers {
            Text(verse.number + " ")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            + Text(displayedContent)
        } else {
            Text(displayedContent)
        }
    }

    private var displayedContent: AttributedString {
        guard !model.showsRedLetterText else { return verse.content }
        var content = verse.content
        content.foregroundColor = nil
        return content
    }

    private func selectedText() -> String? {
        #if os(macOS)
        guard let textView = NSApp.keyWindow?.firstResponder as? NSTextView,
              textView.selectedRange().length > 0
        else { return nil }
        return (textView.string as NSString).substring(with: textView.selectedRange())
        #else
        UIResponder.captureCurrentFirstResponder()
        guard let textView = FirstResponderProbe.current as? UITextView,
              let range = textView.selectedTextRange,
              !range.isEmpty
        else { return nil }
        return textView.text(in: range)
        #endif
    }

    private func copyToPasteboard(_ text: String) {
        #if os(macOS)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        #else
        UIPasteboard.general.string = text
        #endif
    }
}

#if !os(macOS)
@MainActor
private enum FirstResponderProbe {
    static weak var current: UIResponder?
}

@MainActor
private extension UIResponder {
    @objc func captureAsCurrentFirstResponder(_ sender: Any?) {
        FirstResponderProbe.current = self
    }

    static func captureCurrentFirstResponder() {
        FirstResponderProbe.current = nil
        UIApplication.shared.sendAction(
            #selector(captureAsCurrentFirstResponder(_:)),
            to: nil,
            from: nil,
            for: nil
        )
    }
}
#endif

private struct StudyNoteEditor: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let reference: String
    @State private var text: String

    init(reference: String, initialText: String) {
        self.reference = reference
        _text = State(initialValue: initialText)
    }

    var body: some View {
        NavigationStack {
            TextEditor(text: $text)
                .font(.body)
                .padding()
                .navigationTitle(reference)
                .toolbarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") { dismiss() }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Save") {
                            Task {
                                await model.saveNote(text, reference: reference)
                                dismiss()
                            }
                        }
                    }
                }
        }
        .frame(minWidth: 360, minHeight: 280)
    }
}

private struct VerseAnnotationsView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let verse: BibleVerse

    var body: some View {
        NavigationStack {
            List {
                if !verse.footnotes.isEmpty {
                    Section("Notes") {
                        ForEach(verse.footnotes) { note in
                            VStack(alignment: .leading, spacing: 4) {
                                Text(note.text)
                                if let type = note.type, !type.isEmpty {
                                    Text(type)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            .textSelection(.enabled)
                        }
                    }
                }

                if !verse.crossReferences.isEmpty {
                    Section("Cross-References") {
                        ForEach(verse.crossReferences) { group in
                            ForEach(group.references, id: \.self) { reference in
                                Button {
                                    dismiss()
                                    model.open(reference: reference)
                                } label: {
                                    Label(reference, systemImage: "arrow.right.circle")
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle(verse.reference)
            .toolbarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}

private struct ReaderAppearanceMenu: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        Menu("Reading Appearance", systemImage: "textformat.size") {
            Picker("Font", selection: fontBinding) {
                ForEach(ReaderFont.allCases) { font in
                    Text(font.title).tag(font)
                }
            }

            Picker("Text Size", selection: sizeBinding) {
                ForEach(ReaderTextSize.allCases) { size in
                    Text(size.title).tag(size)
                }
            }

            Picker("Spacing", selection: spacingBinding) {
                ForEach(ReaderSpacing.allCases) { spacing in
                    Text(spacing.title).tag(spacing)
                }
            }

            Picker("App Appearance", selection: appearanceBinding) {
                ForEach(AppAppearance.allCases) { appearance in
                    Text(appearance.title).tag(appearance)
                }
            }

            Toggle("Verse Numbers", isOn: verseNumberBinding)
        }
        .accessibilityHint("Changes font, text size, spacing, appearance, and verse numbers")
        .help("Reading Appearance")
    }

    private var fontBinding: Binding<ReaderFont> {
        Binding(
            get: { model.readerFont },
            set: { model.setReaderFont($0) }
        )
    }

    private var sizeBinding: Binding<ReaderTextSize> {
        Binding(
            get: { model.readerTextSize },
            set: { model.setReaderTextSize($0) }
        )
    }

    private var spacingBinding: Binding<ReaderSpacing> {
        Binding(
            get: { model.readerSpacing },
            set: { model.setReaderSpacing($0) }
        )
    }

    private var verseNumberBinding: Binding<Bool> {
        Binding(
            get: { model.showsVerseNumbers },
            set: { model.setShowsVerseNumbers($0) }
        )
    }

    private var appearanceBinding: Binding<AppAppearance> {
        Binding(
            get: { model.appAppearance },
            set: { model.setAppAppearance($0) }
        )
    }
}

extension ReaderFont {
    var design: Font.Design {
        switch self {
        case .system: .default
        case .serif: .serif
        case .rounded: .rounded
        }
    }
}

private extension ReaderTextSize {
    var textStyle: Font.TextStyle {
        switch self {
        case .small: .callout
        case .standard: .body
        case .large: .title3
        case .extraLarge: .title2
        }
    }
}

private extension ReaderSpacing {
    var verseSpacing: CGFloat {
        switch self {
        case .compact: 12
        case .comfortable: 18
        case .relaxed: 26
        }
    }

    var lineSpacing: CGFloat {
        switch self {
        case .compact: 2
        case .comfortable: 6
        case .relaxed: 10
        }
    }
}

private struct BookNavigationView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""

    private var matchingBooks: [BibleBook] {
        guard !query.isEmpty else { return model.books }
        return model.books.filter {
            $0.name.localizedCaseInsensitiveContains(query)
                || $0.abbreviation.localizedCaseInsensitiveContains(query)
        }
    }

    var body: some View {
        NavigationStack {
            List {
                testamentSection("Old Testament", testament: .old)
                testamentSection("New Testament", testament: .new)
            }
            .navigationTitle("Choose a Book")
            .toolbarTitleDisplayMode(.inline)
            .searchable(text: $query, prompt: "Book")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
        }
    }

    @ViewBuilder
    private func testamentSection(
        _ title: String,
        testament: BibleBook.Testament
    ) -> some View {
        let books = matchingBooks.filter { $0.testament == testament }
        if !books.isEmpty {
            Section(title) {
                ForEach(books) { book in
                    Button {
                        model.select(bookID: book.id, chapter: 1)
                        dismiss()
                    } label: {
                        HStack {
                            if book.id == model.selectedBookID {
                                Image(systemName: "checkmark")
                                    .foregroundStyle(.tint)
                                    .frame(width: 18)
                                    .accessibilityLabel("Current book")
                            } else {
                                Color.clear.frame(width: 18, height: 1)
                            }
                            Text(book.name)
                            Spacer()
                            Text("\(book.chapterCount)")
                                .foregroundStyle(.secondary)
                                .accessibilityLabel(
                                    "\(book.chapterCount) chapters"
                                )
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
}

private struct ChapterNavigationView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            if let book = model.selectedBook {
                ChapterGridView(book: book) { dismiss() }
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Close") { dismiss() }
                        }
                    }
            } else {
                ContentUnavailableView("Choose a Book First", systemImage: "book.closed")
            }
        }
    }
}

private struct ChapterGridView: View {
    @Environment(AppModel.self) private var model
    let book: BibleBook
    let didSelect: () -> Void

    private let columns = [
        GridItem(.adaptive(minimum: 48, maximum: 64), spacing: 12)
    ]

    var body: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: 12) {
                ForEach(1...book.chapterCount, id: \.self) { chapter in
                    Button {
                        model.select(bookID: book.id, chapter: chapter)
                        didSelect()
                    } label: {
                        ZStack {
                            Text("\(chapter)")
                                .font(.body.monospacedDigit())
                            if isSelected(chapter) {
                                Image(systemName: "checkmark")
                                    .font(.caption2.weight(.bold))
                                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                                    .padding(6)
                                    .accessibilityHidden(true)
                            }
                        }
                            .frame(maxWidth: .infinity, minHeight: 44)
                            .background(
                                isSelected(chapter)
                                    ? Color.accentColor
                                    : Color.secondary.opacity(0.12),
                                in: .rect(cornerRadius: 10)
                            )
                            .foregroundStyle(
                                isSelected(chapter) ? .white : .primary
                            )
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(
                        "\(book.name) chapter \(chapter)"
                    )
                    .accessibilityAddTraits(
                        isSelected(chapter) ? .isSelected : []
                    )
                }
            }
            .padding()
        }
        .navigationTitle(book.name)
        .toolbarTitleDisplayMode(.inline)
    }

    private func isSelected(_ chapter: Int) -> Bool {
        model.selectedBookID == book.id
            && model.selectedChapter == chapter
    }
}
