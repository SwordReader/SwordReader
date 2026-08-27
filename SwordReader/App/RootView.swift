import SwiftUI

struct RootView: View {
    @Environment(AppModel.self) private var model
    @State private var dismissedCrashDiagnosticID: CrashDiagnosticReport.ID?
    @State private var crashDiagnosticForReview: CrashDiagnosticReport?

    var body: some View {
        Group {
            #if os(macOS)
            if model.isPresentingOnboarding {
                OnboardingView()
                    .environment(model)
                    .frame(minWidth: 760, minHeight: 620)
            } else {
                SplitRootView()
                    .frame(minWidth: 760, minHeight: 620)
            }
            #else
            TabRootView()
            #endif
        }
        .alert(item: Bindable(model).presentedError) { error in
            Alert(
                title: Text("Something Went Wrong"),
                message: Text(error.message),
                dismissButton: .default(Text("OK"))
            )
        }
        .alert(item: Bindable(model).continuityNotice) { notice in
            Alert(
                title: Text("Bible Not Installed"),
                message: Text(notice.message),
                primaryButton: .default(Text("Download & Continue")) {
                    Task { await model.downloadContinuityModule() }
                },
                secondaryButton: .cancel(
                    Text(notice.currentTranslationTitle == nil ? "Not Now" : "Use Current Bible")
                )
            )
        }
        .alert("Crash Diagnostic Available", isPresented: crashDiagnosticAlertBinding) {
            Button("Review Report") {
                crashDiagnosticForReview = model.pendingCrashDiagnostic
            }
            Button("Not Now", role: .cancel) {
                dismissedCrashDiagnosticID = model.pendingCrashDiagnostic?.id
            }
        } message: {
            Text("Apple provided a diagnostic for a previous crash. Review and edit it before choosing whether to share it; SwordReader never uploads it automatically.")
        }
        .sheet(item: $crashDiagnosticForReview) { report in
            CrashDiagnosticReviewView(report: report) {
                model.clearPendingCrashDiagnostic()
                crashDiagnosticForReview = nil
            }
        }
        #if !os(macOS)
        .fullScreenCover(isPresented: onboardingBinding) {
            OnboardingView().environment(model)
        }
        #endif
    }

    private var onboardingBinding: Binding<Bool> {
        Binding(
            get: { model.isPresentingOnboarding },
            set: { if !$0 { model.completeOnboarding() } }
        )
    }

    private var crashDiagnosticAlertBinding: Binding<Bool> {
        Binding(
            get: {
                guard let report = model.pendingCrashDiagnostic else { return false }
                return report.id != dismissedCrashDiagnosticID
            },
            set: { isPresented in
                if !isPresented, crashDiagnosticForReview == nil {
                    dismissedCrashDiagnosticID = model.pendingCrashDiagnostic?.id
                }
            }
        )
    }
}

private struct TabRootView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        TabView(selection: $model.section) {
            NavigationStack { ReaderView() }
                .tabItem { Label(AppSection.read.title, systemImage: AppSection.read.systemImage) }
                .tag(AppSection.read)
            NavigationStack { StudyItemsView() }
                .tabItem { Label(AppSection.study.title, systemImage: AppSection.study.systemImage) }
                .tag(AppSection.study)
            NavigationStack { ReadingPlansView() }
                .tabItem { Label(AppSection.plans.title, systemImage: AppSection.plans.systemImage) }
                .tag(AppSection.plans)
            NavigationStack { SearchView() }
                .tabItem { Label(AppSection.search.title, systemImage: AppSection.search.systemImage) }
                .tag(AppSection.search)
            NavigationStack { LibraryView() }
                .tabItem { Label(AppSection.library.title, systemImage: AppSection.library.systemImage) }
                .tag(AppSection.library)
            NavigationStack { PreferencesView() }
                .tabItem { Label(AppSection.settings.title, systemImage: AppSection.settings.systemImage) }
                .tag(AppSection.settings)
        }
    }
}

private struct SplitRootView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        NavigationSplitView {
            List(AppSection.primarySections) { section in
                Button {
                    model.section = section
                } label: {
                    HStack {
                        Label(section.title, systemImage: section.systemImage)
                        Spacer()
                        if model.section == section {
                            Image(systemName: "checkmark")
                                .accessibilityHidden(true)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .listRowBackground(model.section == section ? Color.accentColor.opacity(0.14) : Color.clear)
                .accessibilityAddTraits(
                    model.section == section ? .isSelected : []
                )
            }
            .navigationTitle("SwordReader")
        } detail: {
            NavigationStack {
                switch model.section {
                case .read: ReaderView()
                case .study: StudyItemsView()
                case .plans: ReadingPlansView()
                case .search: SearchView()
                case .library: LibraryView()
                case .settings: PreferencesView()
                }
            }
        }
    }
}

struct PreferencesView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        Form {
            Section("Reading") {
                Toggle("Red-letter text", isOn: redLetterBinding)
                    .help("Show words of Christ in red when the installed module provides that formatting")

                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Font Size")
                        Spacer()
                        Text("\(Int(model.readerFontSize.rounded())) pt")
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                    Slider(value: fontSizeBinding, in: 12...32, step: 0.5) {
                        Text("Font Size")
                    } minimumValueLabel: {
                        Image(systemName: "textformat.size.smaller")
                    } maximumValueLabel: {
                        Image(systemName: "textformat.size.larger")
                    }

                    VStack(alignment: .leading, spacing: 6) {
                        Text("Reader Preview")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                        (Text("16 ").foregroundStyle(.secondary)
                            + Text("I am the way, and the truth, and the life.")
                                .foregroundStyle(model.showsRedLetterText ? .red : .primary))
                            .font(.system(size: model.readerFontSize, design: model.readerFont.design))
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding()
                            .background(.background, in: .rect(cornerRadius: 8))
                    }
                }
            }

            Section("Library") {
                NavigationLink("Installed Modules") {
                    InstalledModulesPreferencesView()
                        .environment(model)
                }
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Settings")
    }

    private var redLetterBinding: Binding<Bool> {
        Binding(
            get: { model.showsRedLetterText },
            set: { model.setShowsRedLetterText($0) }
        )
    }

    private var fontSizeBinding: Binding<Double> {
        Binding(
            get: { model.readerFontSize },
            set: { model.setReaderFontSize($0) }
        )
    }
}

private struct InstalledModulesPreferencesView: View {
    @Environment(AppModel.self) private var model
    @State private var biblePendingRemoval: BibleModule?
    @State private var keyedModulePendingRemoval: KeyedModule?

    var body: some View {
        List {
            Section("Bibles") {
                if model.modules.isEmpty {
                    Text("No Bibles installed").foregroundStyle(.secondary)
                }
                ForEach(model.modules) { module in
                    moduleRow(
                        title: module.title,
                        details: [module.id, module.language, module.version]
                    ) {
                        biblePendingRemoval = module
                    }
                }
            }

            Section("Books, Dictionaries & Devotionals") {
                if model.keyedModules.isEmpty {
                    Text("No books, dictionaries, or devotionals installed")
                        .foregroundStyle(.secondary)
                }
                ForEach(model.keyedModules) { module in
                    moduleRow(
                        title: module.title,
                        details: [module.category.title, module.language, module.version]
                    ) {
                        keyedModulePendingRemoval = module
                    }
                }
            }
        }
        .navigationTitle("Installed Modules")
        .confirmationDialog(
            "Delete \(biblePendingRemoval?.title ?? "Bible")?",
            isPresented: Binding(
                get: { biblePendingRemoval != nil },
                set: { if !$0 { biblePendingRemoval = nil } }
            ),
            titleVisibility: .visible,
            presenting: biblePendingRemoval
        ) { module in
            Button("Delete from This Device", role: .destructive) {
                biblePendingRemoval = nil
                Task { await model.removeModule(id: module.id) }
            }
            Button("Cancel", role: .cancel) { biblePendingRemoval = nil }
        } message: { module in
            Text("\(module.title) can be installed again later from its module source.")
        }
        .confirmationDialog(
            "Delete \(keyedModulePendingRemoval?.title ?? "Module")?",
            isPresented: Binding(
                get: { keyedModulePendingRemoval != nil },
                set: { if !$0 { keyedModulePendingRemoval = nil } }
            ),
            titleVisibility: .visible,
            presenting: keyedModulePendingRemoval
        ) { module in
            Button("Delete from This Device", role: .destructive) {
                keyedModulePendingRemoval = nil
                Task { await model.removeKeyedModule(id: module.id) }
            }
            Button("Cancel", role: .cancel) { keyedModulePendingRemoval = nil }
        } message: { module in
            Text("\(module.title) can be installed again later from its module source.")
        }
    }

    private func moduleRow(
        title: String,
        details: [String?],
        delete: @escaping () -> Void
    ) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                Text(details.compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · "))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button("Delete", systemImage: "trash", role: .destructive, action: delete)
                .labelStyle(.iconOnly)
                .disabled(model.removingModuleID != nil)
                .help("Remove from This Device")
        }
    }
}
