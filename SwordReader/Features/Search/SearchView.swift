import SwiftUI

struct SearchView: View {
    @Environment(AppModel.self) private var model
    @State private var query = ""

    var body: some View {
        Group {
            if model.modules.isEmpty {
                ContentUnavailableView("No Bible to Search", systemImage: "magnifyingglass", description: Text("Install a Bible from the Library first."))
            } else if query.isEmpty {
                searchHome
            } else if model.isSearching && model.searchResults.isEmpty {
                ProgressView("Searching…")
            } else if model.searchResults.isEmpty {
                ContentUnavailableView.search(text: query)
            } else {
                List {
                    Section {
                        ForEach(model.searchResults) { result in
                            Button {
                                Task { await model.openSearchResult(result) }
                            } label: {
                                VStack(alignment: .leading, spacing: 5) {
                                    Text(result.reference).font(.headline)
                                    Text(highlighted(result.text))
                                        .font(.body)
                                        .foregroundStyle(.primary)
                                        .lineLimit(3)
                                }
                                .padding(.vertical, 4)
                            }
                            .buttonStyle(.plain)
                        }
                    } footer: {
                        if model.searchResultsWereLimited {
                            Text("Showing the first \(model.searchResults.count) of \(model.searchResultCount) matches. Narrow the search or scope to see different results.")
                        }
                    }
                }
            }
        }
        .navigationTitle("Search")
        .searchable(text: $query, prompt: "Word or phrase")
        .onSubmit(of: .search) { model.search(query) }
        .onChange(of: query) { _, value in
            if value.isEmpty { model.search("") }
        }
        .toolbar {
            ToolbarItem(placement: .secondaryAction) {
                Menu("Search Options", systemImage: "line.3.horizontal.decrease.circle") {
                    Picker("Match", selection: modeBinding) {
                        ForEach(ScriptureSearchMode.allCases) { mode in
                            Text(mode.title).tag(mode)
                        }
                    }
                    Picker("Scope", selection: scopeBinding) {
                        ForEach(ScriptureSearchScope.allCases) { scope in
                            Text(scope.title).tag(scope)
                        }
                    }
                }
                .help("Search Options")
            }
        }
        .safeAreaInset(edge: .bottom) {
            if model.isSearching {
                VStack(spacing: 4) {
                    if let progress = model.searchProgress {
                        ProgressView(value: Double(progress), total: 100)
                    } else {
                        ProgressView()
                    }
                    Text("Searching \(model.searchScope.title)…")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal)
                .padding(.vertical, 8)
                .background(.bar)
            }
        }
    }

    @ViewBuilder
    private var searchHome: some View {
        if model.recentSearches.isEmpty {
            ContentUnavailableView(
                "Search Scripture",
                systemImage: "text.magnifyingglass",
                description: Text("Search the selected translation by phrase, words, pattern, Strong’s number, or morphology.")
            )
        } else {
            List {
                Section {
                    ForEach(model.recentSearches, id: \.self) { recent in
                        Button {
                            query = recent
                            model.search(recent)
                        } label: {
                            Label(recent, systemImage: "clock.arrow.circlepath")
                        }
                    }
                } header: {
                    HStack {
                        Text("Recent Searches")
                        Spacer()
                        Button("Clear") { model.clearRecentSearches() }
                            .font(.caption)
                    }
                }
            }
        }
    }

    private var modeBinding: Binding<ScriptureSearchMode> {
        Binding(
            get: { model.searchMode },
            set: { model.setSearchMode($0) }
        )
    }

    private var scopeBinding: Binding<ScriptureSearchScope> {
        Binding(
            get: { model.searchScope },
            set: { model.setSearchScope($0) }
        )
    }

    private func highlighted(_ text: String) -> AttributedString {
        var output = AttributedString(text)
        let terms = model.searchMode == .allWords
            ? query.split(whereSeparator: \.isWhitespace).map(String.init)
            : [query]

        for term in terms where !term.isEmpty {
            var searchStart = text.startIndex
            while searchStart < text.endIndex,
                  let range = text.range(
                    of: term,
                    options: [.caseInsensitive, .diacriticInsensitive],
                    range: searchStart..<text.endIndex
                  ) {
                if let lower = AttributedString.Index(range.lowerBound, within: output),
                   let upper = AttributedString.Index(range.upperBound, within: output) {
                    output[lower..<upper].inlinePresentationIntent = .stronglyEmphasized
                }
                searchStart = range.upperBound
            }
        }
        return output
    }
}
