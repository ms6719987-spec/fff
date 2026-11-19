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
        let assetId = selectedCategory == "FF MAX"
            ? "YJ~2FW7EkU5pRkVg51NrKyx4LXid8~3D"
            : "U6Zffc4YIR3DslNj3cXvYGAqz58~3D"
        // Show .3105 packages, not arbitrary asset files. Classify installed
        // projects by their declared target directory rather than package name.
        let documents = (selectedCategory == "HS VIPS" ? [] : matchingAssetFiles).map { ListedFile(id: $0.path, name: $0.deletingPathExtension().lastPathComponent) }
        let installed = patchStore.items.compactMap { item -> ListedFile? in
            guard let project = item.project, item.canInspectContents else { return nil }
            let paths = project.rules.map(\.relativePath) + project.directories.map(\.relativePath)
            guard selectedCategory == "HS VIPS" || paths.contains(where: { path in
                path.split(separator: "/").contains(where: { component in
                    let name = String(component).lowercased()
                    return name == "assetindexer.\(assetId.lowercased())"
                })
            }) else { return nil }
            return ListedFile(id: "project-\(item.id)", name: project.name)
        }
        var seen = Set<String>()
        return (documents + installed).filter { seen.insert($0.id).inserted }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }
    @State private var selectedAssetPath: String? = nil
    @State private var activationBusy = false
    @State private var activationMessage: String? = nil
    @State private var showActivationMessage = false
    @State private var showSupport = false
    private let red = Color(red: 1, green: 0.23, blue: 0.27)
    private let panel = Color(red: 0.065, green: 0.005, blue: 0.012)
    private let outline = Color(red: 0.33, green: 0.075, blue: 0.095)
    private let categories: [(String, String)] = [
        ("FF NORMAL", "flame.fill"), ("FF MAX", "flame"),
        ("AP", "shield.lefthalf.filled")
    ]

    var body: some View {
        ZStack {
            Color(red: 0.035, green: 0, blue: 0.007).ignoresSafeArea()
            ScrollView {
                VStack(spacing: 22) {
                    statusPanel
                    categoryPanel
                    launchPanel
                }
                .padding(.horizontal, 18)
                .padding(.top, 20)
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) { hsVipsBottomButton }
        .preferredColorScheme(.dark)
        .alert("Ativação do arquivo", isPresented: $showActivationMessage) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(activationMessage ?? "Não foi possível concluir a operação.")
        }
        .alert("Suporte", isPresented: $showSupport) {
            Button("OK", role: .cancel) { }
        } message: {
            Text("As informações de suporte não estão configuradas neste projeto.")
        }
    }

    private var hsVipsBottomButton: some View {
        Button {
            selectedCategory = "HS VIPS"
        } label: {
            VStack(spacing: 5) {
                Image(systemName: "flame.fill")
                    .font(.system(size: 31, weight: .bold))
                Text("HS VIPS")
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                    .tracking(1.2)
            }
            .foregroundStyle(Color(red: 1.0, green: 0.32, blue: 0.37))
            .frame(width: 154, height: 90)
            .background(Color(red: 0.23, green: 0.19, blue: 0.20),
                        in: RoundedRectangle(cornerRadius: 45, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 45, style: .continuous)
                    .stroke(Color(red: 0.35, green: 0.27, blue: 0.29), lineWidth: 2)
            }
            .shadow(color: .black.opacity(0.35), radius: 6, y: 3)
        }
        .buttonStyle(.plain)
        .frame(maxWidth: .infinity)
        .padding(.top, 12)
        .padding(.bottom, 10)
        .background(Color.black.opacity(0.96))
    }

    private var iphoneModelName: String {
        var systemInfo = utsname()
        uname(&systemInfo)
        let identifier = withUnsafePointer(to: &systemInfo.machine) {
            $0.withMemoryRebound(to: CChar.self, capacity: MemoryLayout.size(ofValue: systemInfo.machine)) {
                String(cString: $0)
            }
        }
        let models: [String: String] = [
            "iPhone10,1": "iPhone 8", "iPhone10,4": "iPhone 8",
            "iPhone10,2": "iPhone 8 Plus", "iPhone10,5": "iPhone 8 Plus",
            "iPhone10,3": "iPhone X", "iPhone10,6": "iPhone X",
            "iPhone11,2": "iPhone XS", "iPhone11,4": "iPhone XS Max", "iPhone11,6": "iPhone XS Max", "iPhone11,8": "iPhone XR",
            "iPhone12,1": "iPhone 11", "iPhone12,3": "iPhone 11 Pro", "iPhone12,5": "iPhone 11 Pro Max", "iPhone12,8": "iPhone SE (2ª geração)",
            "iPhone13,1": "iPhone 12 mini", "iPhone13,2": "iPhone 12", "iPhone13,3": "iPhone 12 Pro", "iPhone13,4": "iPhone 12 Pro Max",
            "iPhone14,2": "iPhone 13 Pro", "iPhone14,3": "iPhone 13 Pro Max", "iPhone14,4": "iPhone 13 mini", "iPhone14,5": "iPhone 13", "iPhone14,6": "iPhone SE (3ª geração)", "iPhone14,7": "iPhone 14", "iPhone14,8": "iPhone 14 Plus",
            "iPhone15,2": "iPhone 14 Pro", "iPhone15,3": "iPhone 14 Pro Max", "iPhone15,4": "iPhone 15", "iPhone15,5": "iPhone 15 Plus",
            "iPhone16,1": "iPhone 15 Pro", "iPhone16,2": "iPhone 15 Pro Max",
            "iPhone17,1": "iPhone 16 Pro", "iPhone17,2": "iPhone 16 Pro Max", "iPhone17,3": "iPhone 16", "iPhone17,4": "iPhone 16 Plus", "iPhone17,5": "iPhone 16e",
            "iPhone18,1": "iPhone 17 Pro", "iPhone18,2": "iPhone 17 Pro Max", "iPhone18,3": "iPhone 17", "iPhone18,4": "iPhone Air",
            "i386": "iPhone (simulador)", "x86_64": "iPhone (simulador)", "arm64": "iPhone (simulador)"
        ]
        return models[identifier] ?? identifier
    }

    private var dispositivoSuportado: Bool {
        let version = AppInfo.versionTuple
        return ExploitSupportPolicy.isSupported(
            major: version.major,
            minor: version.minor,
            patch: version.patch,
            build: AppInfo.osBuild
        )
    }

    private var statusPanel: some View {
        VStack(spacing: 18) {
            HStack {
                Text("STATUS DO DISPOSITIVO").font(.system(size: 17, weight: .heavy, design: .rounded)).tracking(2)
                Spacer()
                Circle().fill(red).frame(width: 9, height: 9)
            }
            statusRow("iphone.gen3", "Device", iphoneModelName, red)
            Button { showSupport = true } label: {
                statusRow("checkmark.seal.fill", "Suporte", dispositivoSuportado ? "SUPORTADO" : "NÃO SUPORTADO", dispositivoSuportado ? .green : .red)
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
            if selectedCategory == "FF NORMAL" || selectedCategory == "FF MAX" || selectedCategory == "HS VIPS" {
                if listedFiles.isEmpty {
                    Text(selectedCategory == "HS VIPS" ? "Nenhum pacote instalado encontrado." : "Nenhum pacote .3105 encontrado para \(selectedCategory). Importe um patch .3105 com um caminho de destino compatível ou adicione-o à pasta correspondente no app Arquivos.")
                        .foregroundStyle(.gray).font(.system(size: 13))
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity).padding(.vertical, 36)
                } else {
                    LazyVStack(spacing: 8) {
                        ForEach(listedFiles) { file in
                            Button {
                                activateListedFile(file)
                            } label: {
                                HStack(spacing: 9) {
                                    Image(systemName: "flame.fill")
                                        .font(.system(size: 19, weight: .bold))
                                        .foregroundStyle(red)
                                        .frame(width: 40, height: 40)
                                        .background(Color(red: 0.13, green: 0.015, blue: 0.025), in: RoundedRectangle(cornerRadius: 11))
                                        .overlay(RoundedRectangle(cornerRadius: 11).stroke(outline, lineWidth: 1))
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(file.name)
                                            .font(.system(size: 12, weight: .semibold, design: .rounded))
                                            .foregroundStyle(.white)
                                            .fixedSize(horizontal: false, vertical: true)
                                            .multilineTextAlignment(.leading)
                                        Text(selectedCategory)
                                            .font(.system(size: 9, weight: .heavy, design: .rounded))
                                            .tracking(1)
                                            .foregroundStyle(red)
                                    }
                                    Spacer(minLength: 0)
                                    Image(systemName: selectedAssetPath == file.id ? "checkmark.circle.fill" : "circle")
                                        .font(.system(size: 23, weight: .medium))
                                        .foregroundStyle(selectedAssetPath == file.id ? red : Color.gray.opacity(0.6))
                                }
                                .padding(.horizontal, 10)
                                .padding(.vertical, 9)
                                .frame(maxWidth: .infinity, minHeight: 64)
                                .background(Color.black, in: RoundedRectangle(cornerRadius: 24))
                                .overlay(RoundedRectangle(cornerRadius: 24).stroke(outline.opacity(0.75), lineWidth: 1))
                            }
                            .buttonStyle(.plain)
                            .disabled(activationBusy)
                        }
                    }
                }
            } else {
                Text("Nenhum patch nesta categoria.")
                    .foregroundStyle(.gray).font(.system(size: 15))
                    .frame(maxWidth: .infinity).padding(.vertical, 36)
            }

        }
        .padding(20)
        .background(panel, in: RoundedRectangle(cornerRadius: 28))
        .overlay(RoundedRectangle(cornerRadius: 28).stroke(outline, lineWidth: 1.2))
        .onAppear { refreshAssetFiles() }
    }

    private func activateListedFile(_ file: ListedFile) {
        guard !activationBusy else { return }
        if selectedAssetPath == file.id {
            activationMessage = "O arquivo já foi aplicado. Para restaurar o estado anterior, use a opção de restauração do patch."
            showActivationMessage = true
            return
        }
        // Import bundled and document packages through the same validated library
        // pipeline used by the regular file importer. Never treat an unvalidated
        // resource as an executable patch.
        if !file.id.hasPrefix("project-") {
            let sourceURL = URL(fileURLWithPath: file.id)
            guard sourceURL.pathExtension.lowercased() == "3105",
                  FileManager.default.fileExists(atPath: sourceURL.path) else {
                activationMessage = "Arquivo .3105 não encontrado."
                showActivationMessage = true
                return
            }
            patchStore.importPackage(at: sourceURL)
            activationMessage = "Importação iniciada nesta tela. Após a validação, o arquivo aparecerá na lista e poderá ser ativado aqui, sem trocar de aba."
            showActivationMessage = true
            return
        }
        guard let item = patchStore.items.first(where: { "project-\($0.id)" == file.id }),
              let baseProject = item.project else {
            activationMessage = "O patch ainda não está disponível na biblioteca."
            showActivationMessage = true
            return
        }
        activationBusy = true
        Task.detached(priority: .userInitiated) {
            do {
                let project = item.summary.schemaVersion >= 2 && item.canInspectContents
                    ? try PatchProjectLibrary.synchronizeWorkspace(item: item)
                    : baseProject
                _ = try DevicePatchService.apply(project: project)
                await MainActor.run {
                    selectedAssetPath = file.id
                    activationBusy = false
                    patchStore.reload()
                    activationMessage = "Patch aplicado com sucesso."
                    showActivationMessage = true
                }
            } catch {
                await MainActor.run {
                    activationBusy = false
                    activationMessage = "Não foi possível aplicar o patch: \(error.localizedDescription)"
                    showActivationMessage = true
                }
            }
        }
    }

    // Match parent directory components, never the filename. Limited to app-accessible Documents.
    private func refreshAssetFiles() {
        let assetId = selectedCategory == "FF MAX"
            ? "YJ~2FW7EkU5pRkVg51NrKyx4LXid8~3D"
            : "U6Zffc4YIR3DslNj3cXvYGAqz58~3D"
        guard let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first,
              let enumerator = FileManager.default.enumerator(at: documents,
                  includingPropertiesForKeys: [.isRegularFileKey],
                  options: [.skipsHiddenFiles]) else {
            matchingAssetFiles = []
            return
        }
        var found: [URL] = []
        for case let url as URL in enumerator {
            guard url.pathExtension.lowercased() == "3105",
                  url.deletingLastPathComponent().pathComponents.contains(where: { component in
                      let name = component.lowercased()
                      return name == "assetindexer.\(assetId.lowercased())"
                  }),
                  (try? url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true else { continue }
            found.append(url)
            if found.count >= 200 { break }
        }
        // Files included in the IPA are read-only bundle resources.
        // They are listed in addition to imported files in Documents.
        let bundledFolder = selectedCategory == "FF MAX" ? "FF_MAX" : "FF_NORMAL"
        if let root = Bundle.main.resourceURL?
            .appendingPathComponent("BundledPatches", isDirectory: true)
            .appendingPathComponent(bundledFolder, isDirectory: true),
           let bundled = try? FileManager.default.contentsOfDirectory(
                at: root, includingPropertiesForKeys: [.isRegularFileKey],
                options: [.skipsHiddenFiles]) {
            found.append(contentsOf: bundled.filter { $0.pathExtension.lowercased() == "3105" })
        }
        matchingAssetFiles = Array(Set(found)).sorted { $0.lastPathComponent < $1.lastPathComponent }

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
        Button { selectedCategory = title; selectedAssetPath = nil; refreshAssetFiles() } label: {
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
