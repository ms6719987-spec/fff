import SwiftUI
import UIKit

struct ContentView: View {
    @Environment(\.appLanguage) private var language
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @EnvironmentObject private var patchDraftCoordinator: PatchDraftCoordinator
    @EnvironmentObject private var patchStore: PatchProjectStore
    @EnvironmentObject private var repositoryStore: PackageRepositoryStore
    @AppStorage(FeatureVisibility.developerModeStorageKey)
    private var developerModeEnabled = false
    @State private var tabNavigation: AppTabNavigationState
    @State private var showSettings = false
    @State private var showLogs = false

    init() {
#if targetEnvironment(simulator)
        let arguments = ProcessInfo.processInfo.arguments
        let initialTab: Int
        if arguments.contains("--simulate-new-tab") {
            initialTab = 1
        } else if arguments.contains("--simulate-sources-tab") {
            initialTab = 2
        } else if arguments.contains("--simulate-installed-tab")
                    || arguments.contains("--simulate-patch-tab")
                    || arguments.contains("--simulate-wallpaper-tab") {
            initialTab = 3
        } else if arguments.contains("--simulate-files-tab") {
            initialTab = 4
        } else if arguments.contains("--simulate-search-tab") {
            initialTab = 5
        } else {
            initialTab = AppSection.installed.rawValue
        }
        _tabNavigation = State(initialValue: AppTabNavigationState(selectedTab: initialTab))
        _showSettings = State(
            initialValue: arguments.contains("--simulate-settings")
        )
#else
        _tabNavigation = State(initialValue: AppTabNavigationState())
#endif
    }

    var body: some View {
        Group {
            if horizontalSizeClass == .regular {
                regularLayout
            } else {
                compactLayout
            }
        }
        .tint(AppTheme.accent)
        .imageScale(.small)
        .onChange(of: patchDraftCoordinator.request?.id) { requestID in
            if requestID != nil { tabNavigation.select(AppSection.installed.rawValue) }
        }
        .onChange(of: patchDraftCoordinator.importRequest?.id) { requestID in
            if requestID != nil { tabNavigation.select(AppSection.installed.rawValue) }
        }
        .onChange(of: developerModeEnabled) { _ in
            tabNavigation.reconcileSelection(with: featureVisibility)
        }
        .onAppear {
            tabNavigation.reconcileSelection(with: featureVisibility)
        }
        .sheet(isPresented: $showSettings) { SettingsView() }
        .sheet(isPresented: $showLogs) { LogView() }
        .patchStorePresentation(patchStore)
        .repositoryStorePresentation(repositoryStore, patchStore: patchStore)
    }

    private var compactLayout: some View {
        RoyalDashboardView()
    }

    private var regularLayout: some View {
        RoyalDashboardView()
    }

    @ViewBuilder
    private func sectionContent(_ section: AppSection) -> some View {
        switch section {
        case .home:
            RepositoryHomeView(
                onOpenSettings: openSettings,
                onOpenLogs: openLogs
            )
        case .new:
            RepositoryNewView(
                onOpenSettings: openSettings,
                onOpenLogs: openLogs
            )
        case .sources:
            RepositorySourcesView(
                onOpenSettings: openSettings,
                onOpenLogs: openLogs
            )
        case .installed:
            PatchProjectsView(
                onOpenSettings: openSettings,
                onOpenLogs: openLogs
            )
        case .files:
            AppDataBrowserView(
                tabSession: filesTabSession,
                onOpenSettings: openSettings,
                onOpenLogs: openLogs
            )
        case .search:
            RepositorySearchView(
                onOpenSettings: openSettings,
                onOpenLogs: openLogs
            )
        }
    }

    private var tabSelection: Binding<Int> {
        Binding(
            get: { tabNavigation.selectedTab },
            set: { tabNavigation.select($0) }
        )
    }

    private var filesTabSession: Binding<FilesTabSession> {
        Binding(
            get: { tabNavigation.filesTabs },
            set: { tabNavigation.setFilesTabs($0) }
        )
    }

    private var featureVisibility: FeatureVisibility {
        FeatureVisibility(developerModeEnabled: developerModeActive)
    }

    private var developerModeActive: Bool {
#if targetEnvironment(simulator)
        developerModeEnabled
            || ProcessInfo.processInfo.arguments.contains("--simulate-developer-mode")
            || ProcessInfo.processInfo.arguments.contains("--simulate-files-tab")
#else
        developerModeEnabled
#endif
    }

    private var selectedVisibleSection: AppSection {
        let selected = AppSection(rawValue: tabNavigation.selectedTab)
        return selected.flatMap {
            featureVisibility.isVisible($0) ? $0 : nil
        } ?? .installed
    }

    private func openSettings() {
        showSettings = true
    }

    private func openLogs() {
        showLogs = true
    }
}

private struct CompactTabLabel: View {
    let title: String
    let systemImage: String

    @ViewBuilder
    var body: some View {
        if let image = UIImage(
            systemName: systemImage,
            withConfiguration: UIImage.SymbolConfiguration(pointSize: 17, weight: .medium)
        )?.withRenderingMode(.alwaysTemplate) {
            Image(uiImage: image)
        } else {
            Image(systemName: systemImage)
                .font(.system(size: 17, weight: .medium))
        }
        Text(title)
    }
}

private extension AppSection {
    var titleKey: String {
        switch self {
        case .home: return "tab.home"
        case .new: return "tab.new"
        case .sources: return "tab.sources"
        case .installed: return "tab.installed"
        case .files: return "tab.files"
        case .search: return "tab.search"
        }
    }

    var systemImage: String {
        switch self {
        case .home: return "house.fill"
        case .new: return "clock.fill"
        case .sources: return "shippingbox.fill"
        case .installed: return "tray.full.fill"
        case .files: return "folder.fill"
        case .search: return "magnifyingglass"
        }
    }
}


// Custom dashboard presentation. Existing Installed functionality remains available.
private struct RoyalDashboardView: View {
    @EnvironmentObject private var patchStore: PatchProjectStore
    @State private var selectedCategory = "FF NORMAL"
    @State private var matchingAssetFiles: [URL] = []
    private struct ListedFile: Identifiable {
        let id: String
        let name: String
    }
    private var listedFiles: [ListedFile] {
        let prefix = selectedCategory == "FF MAX"
            ? "maassetindexer.YJ~2FW7EkU5pRkVg51NrKyx4LXid8~3D"
            : "assetindexer.U6Zffc4YIR3DslNj3cXvYGAqz58~3D"
        let documents = matchingAssetFiles.map { ListedFile(id: $0.path, name: $0.lastPathComponent) }
        let installed = patchStore.items.flatMap { item -> [ListedFile] in
            guard let project = item.project, item.canInspectContents else { return [] }
            return project.rules.enumerated().compactMap { index, rule in
                let name = rule.replacementFilename
                guard name.hasPrefix(prefix) else { return nil }
                return ListedFile(id: "\(item.id)-\(index)", name: name)
            }
        }
        var seen = Set<String>()
        return (documents + installed).filter { seen.insert($0.id).inserted }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }
    @State private var selectedAssetPath: String? = nil
    @State private var showSupport = false
    @State private var showVIPTab = false
    private let red = Color(red: 1, green: 0.23, blue: 0.27)
    private let panel = Color(red: 0.065, green: 0.005, blue: 0.012)
    private let outline = Color(red: 0.33, green: 0.075, blue: 0.095)
    private let categories: [(String, String)] = [
        ("FF NORMAL", "flame.fill"), ("FF MAX", "flame"),
        ("AP", "shield.lefthalf.filled"), ("SKINS / TEXTURAS", "square.grid.2x2.fill"),
        ("HOLOGRAMAS", "wand.and.stars"), ("OUTROS", "shippingbox.fill")
    ]

    var body: some View {
        ZStack {
            Color(red: 0.035, green: 0, blue: 0.007).ignoresSafeArea()
            ScrollView {
                VStack(spacing: 22) {
                    if showVIPTab {
                        vipTab
                    } else {
                    statusPanel
                    categoryPanel
                    launchPanel
                    Button { showVIPTab = true } label: {
                        VStack(spacing: 4) {
                            Image(systemName: "flame.fill").font(.system(size: 24))
                            Text("HS VIPS").font(.system(size: 12, weight: .bold, design: .rounded))
                        }
                        .foregroundStyle(red)
                        .frame(width: 112, height: 68)
                        .background(Color.white.opacity(0.14), in: Capsule())
                        .overlay(Capsule().stroke(Color.white.opacity(0.12), lineWidth: 3))
                    }
                    .padding(.bottom, 30)
                    }
                }
                .padding(.horizontal, 18)
                .padding(.top, 20)
            }
        }
        .preferredColorScheme(.dark)
        .alert("Suporte", isPresented: $showSupport) {
            Button("OK", role: .cancel) { }
        } message: {
            Text("As informações de suporte não estão configuradas neste projeto.")
        }
    }

    // HS VIPS replaces the former Installed screen while retaining its tools and data.
    private var vipTab: some View {
        VStack(alignment: .leading, spacing: 16) {
            Button { showVIPTab = false } label: {
                Label("Voltar", systemImage: "chevron.left")
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                    .foregroundStyle(red)
            }
            .buttonStyle(.plain)

            heading("flame.fill", "HS VIPS")

            Text("Arquivos disponíveis nas categorias FF NORMAL e FF MAX aparecem na lista da tela principal.")
                .foregroundStyle(.gray)
                .font(.system(size: 14))
                .padding(.vertical, 22)
        }
        .padding(16)
        .background(panel, in: RoundedRectangle(cornerRadius: 28))
        .overlay(RoundedRectangle(cornerRadius: 28).stroke(outline, lineWidth: 1.2))
    }

    private var statusPanel: some View {
        VStack(spacing: 18) {
            HStack {
                Text("STATUS DO DISPOSITIVO").font(.system(size: 17, weight: .heavy, design: .rounded)).tracking(2)
                Spacer()
                Circle().fill(red).frame(width: 9, height: 9)
            }
            statusRow("iphone.gen3", "Device", UIDevice.current.model, red)
            Button { showSupport = true } label: {
                statusRow("checkmark.seal.fill", "Support", "SUPPORTED", .green)
            }.buttonStyle(.plain)
            statusRow("lock.shield.fill", "Licença", "Não configurada", .yellow)
        }
        .padding(20)
        .background(panel, in: RoundedRectangle(cornerRadius: 28))
        .overlay(RoundedRectangle(cornerRadius: 28).stroke(outline, lineWidth: 1.2))
    }

    private func statusRow(_ symbol: String, _ label: String, _ value: String, _ tint: Color) -> some View {
        HStack(spacing: 15) {
            Image(systemName: symbol)
                .font(.system(size: 24, weight: .bold))
                .foregroundStyle(tint)
                .frame(width: 53, height: 53)
                .background(tint.opacity(0.13), in: RoundedRectangle(cornerRadius: 15))
                .overlay(RoundedRectangle(cornerRadius: 15).stroke(tint.opacity(0.35)))
            Text(label).foregroundStyle(.gray)
            Spacer(minLength: 4)
            Text(value).font(.system(size: 15, weight: .heavy, design: .rounded))
                .foregroundStyle(.white).lineLimit(1).minimumScaleFactor(0.7)
        }
    }

    private var categoryPanel: some View {
        VStack(alignment: .leading, spacing: 22) {
            heading("bolt.fill", "CATEGORIAS ONLINE")
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
                ForEach(categories, id: \.0) { item in
                    Button { selectedCategory = item.0; if item.0 == "FF NORMAL" || item.0 == "FF MAX" { refreshAssetFiles() } } label: {
                        VStack(spacing: 14) {
                            Image(systemName: item.1).font(.system(size: 29, weight: .bold))
                            Text(item.0).font(.system(size: 10, weight: .heavy, design: .rounded))
                                .tracking(0.5).lineLimit(1).minimumScaleFactor(0.65)
                        }
                        .foregroundStyle(selectedCategory == item.0 ? .white : .gray)
                        .frame(maxWidth: .infinity).frame(height: 105)
                        .background(selectedCategory == item.0 ? red : .black, in: RoundedRectangle(cornerRadius: 23))
                        .overlay(RoundedRectangle(cornerRadius: 23).stroke(selectedCategory == item.0 ? Color.white.opacity(0.5) : outline, lineWidth: 1.3))
                    }.buttonStyle(.plain)
                }
            }
            if selectedCategory == "FF NORMAL" || selectedCategory == "FF MAX" {
                if listedFiles.isEmpty {
                    Text("Nenhum arquivo \(selectedCategory == "FF MAX" ? "maassetindexer.YJ~2FW7EkU5pRkVg51NrKyx4LXid8~3D" : "assetindexer.U6Zffc4YIR3DslNj3cXvYGAqz58~3D") encontrado.")
                        .foregroundStyle(.gray).font(.system(size: 13))
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity).padding(.vertical, 36)
                } else {
                    LazyVStack(spacing: 14) {
                        ForEach(listedFiles) { file in
                            Button {
                                selectedAssetPath = selectedAssetPath == file.id ? nil : file.id
                            } label: {
                                HStack(spacing: 14) {
                                    Image(systemName: "flame.fill")
                                        .font(.system(size: 28, weight: .bold))
                                        .foregroundStyle(red)
                                        .frame(width: 62, height: 62)
                                        .background(Color(red: 0.13, green: 0.015, blue: 0.025), in: RoundedRectangle(cornerRadius: 16))
                                        .overlay(RoundedRectangle(cornerRadius: 16).stroke(outline, lineWidth: 1))
                                    VStack(alignment: .leading, spacing: 8) {
                                        Text(file.name)
                                            .font(.system(size: 15, weight: .heavy, design: .rounded))
                                            .foregroundStyle(.white)
                                            .lineLimit(2)
                                            .multilineTextAlignment(.leading)
                                        Text(selectedCategory)
                                            .font(.system(size: 11, weight: .heavy, design: .rounded))
                                            .tracking(2)
                                            .foregroundStyle(red)
                                    }
                                    Spacer(minLength: 4)
                                    Image(systemName: selectedAssetPath == file.id ? "checkmark.circle.fill" : "circle")
                                        .font(.system(size: 29, weight: .medium))
                                        .foregroundStyle(selectedAssetPath == file.id ? red : Color.gray.opacity(0.6))
                                }
                                .padding(16)
                                .frame(maxWidth: .infinity, minHeight: 104)
                                .background(Color.black, in: RoundedRectangle(cornerRadius: 24))
                                .overlay(RoundedRectangle(cornerRadius: 24).stroke(outline.opacity(0.75), lineWidth: 1))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            } else {
                Text("Nenhum patch nesta categoria.")
                    .foregroundStyle(.gray).font(.system(size: 15))
                    .frame(maxWidth: .infinity).padding(.vertical, 36)
            }
            Button { showVIPTab = true } label: {
                Label("Abrir HS VIPS", systemImage: "arrow.clockwise")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(red).frame(maxWidth: .infinity)
            }
        }
        .padding(20)
        .background(panel, in: RoundedRectangle(cornerRadius: 28))
        .overlay(RoundedRectangle(cornerRadius: 28).stroke(outline, lineWidth: 1.2))
        .onAppear { refreshAssetFiles() }
    }

    // Only files within this app's accessible Documents folder can be listed.
    private func refreshAssetFiles() {
        let prefix = selectedCategory == "FF MAX"
            ? "maassetindexer.YJ~2FW7EkU5pRkVg51NrKyx4LXid8~3D"
            : "assetindexer.U6Zffc4YIR3DslNj3cXvYGAqz58~3D"
        guard let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first,
              let enumerator = FileManager.default.enumerator(at: documents,
                  includingPropertiesForKeys: [.isRegularFileKey],
                  options: [.skipsHiddenFiles]) else {
            matchingAssetFiles = []
            return
        }
        var found: [URL] = []
        for case let url as URL in enumerator {
            guard url.lastPathComponent.hasPrefix(prefix),
                  (try? url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true else { continue }
            found.append(url)
            if found.count >= 200 { break }
        }
        matchingAssetFiles = found.sorted { $0.lastPathComponent < $1.lastPathComponent }

    }

    private var launchPanel: some View {
        VStack(alignment: .leading, spacing: 22) {
            heading("arrow.up.right.square.fill", "LAUNCH GAME")
            HStack(spacing: 12) {
                launchButton("FF NORMAL")
                launchButton("FF MAX")
            }
        }
        .padding(20)
        .background(panel, in: RoundedRectangle(cornerRadius: 28))
        .overlay(RoundedRectangle(cornerRadius: 28).stroke(outline, lineWidth: 1.2))
    }

    private func launchButton(_ title: String) -> some View {
        Button { showVIPTab = true } label: {
            Label(title, systemImage: "play.fill")
                .font(.system(size: 14, weight: .heavy, design: .rounded))
                .foregroundStyle(.white).frame(maxWidth: .infinity).frame(height: 76)
                .background(red.opacity(0.07), in: RoundedRectangle(cornerRadius: 22))
                .overlay(RoundedRectangle(cornerRadius: 22).stroke(outline, lineWidth: 1.3))
        }.buttonStyle(.plain)
    }

    private func heading(_ symbol: String, _ title: String) -> some View {
        HStack(spacing: 14) {
            Image(systemName: symbol).font(.system(size: 23, weight: .bold))
                .foregroundStyle(red).frame(width: 55, height: 55)
                .background(red.opacity(0.12), in: RoundedRectangle(cornerRadius: 17))
                .overlay(RoundedRectangle(cornerRadius: 17).stroke(outline))
            Text(title).font(.system(size: 18, weight: .black, design: .rounded))
                .tracking(2).foregroundStyle(.white).minimumScaleFactor(0.7)
            Spacer(minLength: 0)
            Circle().fill(red).frame(width: 8, height: 8)
        }
    }
}
