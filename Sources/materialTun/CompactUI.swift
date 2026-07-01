import SwiftUI
import AppKit
import UniformTypeIdentifiers

enum CompactTab: String, CaseIterable {
    case connection = "Главная"
    case profiles = "Профили"
    case settings = "Настройки"

    var icon: String {
        switch self {
        case .connection: "power"
        case .profiles: "square.stack.3d.up.fill"
        case .settings: "slider.horizontal.3"
        }
    }
}

enum SeedColor: String, CaseIterable, Identifiable {
    case purple = "Фиолетовая"
    case red = "Красная"
    case amber = "Жёлтая"
    var id: String { rawValue }

    var color: Color {
        switch self {
        case .purple: Color(hex: "D0BCFF")
        case .red: Color(hex: "FFB4AB")
        case .amber: Color(hex: "FFDDB0")
        }
    }
}

struct CompactRootView: View {
    @EnvironmentObject private var store: AppStore
    @AppStorage("SeedColor") private var seedName = SeedColor.purple.rawValue
    @State private var tab = CompactTab.connection
    @State private var showWorkspace = false
    @Namespace private var navigationAnimation

    private var seed: Color { SeedColor(rawValue: seedName)?.color ?? .purple }

    var body: some View {
        ZStack {
            CompactBackground()

            VStack(spacing: 0) {
                compactTopBar
                Group {
                    switch tab {
                    case .connection: CompactConnectionView(seed: seed)
                    case .profiles: CompactProfilesView(seed: seed)
                    case .settings: CompactSettingsView(seed: seed)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(.horizontal, 14)
                .padding(.bottom, 74)
                .transition(.opacity.combined(with: .scale(scale: 0.985)))
            }

            VStack {
                Spacer()
                compactNavigation
                    .padding(.bottom, 16)
            }

            if showWorkspace {
                Color.black.opacity(0.34)
                    .ignoresSafeArea()
                    .contentShape(Rectangle())
                    .onTapGesture {
                        withAnimation(.easeOut(duration: 0.18)) { showWorkspace = false }
                    }
                    .transition(.opacity)

                WorkspaceSheet(seed: seed) {
                    withAnimation(.easeOut(duration: 0.18)) { showWorkspace = false }
                }
                .transition(.scale(scale: 0.96).combined(with: .opacity))
            }

            if let toast = store.toast {
                VStack {
                    Text(toast)
                        .font(.system(size: 11, weight: .semibold))
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(Color(hex: "312E38"), in: Capsule())
                        .padding(.top, 46)
                    Spacer()
                }
                .transition(.opacity.combined(with: .scale(scale: 0.96)))
            }
        }
        .tint(seed)
        .preferredColorScheme(.dark)
        .frame(width: 640, height: 470)
        .animation(.spring(response: 0.44, dampingFraction: 0.82), value: tab)
        .animation(.easeInOut(duration: 0.62), value: store.toast)
        .onChange(of: store.settings) { _, _ in store.save() }
        .sheet(isPresented: Binding(
            get: { !store.onboardingComplete },
            set: { if !$0 { store.completeOnboarding() } }
        )) { OnboardingView(seed: seed) }
        .onOpenURL { url in
            if url.isFileURL {
                store.importFiles([url])
            } else {
                let count = store.addProfiles(from: url.absoluteString)
                store.showToast(count > 0 ? "Профиль импортирован" : "Ссылка не распознана")
            }
        }
    }

    private var compactTopBar: some View {
        ZStack {
            Text(tab.rawValue)
                .font(.system(size: 13, weight: .bold, design: .rounded))

            HStack(spacing: 10) {
                Button { showWorkspace = true } label: {
                    HStack(spacing: 8) {
                        Circle()
                            .fill(seed)
                            .frame(width: 9, height: 9)
                        Text(store.activeWorkspace?.name ?? "Личный")
                            .font(.system(size: 12, weight: .semibold))
                            .lineLimit(1)
                        Image(systemName: "chevron.down").font(.system(size: 8, weight: .bold))
                    }
                    .padding(.horizontal, 11).frame(height: 30)
                    .background(Color(hex: "211F26"), in: Capsule())
                }
                .buttonStyle(.plain)

                Spacer()

                Menu {
                    Button("Импорт из буфера") {
                        let text = NSPasteboard.general.string(forType: .string) ?? ""
                        let count = store.addProfiles(from: text)
                        store.showToast(count > 0 ? "Добавлено: \(count)" : "Ничего не найдено")
                    }
                    Button("QR из изображения…") { store.importQRImage() }
                    Button("Проверить обновления") { Task { await store.checkForUpdates() } }
                } label: {
                    Image(systemName: "ellipsis")
                        .frame(width: 30, height: 30)
                        .background(Color(hex: "211F26"), in: Circle())
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
            }
        }
        .padding(.horizontal, 14)
        .frame(height: 46)
    }

    private var compactNavigation: some View {
        HStack(spacing: 2) {
            ForEach(CompactTab.allCases, id: \.self) { item in
                Button {
                    withAnimation(.spring(response: 0.48, dampingFraction: 0.76)) { tab = item }
                } label: {
                    ZStack {
                        if tab == item {
                            Capsule()
                                .fill(seed.opacity(0.28))
                                .matchedGeometryEffect(id: "compact-navigation", in: navigationAnimation)
                        }
                        Image(systemName: item.icon)
                            .font(.system(size: 14, weight: .semibold))
                            .symbolEffect(.bounce, value: tab == item)
                    }
                    .frame(width: 56, height: 38)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .foregroundStyle(tab == item ? .white : .white.opacity(0.56))
            }
        }
        .padding(5)
        .background(Color(hex: "211F26"), in: Capsule())
    }
}

struct CompactBackground: View {
    var body: some View {
        Color(hex: "141218").ignoresSafeArea()
    }
}

struct CompactConnectionView: View {
    @EnvironmentObject private var store: AppStore
    let seed: Color
    @State private var now = Date()
    @State private var waveVisible = false
    @State private var waveExpanded = false
    @State private var appeared = false

    var body: some View {
        VStack(spacing: 10) {
            Spacer(minLength: 0)

            Button { store.toggleConnection() } label: {
                TimelineView(.animation(minimumInterval: 1.0 / 40.0)) { context in
                    let time = context.date.timeIntervalSinceReferenceDate
                    ZStack {
                        if waveVisible {
                            Circle()
                                .stroke(seed.opacity(0.46), lineWidth: 3)
                                .frame(width: 92, height: 92)
                                .scaleEffect(waveExpanded ? 1.75 : 0.9)
                                .opacity(waveExpanded ? 0 : 0.9)
                        }

                        Circle()
                            .fill(seed.opacity(isTransitioning ? 0.18 : 0.13))
                            .frame(width: 136, height: 136)
                            .scaleEffect(isTransitioning ? 1.03 + sin(time * 10) * 0.025 : 1)

                        if isTransitioning {
                            ForEach(0..<3, id: \.self) { index in
                                Circle()
                                    .trim(from: CGFloat(index) * 0.24, to: CGFloat(index) * 0.24 + 0.13)
                                    .stroke(
                                        seed.opacity(0.9 - Double(index) * 0.18),
                                        style: StrokeStyle(lineWidth: 3.2 - CGFloat(index) * 0.55, lineCap: .round)
                                    )
                                    .frame(
                                        width: 122 - CGFloat(index) * 13,
                                        height: 122 - CGFloat(index) * 13
                                    )
                                    .rotationEffect(.degrees(time * (170 + Double(index) * 55) * (index == 1 ? -1 : 1)))
                            }
                        }

                        Circle()
                            .fill(seed)
                            .frame(width: 88, height: 88)
                            .scaleEffect(isTransitioning ? 0.96 + sin(time * 13) * 0.025 : 1)

                        Image(systemName: connectionIcon)
                            .font(.system(size: 30, weight: .semibold))
                            .foregroundStyle(Color(hex: "211F26"))
                            .contentTransition(.symbolEffect(.replace))
                            .symbolEffect(.pulse.wholeSymbol, options: .repeating.speed(1.7), isActive: isTransitioning)
                    }
                    .scaleEffect(appeared ? 1 : 0.84)
                    .opacity(appeared ? 1 : 0)
                }
            }
            .buttonStyle(CompactPressStyle())

            VStack(spacing: 3) {
                Text(store.state.title)
                    .font(.system(size: 20, weight: .bold, design: .rounded))
                Text(store.selectedServer?.name ?? "Выберите сервер")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            HStack(spacing: 8) {
                TinyMetric(icon: "clock", value: duration, label: "Сессия")
                TinyMetric(icon: "arrow.down", value: rate(store.downRate), label: "Загрузка")
                TinyMetric(icon: "arrow.up", value: rate(store.upRate), label: "Отдача")
            }

            if let server = store.selectedServer {
                HStack(spacing: 9) {
                    Image(systemName: "server.rack").foregroundStyle(seed)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(server.name).font(.system(size: 11, weight: .semibold)).lineLimit(1)
                        Text("\(server.type.rawValue) · \(server.host):\(server.port)")
                            .font(.system(size: 9)).foregroundStyle(.secondary).lineLimit(1)
                    }
                    Spacer()
                    Button(server.ping.map { $0 > 0 ? "\($0) ms" : "Ping" } ?? "Ping") {
                        store.testLatency(server.id)
                    }
                    .font(.system(size: 10, weight: .semibold))
                    .buttonStyle(.plain)
                    .padding(.horizontal, 10).frame(height: 28)
                    .background(seed.opacity(0.16), in: Capsule())
                }
                .padding(.horizontal, 12)
                .frame(height: 48)
                .compactCard()
            }
            Spacer(minLength: 0)
        }
        .onReceive(Timer.publish(every: 1, on: .main, in: .common).autoconnect()) { now = $0 }
        .onAppear {
            withAnimation(.spring(response: 0.55, dampingFraction: 0.72)) { appeared = true }
        }
        .onChange(of: store.state) { oldValue, newValue in
            guard !oldValue.connected, newValue.connected else { return }
            waveVisible = true
            waveExpanded = false
            Task {
                await Task.yield()
                withAnimation(.easeOut(duration: 0.75)) { waveExpanded = true }
                try? await Task.sleep(for: .milliseconds(800))
                waveVisible = false
            }
        }
    }

    private var connectionIcon: String {
        switch store.state {
        case .connecting, .disconnecting: "ellipsis"
        case .connected: "checkmark"
        case .failed: "arrow.clockwise"
        case .disconnected: "power"
        }
    }
    private var isTransitioning: Bool {
        if case .connecting = store.state { return true }
        if case .disconnecting = store.state { return true }
        return false
    }
    private var duration: String {
        guard case let .connected(start) = store.state else { return "00:00" }
        let seconds = Int(now.timeIntervalSince(start))
        return String(format: "%02d:%02d", seconds / 60, seconds % 60)
    }
    private func rate(_ value: Double) -> String {
        value > 1_000_000 ? String(format: "%.1fM", value / 1_000_000) : String(format: "%.0fK", value / 1_000)
    }
}

struct TinyMetric: View {
    let icon: String
    let value: String
    let label: String
    var body: some View {
        VStack(spacing: 3) {
            HStack(spacing: 4) {
                Image(systemName: icon).font(.system(size: 9))
                Text(value).font(.system(size: 11, weight: .bold, design: .rounded))
            }
            Text(label).font(.system(size: 8)).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity).frame(height: 45)
        .compactCard()
    }
}

struct CompactProfilesView: View {
    @EnvironmentObject private var store: AppStore
    let seed: Color
    @State private var search = ""
    @State private var sort = ProfileSort.name
    @State private var latencyMethod = LatencyMethod.tcp
    @State private var showImport = false
    @State private var showSubscription = false
    @State private var editServer: ServerProfile?

    private var filtered: [ServerProfile] {
        let result = search.isEmpty ? store.servers : store.servers.filter {
            $0.name.localizedCaseInsensitiveContains(search) || $0.host.localizedCaseInsensitiveContains(search)
        }
        return result.sorted {
            switch sort {
            case .name: $0.name.localizedStandardCompare($1.name) == .orderedAscending
            case .latency: ($0.ping ?? .max) < ($1.ping ?? .max)
            }
        }
    }

    var body: some View {
        VStack(spacing: 8) {
            HStack(spacing: 8) {
                Text("Серверы")
                    .font(.system(size: 13, weight: .bold, design: .rounded))

                Spacer()
                Menu {
                    Button("Ссылка или JSON") { showImport = true }
                    Button("Из буфера") { importClipboard() }
                    Button("QR из изображения") { store.importQRImage() }
                    Button("Подписка") { showSubscription = true }
                    Button("Файл…") { openFiles() }
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 12, weight: .bold))
                        .frame(width: 31, height: 31)
                        .background(seed, in: Circle())
                        .foregroundStyle(.white)
                }
                .menuStyle(.borderlessButton).fixedSize()
            }

            profileTools

            ScrollView {
                LazyVStack(spacing: 8) {
                    subscriptionSection
                    profileSection
                }
                .padding(.bottom, 4)
            }
            .scrollIndicators(.hidden)
        }
        .sheet(isPresented: $showImport) { ImportPreviewSheet(seed: seed) }
        .sheet(isPresented: $showSubscription) { CompactSubscriptionSheet(seed: seed) }
        .sheet(item: $editServer) { CompactEditorSheet(server: $0, seed: seed) }
    }

    private var profileSection: some View {
        VStack(spacing: 7) {
            HStack {
                Text("Добавленные вручную")
                    .font(.system(size: 11, weight: .bold))
                Text("\(manualProfiles.count)")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(.secondary)
                Spacer()
            }
            if manualProfiles.isEmpty {
                VStack(spacing: 5) {
                    Image(systemName: "square.stack.3d.up.slash").foregroundStyle(.secondary)
                    Text("Ручных профилей нет").font(.system(size: 10, weight: .semibold))
                }
                .frame(maxWidth: .infinity).frame(height: 72)
                .compactCard()
            } else {
                LazyVStack(spacing: 5) {
                    ForEach(manualProfiles) { server in
                        CompactServerRow(server: server, seed: seed, editServer: $editServer)
                    }
                }
            }
        }
        .padding(.top, 12)
    }

    private var subscriptionSection: some View {
        VStack(spacing: 7) {
            HStack {
                Text("Подписки")
                    .font(.system(size: 11, weight: .bold))
                Text("\(store.subscriptions.count)")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Обновить все") { Task { await store.updateAllSubscriptions() } }
                    .font(.system(size: 10, weight: .semibold))
            }
            if store.subscriptions.isEmpty {
                HStack {
                    Image(systemName: "link.badge.plus").foregroundStyle(seed)
                    Text("Добавьте URL подписки").font(.system(size: 10))
                    Spacer()
                    Button("Добавить") { showSubscription = true }
                        .font(.system(size: 9, weight: .semibold))
                }
                .padding(10).compactCard()
            } else {
                LazyVStack(spacing: 6) {
                    ForEach(store.subscriptions) { subscription in
                        VStack(spacing: 5) {
                            CompactSubscriptionRow(subscription: subscription, seed: seed)
                            let profiles = profiles(for: subscription)
                            if profiles.isEmpty {
                                Text("В этой подписке пока нет серверов")
                                    .font(.system(size: 9))
                                    .foregroundStyle(.secondary)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(.horizontal, 12)
                            } else {
                                ForEach(profiles) { server in
                                    CompactServerRow(server: server, seed: seed, editServer: $editServer)
                                        .padding(.leading, 12)
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    private var manualProfiles: [ServerProfile] {
        filtered.filter { $0.subscriptionID == nil }
    }

    private func profiles(for subscription: Subscription) -> [ServerProfile] {
        filtered.filter { $0.subscriptionID == subscription.id }
    }

    private var profileTools: some View {
        HStack(spacing: 7) {
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass").font(.system(size: 10)).foregroundStyle(.secondary)
                TextField("Поиск по всем серверам", text: $search).textFieldStyle(.plain).font(.system(size: 11))
            }
            .padding(.horizontal, 10).frame(height: 30).compactCard()

            Menu(sort.rawValue) {
                ForEach(ProfileSort.allCases) { item in Button(item.rawValue) { sort = item } }
            }
            .font(.system(size: 10)).frame(width: 66)
        }
    }

    private func importClipboard() {
        let count = store.addProfiles(from: NSPasteboard.general.string(forType: .string) ?? "")
        store.showToast(count > 0 ? "Добавлено: \(count)" : "Не распознано")
    }

    private func openFiles() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.allowedContentTypes = [.plainText, .json, .data]
        if panel.runModal() == .OK { store.importFiles(panel.urls) }
    }
}

struct CompactServerRow: View {
    @EnvironmentObject private var store: AppStore
    let server: ServerProfile
    let seed: Color
    @Binding var editServer: ServerProfile?
    @State private var confirmDelete = false

    var body: some View {
        Button {
            store.selectedServerID = server.id
            store.save()
        } label: {
            HStack(spacing: 9) {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 5) {
                        Text(server.name).font(.system(size: 11, weight: .semibold)).lineLimit(1)
                        if server.favorite { Image(systemName: "star.fill").font(.system(size: 7)).foregroundStyle(.yellow) }
                    }
                    Text("\(server.host):\(server.port)")
                        .font(.system(size: 9)).foregroundStyle(.secondary).lineLimit(1)
                }
                Spacer()
                latency
                Menu {
                    Button("Проверить задержку") { store.testLatency(server.id) }
                    Button("Редактировать") { editServer = server }
                    Button("Дублировать") { store.duplicate(server) }
                    Menu("Экспорт") {
                        Button("Обычная ссылка") { store.exportProfile(server, format: "Native") }
                        Button("palazikVPN") { store.exportProfile(server, format: "palazikVPN") }
                        Button("JSON") { store.exportProfile(server, format: "JSON") }
                        Button("QR-код…") { store.saveProfileQR(server) }
                    }
                    Button(server.favorite ? "Убрать из избранного" : "В избранное") {
                        if let index = store.servers.firstIndex(where: { $0.id == server.id }) {
                            store.servers[index].favorite.toggle(); store.save()
                        }
                    }
                    Divider()
                    Button("Удалить", role: .destructive) { confirmDelete = true }
                } label: {
                    Image(systemName: "ellipsis").frame(width: 24, height: 30)
                }
                .menuStyle(.borderlessButton).fixedSize()
            }
            .padding(.horizontal, 9).frame(height: 48)
            .background(store.selectedServerID == server.id ? seed.opacity(0.16) : .white.opacity(0.045), in: RoundedRectangle(cornerRadius: 14))
        }
        .buttonStyle(.plain)
        .confirmationDialog(
            "Удалить «\(server.name)»?",
            isPresented: $confirmDelete,
            titleVisibility: .visible
        ) {
            Button("Подтверждаю", role: .destructive) { store.deleteServer(server) }
            Button("Отмена", role: .cancel) {}
        }
    }

    @ViewBuilder private var latency: some View {
        if server.ping == -1 {
            ProgressView().controlSize(.small).frame(width: 42)
        } else {
            Text(server.ping.map { $0 > 0 ? "\($0) ms" : "—" } ?? "")
                .font(.system(size: 9, weight: .semibold, design: .monospaced))
                .foregroundStyle((server.ping ?? 999) < 150 ? .green : .secondary)
                .frame(width: 44, alignment: .trailing)
        }
    }
}

struct CompactSubscriptionRow: View {
    @EnvironmentObject private var store: AppStore
    let subscription: Subscription
    let seed: Color
    @State private var confirmDelete = false
    var details: SubscriptionDetails? { store.subscriptionDetails[subscription.id] }

    var body: some View {
        VStack(spacing: 7) {
            HStack {
                SubscriptionLogo(urlString: details?.iconURL, seed: seed)
                VStack(alignment: .leading, spacing: 1) {
                    Text(subscription.name).font(.system(size: 11, weight: .semibold))
                    Text(expiryText)
                        .font(.system(size: 8)).foregroundStyle(.secondary)
                }
                Spacer()
                Button { Task { await store.refreshSubscriptionEnhanced(subscription) } } label: {
                    Image(systemName: "arrow.clockwise")
                }.buttonStyle(.plain)
                Button { confirmDelete = true } label: {
                    Image(systemName: "trash").foregroundStyle(.red.opacity(0.75))
                }.buttonStyle(.plain)
            }
            if let total = details?.total, total > 0 {
                let used = (details?.upload ?? 0) + (details?.download ?? 0)
                ProgressView(value: min(1, Double(used) / Double(total))).tint(seed)
                HStack {
                    Text("\(formatBytes(used)) / \(formatBytes(total))")
                    Spacer()
                }.font(.system(size: 8)).foregroundStyle(.secondary)
            }
        }
        .padding(10).compactCard()
        .confirmationDialog(
            "Удалить подписку «\(subscription.name)» и все её серверы?",
            isPresented: $confirmDelete,
            titleVisibility: .visible
        ) {
            Button("Подтверждаю", role: .destructive) { store.deleteSubscription(subscription) }
            Button("Отмена", role: .cancel) {}
        }
    }

    private var expiryText: String {
        guard let expire = details?.expire else { return "Без срока окончания" }
        let calendar = Calendar.current
        let days = calendar.dateComponents(
            [.day],
            from: calendar.startOfDay(for: Date()),
            to: calendar.startOfDay(for: expire)
        ).day ?? 0
        let date = expire.formatted(.dateTime.day().month(.twoDigits).year())
        if days < 0 { return "До окончания подписки: \(date) (истекла)" }
        return "До окончания подписки: \(date) (\(days) \(dayWord(days)))"
    }

    private func dayWord(_ value: Int) -> String {
        let mod100 = value % 100
        let mod10 = value % 10
        if mod100 >= 11 && mod100 <= 14 { return "дней" }
        if mod10 == 1 { return "день" }
        if mod10 >= 2 && mod10 <= 4 { return "дня" }
        return "дней"
    }

    private func formatBytes(_ value: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: value, countStyle: .binary)
    }
}

struct SubscriptionLogo: View {
    let urlString: String?
    let seed: Color

    var body: some View {
        AsyncImage(url: urlString.flatMap(URL.init(string:))) { phase in
            switch phase {
            case .success(let image):
                image.resizable().scaledToFill()
            default:
                Image(systemName: "link")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(seed)
            }
        }
        .frame(width: 34, height: 34)
        .background(seed.opacity(0.12), in: RoundedRectangle(cornerRadius: 10))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }
}

struct CompactSettingsView: View {
    @EnvironmentObject private var store: AppStore
    let seed: Color
    @State private var section = "Вид"
    @Namespace private var settingsSelection
    private let sections = ["Вид", "Маршруты", "DNS", "Авто", "Профили", "Данные", "О приложении"]

    var body: some View {
        HStack(alignment: .top, spacing: 9) {
            ScrollView {
                VStack(spacing: 3) {
                    ForEach(sections, id: \.self) { item in
                        Button {
                            withAnimation(.spring(response: 0.48, dampingFraction: 0.76)) { section = item }
                        } label: {
                            ZStack {
                                if section == item {
                                    RoundedRectangle(cornerRadius: 11)
                                        .fill(seed.opacity(0.22))
                                        .matchedGeometryEffect(id: "settings-section", in: settingsSelection)
                                }
                                HStack {
                                    Image(systemName: settingsIcon(item)).frame(width: 16)
                                    Text(item).lineLimit(1)
                                    Spacer()
                                }
                                .padding(.horizontal, 9)
                            }
                            .font(.system(size: 10, weight: section == item ? .semibold : .regular))
                            .frame(height: 44)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .frame(width: 118)
            .scrollIndicators(.hidden)

            ScrollView {
                VStack(spacing: 7) {
                    switch section {
                    case "Вид": AppearanceSettings(seed: seed)
                    case "Маршруты": RoutingSettings()
                    case "DNS": DNSSettings()
                    case "Авто": AutomationSettings()
                    case "Профили": WorkspaceSettings(seed: seed)
                    case "Данные": DataSettings()
                    default: AboutSettings(seed: seed)
                    }
                }
                .padding(9)
                .compactCard(radius: 18)
            }
            .scrollIndicators(.hidden)
            .id(section)
            .transition(.opacity)
        }
    }

    private func settingsIcon(_ item: String) -> String {
        switch item {
        case "Вид": "paintpalette"
        case "Маршруты": "point.3.connected.trianglepath.dotted"
        case "DNS": "network"
        case "Авто": "clock.arrow.circlepath"
        case "Профили": "person.2"
        case "Данные": "externaldrive"
        default: "info.circle"
        }
    }
}

struct AppearanceSettings: View {
    let seed: Color
    @AppStorage("SeedColor") private var seedName = SeedColor.purple.rawValue

    var body: some View {
        SettingHeader("Оформление", icon: "paintpalette.fill")
        VStack(alignment: .leading, spacing: 7) {
            Text("Тема интерфейса").font(.system(size: 10, weight: .semibold))
            HStack(spacing: 10) {
                ForEach(SeedColor.allCases) { item in
                    Button { seedName = item.rawValue } label: {
                        ZStack {
                            Circle().fill(item.color).frame(width: 25, height: 25)
                            if seedName == item.rawValue {
                                Image(systemName: "checkmark")
                                    .font(.system(size: 9, weight: .black))
                                    .foregroundStyle(Color(hex: "211F26"))
                            }
                        }
                    }
                    .buttonStyle(.plain)
                    .help(item.rawValue)
                }
                Spacer()
            }
        }.compactSettingBox()
        .onAppear {
            if SeedColor(rawValue: seedName) == nil { seedName = SeedColor.purple.rawValue }
        }
    }
}

struct RoutingSettings: View {
    @EnvironmentObject private var store: AppStore
    @AppStorage("FakeDNS") private var fakeDNS = false
    @AppStorage("AdBlock") private var adBlock = false
    @AppStorage("ChinaBypass") private var chinaBypass = false
    var body: some View {
        SettingHeader("Маршрутизация", icon: "arrow.triangle.branch")
        EnumPickerRow(title: "Режим", selection: $store.settings.routeMode)
        CompactToggle(title: "Обход LAN", subtitle: "Локальные устройства напрямую", value: $store.settings.bypassLAN)
        CompactToggle(title: "Kill switch", subtitle: "Блокировать утечки при обрыве", value: $store.settings.killSwitch)
        CompactToggle(title: "IPv6", subtitle: "Разрешить IPv6 внутри туннеля", value: $store.settings.ipv6)
        CompactToggle(title: "FakeDNS", subtitle: "Подмена DNS для прозрачной маршрутизации", value: $fakeDNS)
        CompactToggle(title: "Блокировка рекламы", subtitle: "Правила geosite:category-ads-all", value: $adBlock)
        CompactToggle(title: "Обход Китая", subtitle: "geoip:cn и geosite:cn напрямую", value: $chinaBypass)
        TokenCompactEditor(title: "Напрямую", values: $store.settings.directDomains)
        TokenCompactEditor(title: "Заблокировано", values: $store.settings.blockedDomains)
        TokenCompactEditor(title: "Приложения мимо VPN", values: $store.settings.excludedApps)
    }
}

struct DNSSettings: View {
    @EnvironmentObject private var store: AppStore
    @AppStorage("RemoteDNS") private var remoteDNS = "https://1.1.1.1/dns-query"
    @AppStorage("DirectDNS") private var directDNS = "system"
    @AppStorage("GeoIPURL") private var geoIPURL = ""
    @AppStorage("GeoSiteURL") private var geoSiteURL = ""
    var body: some View {
        SettingHeader("DNS и Geo", icon: "network")
        CompactToggle(title: "Защищённый DNS", subtitle: "DNS-запросы через VPN", value: $store.settings.dnsEnabled)
        CompactTextRow(title: "VPN DNS", text: $store.settings.dnsServer)
        CompactTextRow(title: "Remote DNS", text: $remoteDNS)
        CompactTextRow(title: "Direct DNS", text: $directDNS)
        CompactTextRow(title: "geoip.dat URL", text: $geoIPURL)
        CompactTextRow(title: "geosite.dat URL", text: $geoSiteURL)
        HStack {
            Spacer()
            Button("Обновить Geo-файлы") {
                Task { await store.updateGeoFiles(geoIPURL: geoIPURL, geoSiteURL: geoSiteURL) }
            }
            .font(.system(size: 9, weight: .semibold))
        }
    }
}

struct AutomationSettings: View {
    @EnvironmentObject private var store: AppStore
    @AppStorage("SubscriptionInterval") private var interval = "24 часа"
    @AppStorage("SubscriptionUserAgent") private var userAgent = "Happ/2.18.1/macOSarm64"
    @AppStorage("LatencyMethod") private var latency = LatencyMethod.tcp.rawValue
    var body: some View {
        SettingHeader("Автоматизация", icon: "clock.arrow.circlepath")
        EnumPickerRow(title: "Подключение", selection: $store.settings.mode)
        CompactToggle(title: "Автоподключение", subtitle: "Подключаться после запуска", value: $store.settings.autoConnect)
        CompactToggle(title: "Переподключение", subtitle: "Восстанавливать туннель", value: $store.settings.autoReconnect)
        ToggleRowWithAction(
            title: "Запуск с macOS",
            value: store.settings.launchAtLogin,
            action: { store.setLaunchAtLogin($0) }
        )
        CompactPicker(title: "Обновление подписок", selection: $interval, values: ["Выкл.", "1 час", "6 часов", "12 часов", "24 часа", "7 дней"])
        CompactPicker(title: "Проверка задержки", selection: $latency, values: LatencyMethod.allCases.map(\.rawValue))
        CompactTextRow(title: "User-Agent", text: $userAgent)
    }
}

struct WorkspaceSettings: View {
    @EnvironmentObject private var store: AppStore
    let seed: Color
    @State private var workspaceToDelete: VPNWorkspace?
    var body: some View {
        SettingHeader("Профили пользователей", icon: "person.2.fill")
        ForEach(store.workspaces) { workspace in
            HStack {
                Circle().fill(seed).frame(width: 10, height: 10)
                Text(workspace.name).font(.system(size: 10, weight: .semibold))
                Spacer()
                if workspace.id == store.activeWorkspaceID { Text("Активен").font(.system(size: 8)).foregroundStyle(seed) }
                else { Button("Перейти") { store.switchWorkspace(workspace.id) }.font(.system(size: 9)) }
                if store.workspaces.count > 1 {
                    Button { workspaceToDelete = workspace } label: { Image(systemName: "trash") }
                        .buttonStyle(.plain).foregroundStyle(.red.opacity(0.7))
                }
            }.compactSettingBox()
        }
        Text("Каждый профиль хранит собственные конфигурации, подписки и активный сервер.")
            .font(.system(size: 9)).foregroundStyle(.secondary)
        .confirmationDialog(
            "Удалить пользовательский профиль?",
            isPresented: Binding(
                get: { workspaceToDelete != nil },
                set: { if !$0 { workspaceToDelete = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Подтверждаю", role: .destructive) {
                if let workspaceToDelete { store.deleteWorkspace(workspaceToDelete.id) }
                workspaceToDelete = nil
            }
            Button("Отмена", role: .cancel) { workspaceToDelete = nil }
        } message: {
            Text(workspaceToDelete?.name ?? "")
        }
    }
}

struct DataSettings: View {
    @EnvironmentObject private var store: AppStore
    @State private var confirmClearLogs = false
    var body: some View {
        SettingHeader("Данные и диагностика", icon: "externaldrive.fill")
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 6) {
                Button("Создать backup") { saveBackup() }
                    .frame(width: 120)
                Button("Восстановить") { restoreBackup() }
                    .frame(width: 120)
                Spacer()
            }
            HStack(spacing: 6) {
                Button("Копировать лог") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(store.logs.joined(separator: "\n"), forType: .string)
                }
                .frame(width: 120)
                Button("Сохранить лог") { saveLog() }
                    .frame(width: 120)
                Button("Очистить") { confirmClearLogs = true }
                    .frame(width: 80)
                Spacer()
            }
        }
        .font(.system(size: 9))
        ScrollView {
            Text(store.logs.isEmpty ? "Логи появятся после подключения." : store.logs.joined(separator: "\n"))
                .font(.system(size: 8, design: .monospaced))
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(8)
        }
        .frame(height: 150)
        .background(.black.opacity(0.22), in: RoundedRectangle(cornerRadius: 10))
        .confirmationDialog(
            "Очистить журнал диагностики?",
            isPresented: $confirmClearLogs,
            titleVisibility: .visible
        ) {
            Button("Подтверждаю", role: .destructive) { store.logs.removeAll() }
            Button("Отмена", role: .cancel) {}
        }
    }

    private func saveBackup() {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "materialTun-backup.json"
        panel.allowedContentTypes = [.json]
        if panel.runModal() == .OK, let url = panel.url {
            do { try store.backup(to: url); store.showToast("Резервная копия создана") }
            catch { store.showToast(error.localizedDescription) }
        }
    }
    private func restoreBackup() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        if panel.runModal() == .OK, let url = panel.url {
            do { try store.restoreBackup(from: url); store.showToast("Данные восстановлены") }
            catch { store.showToast("Некорректная копия") }
        }
    }
    private func saveLog() {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "materialTun.log"
        panel.allowedContentTypes = [.plainText]
        if panel.runModal() == .OK, let url = panel.url {
            try? store.logs.joined(separator: "\n").write(to: url, atomically: true, encoding: .utf8)
        }
    }
}

struct AboutSettings: View {
    @EnvironmentObject private var store: AppStore
    let seed: Color
    var body: some View {
        VStack(spacing: 9) {
            Image(systemName: "shield.lefthalf.filled")
                .font(.system(size: 34)).foregroundStyle(seed)
            Text("materialTun").font(.system(size: 18, weight: .bold, design: .rounded))
            Text("Компактный клиент Xray + sing-box для macOS")
                .font(.system(size: 9)).foregroundStyle(.secondary)
            Button("Проверить обновления") { Task { await store.checkForUpdates() } }
                .font(.system(size: 10, weight: .semibold))
            if !store.updateStatus.isEmpty {
                Text(store.updateStatus).font(.system(size: 9)).foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 250)
    }
}

struct ImportPreviewSheet: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.dismiss) private var dismiss
    let seed: Color
    @State private var text = ""
    private var parsed: [ServerProfile] { ConfigParser.parseMany(text) }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Импорт").font(.system(size: 18, weight: .bold, design: .rounded))
            TextEditor(text: $text)
                .font(.system(size: 10, design: .monospaced))
                .scrollContentBackground(.hidden)
                .padding(8).frame(height: 115)
                .background(.black.opacity(0.18), in: RoundedRectangle(cornerRadius: 12))
            if let first = parsed.first {
                VStack(alignment: .leading, spacing: 4) {
                    Label("\(parsed.count) конфигураций", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
                    Text("\(first.type.rawValue) · \(first.host):\(first.port)")
                    Text(first.rawURI.contains("security=reality") ? "REALITY" : "Параметры ссылки проверены")
                        .foregroundStyle(.secondary)
                }.font(.system(size: 10)).padding(9).compactCard()
            } else if !text.isEmpty {
                Label("Формат пока не распознан", systemImage: "exclamationmark.triangle.fill")
                    .font(.system(size: 10)).foregroundStyle(.orange)
            }
            HStack {
                Button("Из буфера") { text = NSPasteboard.general.string(forType: .string) ?? "" }
                Spacer()
                Button("Отмена") { dismiss() }
                Button("Импортировать") {
                    let count = store.addProfiles(from: text)
                    if count > 0 { dismiss() }
                }
                .buttonStyle(.borderedProminent).tint(seed).disabled(parsed.isEmpty)
            }.font(.system(size: 10))
        }
        .padding(18).frame(width: 430)
    }
}

struct CompactEditorSheet: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.dismiss) private var dismiss
    @State var server: ServerProfile
    let seed: Color
    @State private var options = ProfileOptions()

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            Text("Профиль").font(.system(size: 18, weight: .bold))
            CompactTextRow(title: "Название", text: $server.name)
            CompactTextRow(title: "Сервер", text: $server.host)
            HStack {
                Text("Порт").font(.system(size: 10))
                Spacer()
                TextField("", value: $server.port, format: .number).frame(width: 90)
                    .textFieldStyle(.plain)
            }.compactSettingBox()
            CompactToggle(title: "allowInsecure", subtitle: "Не проверять TLS-сертификат", value: $options.allowInsecure)
            CompactToggle(title: "Mux", subtitle: "Мультиплексирование соединений", value: $options.mux)
            CompactToggle(title: "TLS fragmentation", subtitle: "Anti-DPI фрагментация ClientHello", value: $options.tlsFragment)
            if options.tlsFragment {
                CompactTextRow(title: "Размер пакета", text: $options.fragmentLength)
                CompactTextRow(title: "Интервал", text: $options.fragmentInterval)
            }
            SecureField("Секреты скрыты · изменяйте исходную ссылку при необходимости", text: .constant(""))
                .textFieldStyle(.plain)
                .font(.system(size: 9))
                .padding(8)
                .background(Color(hex: "2B2930"), in: RoundedRectangle(cornerRadius: 10))
            HStack {
                Spacer()
                Button("Отмена") { dismiss() }
                Button("Сохранить") {
                    if let index = store.servers.firstIndex(where: { $0.id == server.id }) { store.servers[index] = server }
                    store.profileOptions[server.id] = options
                    store.save(); dismiss()
                }.buttonStyle(.borderedProminent).tint(seed)
            }.font(.system(size: 10))
        }
        .padding(18).frame(width: 420)
        .onAppear { options = store.profileOptions[server.id] ?? .init() }
    }
}

struct CompactSubscriptionSheet: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.dismiss) private var dismiss
    let seed: Color
    @State private var url = ""
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Новая подписка").font(.system(size: 18, weight: .bold))
            Text("Название определится автоматически из ответа провайдера.")
                .font(.system(size: 9))
                .foregroundStyle(.secondary)
            CompactTextRow(title: "URL", text: $url)
            HStack {
                Spacer()
                Button("Отмена") { dismiss() }
                Button("Добавить") {
                    Task { await store.addSubscription(name: "", url: url); dismiss() }
                }.buttonStyle(.borderedProminent).tint(seed).disabled(url.isEmpty)
            }.font(.system(size: 10))
        }.padding(18).frame(width: 420)
    }
}

struct WorkspaceSheet: View {
    @EnvironmentObject private var store: AppStore
    let seed: Color
    let onClose: () -> Void
    @State private var name = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Профили пользователей").font(.system(size: 17, weight: .bold))
                Spacer()
                Button { onClose() } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 11, weight: .bold))
                        .frame(width: 28, height: 28)
                        .background(Color(hex: "2B2930"), in: Circle())
                }
                .buttonStyle(.plain)
            }
            ForEach(store.workspaces) { workspace in
                Button {
                    store.switchWorkspace(workspace.id); onClose()
                } label: {
                    HStack {
                        Text(workspace.name).font(.system(size: 11, weight: .semibold))
                        Spacer()
                        Text("\(workspace.servers.count)").font(.system(size: 9)).foregroundStyle(.secondary)
                        if store.activeWorkspaceID == workspace.id { Image(systemName: "checkmark").foregroundStyle(seed) }
                    }.padding(9).compactCard()
                }.buttonStyle(.plain)
            }
            Divider()
            TextField("Новый профиль", text: $name)
                .textFieldStyle(.plain)
                .padding(8)
                .background(Color(hex: "2B2930"), in: RoundedRectangle(cornerRadius: 10))
            HStack {
                Spacer()
                Button("Создать") {
                    store.createWorkspace(name: name, colorHex: "6750A4"); onClose()
                }.buttonStyle(.borderedProminent).tint(seed)
            }
        }
        .padding(16)
        .frame(width: 360)
        .background(Color(hex: "211F26"), in: RoundedRectangle(cornerRadius: 22))
        .shadow(color: .black.opacity(0.38), radius: 30, y: 16)
    }
}

struct OnboardingView: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.dismiss) private var dismiss
    let seed: Color
    @State private var page = 0
    var body: some View {
        VStack(spacing: 14) {
            Spacer()
            Image(systemName: page == 0 ? "shield.lefthalf.filled" : page == 1 ? "square.and.arrow.down" : "lock.shield")
                .font(.system(size: 48)).foregroundStyle(seed)
                .symbolEffect(.bounce, value: page)
            Text(["Добро пожаловать", "Добавьте конфигурацию", "Разрешите TUN"][page])
                .font(.system(size: 22, weight: .bold, design: .rounded))
            Text([
                "Компактный VPN-клиент для Xray и sing-box.",
                "Вставьте ссылку, откройте файл, подписку или QR-код.",
                "Для полного VPN macOS запросит пароль администратора. Системный прокси работает без него."
            ][page])
            .font(.system(size: 11)).foregroundStyle(.secondary)
            .multilineTextAlignment(.center).frame(width: 340)
            Spacer()
            HStack {
                if page > 0 { Button("Назад") { page -= 1 } }
                Spacer()
                Button(page == 2 ? "Начать" : "Далее") {
                    if page < 2 { page += 1 }
                    else { store.completeOnboarding(); dismiss() }
                }.buttonStyle(.borderedProminent).tint(seed)
            }.font(.system(size: 11))
        }.padding(22).frame(width: 430, height: 330)
    }
}

struct CompactEmpty: View {
    let icon: String
    let title: String
    let subtitle: String
    var body: some View {
        VStack(spacing: 7) {
            Spacer()
            Image(systemName: icon).font(.system(size: 28)).foregroundStyle(.secondary)
            Text(title).font(.system(size: 12, weight: .semibold))
            Text(subtitle).font(.system(size: 9)).foregroundStyle(.secondary)
            Spacer()
        }.frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct SettingHeader: View {
    let title: String
    let icon: String
    init(_ title: String, icon: String) { self.title = title; self.icon = icon }
    var body: some View {
        HStack {
            Image(systemName: icon)
            Text(title).font(.system(size: 13, weight: .bold, design: .rounded))
            Spacer()
        }.padding(.bottom, 2)
    }
}

struct CompactToggle: View {
    let title: String
    let subtitle: String
    @Binding var value: Bool
    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(.system(size: 10, weight: .medium))
                Text(subtitle).font(.system(size: 8)).foregroundStyle(.secondary)
            }
            Spacer()
            Toggle("", isOn: $value).labelsHidden().toggleStyle(.switch).controlSize(.mini)
        }.compactSettingBox()
    }
}

struct ToggleRowWithAction: View {
    let title: String
    let value: Bool
    let action: (Bool) -> Void
    var body: some View {
        HStack {
            Text(title).font(.system(size: 10, weight: .medium))
            Spacer()
            Toggle("", isOn: Binding(get: { value }, set: { newValue in action(newValue) }))
                .labelsHidden().toggleStyle(.switch).controlSize(.mini)
        }.compactSettingBox()
    }
}

struct CompactPicker: View {
    let title: String
    @Binding var selection: String
    let values: [String]
    var body: some View {
        HStack {
            Text(title).font(.system(size: 10, weight: .medium))
            Spacer()
            Picker("", selection: $selection) {
                ForEach(values, id: \.self) { Text($0).tag($0) }
            }.labelsHidden().frame(width: 150).controlSize(.small)
        }.compactSettingBox()
    }
}

struct EnumPickerRow<T: Hashable & Identifiable & RawRepresentable>: View where T.RawValue == String {
    let title: String
    @Binding var selection: T
    var values: [T] {
        if T.self == RouteMode.self { return RouteMode.allCases as! [T] }
        if T.self == ConnectionMode.self { return ConnectionMode.allCases as! [T] }
        return []
    }
    var body: some View {
        HStack {
            Text(title).font(.system(size: 10, weight: .medium))
            Spacer()
            Picker("", selection: $selection) {
                ForEach(values) { Text($0.rawValue).tag($0) }
            }.labelsHidden().frame(width: 165).controlSize(.small)
        }.compactSettingBox()
    }
}

struct CompactTextRow: View {
    let title: String
    @Binding var text: String
    var body: some View {
        HStack {
            Text(title).font(.system(size: 10, weight: .medium))
            Spacer()
            TextField("", text: $text)
                .textFieldStyle(.plain)
                .font(.system(size: 9)).frame(width: 190)
        }.compactSettingBox()
    }
}

struct TokenCompactEditor: View {
    let title: String
    @Binding var values: [String]
    @State private var text = ""
    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                Text(title).font(.system(size: 10, weight: .medium))
                Spacer()
                Text("\(values.count)").font(.system(size: 8)).foregroundStyle(.secondary)
            }
            HStack {
                TextField("domain.com", text: $text)
                    .textFieldStyle(.plain)
                    .font(.system(size: 9))
                    .onSubmit(add)
                Button { add() } label: { Image(systemName: "plus") }.buttonStyle(.plain)
            }
            if !values.isEmpty {
                Text(values.prefix(4).joined(separator: "  ·  ") + (values.count > 4 ? "  +\(values.count - 4)" : ""))
                    .font(.system(size: 8)).foregroundStyle(.secondary).lineLimit(1)
            }
        }.compactSettingBox()
    }
    private func add() {
        let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty, !values.contains(value) else { return }
        values.append(value); text = ""
    }
}

struct CompactPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.92 : 1)
            .animation(.spring(response: 0.25, dampingFraction: 0.64), value: configuration.isPressed)
    }
}

extension View {
    func compactCard(radius: CGFloat = 14) -> some View {
        self.background(Color(hex: "211F26"), in: RoundedRectangle(cornerRadius: radius, style: .continuous))
    }

    func compactSettingBox() -> some View {
        self.padding(.horizontal, 9).padding(.vertical, 7)
            .background(Color(hex: "2B2930"), in: RoundedRectangle(cornerRadius: 11))
    }
}

struct CompactMenuBarView: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.openWindow) private var openWindow
    @State private var now = Date()
    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack {
                Circle().fill(store.state.connected ? .green : .gray).frame(width: 8, height: 8)
                Text(store.state.title).font(.system(size: 12, weight: .bold))
                Spacer()
                if case let .connected(start) = store.state {
                    Text(duration(from: start)).font(.system(size: 9, design: .monospaced)).foregroundStyle(.secondary)
                }
            }
            if let server = store.selectedServer {
                Text(server.name).font(.system(size: 11, weight: .semibold))
                Text("\(server.type.rawValue) · ↓ \(rate(store.downRate))  ↑ \(rate(store.upRate))")
                    .font(.system(size: 9)).foregroundStyle(.secondary)
            }
            Divider()
            Button(store.state.connected ? "Отключиться" : "Подключиться") { store.toggleConnection() }
            Menu("Сервер") {
                ForEach(store.servers) { server in
                    Button(server.name) { store.selectedServerID = server.id; store.save() }
                }
            }
            Menu("Профиль") {
                ForEach(store.workspaces) { workspace in
                    Button(workspace.name) { store.switchWorkspace(workspace.id) }
                }
            }
            Divider()
            Button("Открыть") { NSApp.activate(ignoringOtherApps: true); openWindow(id: "main") }
            Button("Завершить") { NSApp.terminate(nil) }
        }
        .padding(11).frame(width: 240)
        .onReceive(Timer.publish(every: 1, on: .main, in: .common).autoconnect()) { now = $0 }
    }
    private func duration(from start: Date) -> String {
        let seconds = Int(now.timeIntervalSince(start))
        return String(format: "%02d:%02d", seconds / 60, seconds % 60)
    }
    private func rate(_ value: Double) -> String {
        value > 1_000_000 ? String(format: "%.1fM", value / 1_000_000) : String(format: "%.0fK", value / 1_000)
    }
}

final class CompactAppDelegate: NSObject, NSApplicationDelegate {
    private var subscriptionTimer: Timer?

    func applicationDidFinishLaunching(_ notification: Notification) {
        Task { @MainActor in
            let store = AppStore.shared
            store.recoverProxyIfNeeded()
            await store.updateAllSubscriptions()
            if store.settings.autoConnect, store.selectedServer != nil { store.connect() }
            scheduleSubscriptionUpdates()
        }
    }
    func applicationWillTerminate(_ notification: Notification) {
        MainActor.assumeIsolated { AppStore.shared.disconnect(silent: true) }
    }

    @MainActor
    private func scheduleSubscriptionUpdates() {
        let label = UserDefaults.standard.string(forKey: "SubscriptionInterval") ?? "24 часа"
        let seconds: TimeInterval
        switch label {
        case "1 час": seconds = 3600
        case "6 часов": seconds = 21600
        case "12 часов": seconds = 43200
        case "7 дней": seconds = 604800
        case "Выкл.": return
        default: seconds = 86400
        }
        subscriptionTimer = Timer.scheduledTimer(withTimeInterval: seconds, repeats: true) { _ in
            Task { @MainActor in await AppStore.shared.updateAllSubscriptions() }
        }
    }
}

@main
struct materialTunCompactApp: App {
    @NSApplicationDelegateAdaptor(CompactAppDelegate.self) private var appDelegate
    @StateObject private var store = AppStore.shared
    var body: some Scene {
        Window("materialTun", id: "main") {
            CompactRootView().environmentObject(store)
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 640, height: 470)
        .windowResizability(.contentSize)

        MenuBarExtra {
            CompactMenuBarView().environmentObject(store)
        } label: {
            Image(systemName: store.state.connected ? "shield.fill" : "shield")
        }
        .menuBarExtraStyle(.window)
    }
}
