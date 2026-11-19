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
        RoyalDashboardView(installedContent: AnyView(sectionContent(.installed)))
    }

    private var regularLayout: some View {
        RoyalDashboardView(installedContent: AnyView(sectionContent(.installed)))
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
    let installedContent: AnyView
    @State private var selectedCategory = "FF NORMAL"
    @State private var showInstalled = false
    @State private var showSupport = false
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
                    statusPanel
                    categoryPanel
                    launchPanel
                    Button { showInstalled = true } label: {
                        VStack(spacing: 6) {
                            Image(systemName: "flame.fill").font(.system(size: 32))
                            Text("HS VIPS").font(.system(size: 15, weight: .bold, design: .rounded))
                        }
                        .foregroundStyle(red)
                        .frame(width: 146, height: 92)
                        .background(Color.white.opacity(0.14), in: Capsule())
                        .overlay(Capsule().stroke(Color.white.opacity(0.12), lineWidth: 3))
                    }
                    .padding(.bottom, 30)
                }
                .padding(.horizontal, 18)
                .padding(.top, 20)
            }
        }
        .preferredColorScheme(.dark)
        .sheet(isPresented: $showInstalled) {
            NavigationStack {
                installedContent
                    .navigationTitle("Installed")
                    .toolbar { ToolbarItem(placement: .topBarTrailing) {
                        Button("Fechar") { showInstalled = false }
                    }}
            }
        }
        .alert("Suporte", isPresented: $showSupport) {
            Button("OK", role: .cancel) { }
        } message: {
            Text("As informações de suporte não estão configuradas neste projeto.")
        }
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
                    Button { selectedCategory = item.0 } label: {
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
            Text("Nenhum patch nesta categoria.")
                .foregroundStyle(.gray).font(.system(size: 15))
                .frame(maxWidth: .infinity).padding(.vertical, 36)
            Button { showInstalled = true } label: {
                Label("Abrir Installed", systemImage: "arrow.clockwise")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(red).frame(maxWidth: .infinity)
            }
        }
        .padding(20)
        .background(panel, in: RoundedRectangle(cornerRadius: 28))
        .overlay(RoundedRectangle(cornerRadius: 28).stroke(outline, lineWidth: 1.2))
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
        Button { showInstalled = true } label: {
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
