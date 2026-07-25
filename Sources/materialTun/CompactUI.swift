import SwiftUI
import AppKit
import UniformTypeIdentifiers

enum CompactTab: String, CaseIterable {
    case connection = "Home"
    case profiles = "Profiles"
    case settings = "Settings"

    var icon: String {
        switch self {
        case .connection: "power"
        case .profiles: "square.stack.3d.up.fill"
        case .settings: "slider.horizontal.3"
        }
    }

    var title: String { loc(rawValue) }
}

enum SeedColor: String, CaseIterable, Identifiable {
    case purple = "Purple"
    case red = "Red"
    case amber = "Amber"
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
        .environment(\.locale, Locale(identifier: store.language.rawValue))
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
                store.showToast(count > 0 ? loc("Profile imported") : loc("Link not recognized"))
            }
        }
    }

    private var compactTopBar: some View {
        ZStack {
            Text(tab.title)
                .font(.system(size: 13, weight: .bold, design: .rounded))

            HStack(spacing: 10) {
                Button { showWorkspace = true } label: {
                    HStack(spacing: 8) {
                        Circle()
                            .fill(seed)
                            .frame(width: 9, height: 9)
                        Text(store.activeWorkspace.map { loc($0.name) } ?? loc("Personal"))
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
                    Button(loc("Import from Clipboard")) {
                        let text = NSPasteboard.general.string(forType: .string) ?? ""
                        let count = store.addProfiles(from: text)
                        store.showToast(count > 0 ? locf("Added: %d", count) : loc("Nothing found"))
                    }
                    Button(loc("QR Code from Image…")) { store.importQRImage() }
                    Button(loc("Check for Updates")) { Task { await store.checkForUpdates() } }
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
                Text(store.selectedServer?.name ?? loc("Select a server"))
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            HStack(spacing: 8) {
                TinyMetric(icon: "clock", value: duration, label: loc("Session"))
                TinyMetric(icon: "arrow.down", value: rate(store.downRate), label: loc("Download"))
                TinyMetric(icon: "arrow.up", value: rate(store.upRate), label: loc("Upload"))
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
                    Button(server.ping.map { $0 > 0 ? "\($0) ms" : loc("Ping") } ?? loc("Ping")) {
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
                Text(loc("Servers"))
                    .font(.system(size: 13, weight: .bold, design: .rounded))

                Spacer()
                Menu {
                    Button(loc("Link or JSON")) { showImport = true }
                    Button(loc("From Clipboard")) { importClipboard() }
                    Button(loc("QR Code from Image")) { store.importQRImage() }
                    Button(loc("Subscription")) { showSubscription = true }
                    Button(loc("File…")) { openFiles() }
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
                Text(loc("Added Manually"))
                    .font(.system(size: 11, weight: .bold))
                Text("\(manualProfiles.count)")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(.secondary)
                Spacer()
            }
            if manualProfiles.isEmpty {
                VStack(spacing: 5) {
                    Image(systemName: "square.stack.3d.up.slash").foregroundStyle(.secondary)
                    Text(loc("No manual profiles")).font(.system(size: 10, weight: .semibold))
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
                Text(loc("Subscriptions"))
                    .font(.system(size: 11, weight: .bold))
                Text("\(store.subscriptions.count)")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                Button(loc("Update All")) { Task { await store.updateAllSubscriptions() } }
                    .font(.system(size: 10, weight: .semibold))
            }
            if store.subscriptions.isEmpty {
                HStack {
                    Image(systemName: "link.badge.plus").foregroundStyle(seed)
                    Text(loc("Add a subscription URL")).font(.system(size: 10))
                    Spacer()
                    Button(loc("Add")) { showSubscription = true }
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
                                Text(loc("This subscription has no servers yet"))
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
                TextField(loc("Search all servers"), text: $search).textFieldStyle(.plain).font(.system(size: 11))
            }
            .padding(.horizontal, 10).frame(height: 30).compactCard()

            Menu(loc(sort.rawValue)) {
                ForEach(ProfileSort.allCases) { item in Button(loc(item.rawValue)) { sort = item } }
            }
            .font(.system(size: 10)).frame(width: 66)
        }
    }

    private func importClipboard() {
        let count = store.addProfiles(from: NSPasteboard.general.string(forType: .string) ?? "")
        store.showToast(count > 0 ? locf("Added: %d", count) : loc("Not recognized"))
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
                    Button(loc("Test Latency")) { store.testLatency(server.id) }
                    Button(loc("Edit")) { editServer = server }
                    Button(loc("Duplicate")) { store.duplicate(server) }
                    Menu(loc("Export")) {
                        Button(loc("Native Link")) { store.exportProfile(server, format: "Native") }
                        Button("palazikVPN") { store.exportProfile(server, format: "palazikVPN") }
                        Button("JSON") { store.exportProfile(server, format: "JSON") }
                        Button(loc("QR Code…")) { store.saveProfileQR(server) }
                    }
                    Button(loc(server.favorite ? "Remove from Favorites" : "Add to Favorites")) {
                        if let index = store.servers.firstIndex(where: { $0.id == server.id }) {
                            store.servers[index].favorite.toggle(); store.save()
                        }
                    }
                    Divider()
                    Button(loc("Delete"), role: .destructive) { confirmDelete = true }
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
            locf("Delete “%@”?", server.name),
            isPresented: $confirmDelete,
            titleVisibility: .visible
        ) {
            Button(loc("Delete"), role: .destructive) { store.deleteServer(server) }
            Button(loc("Cancel"), role: .cancel) {}
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
            locf("Delete the “%@” subscription and all its servers?", subscription.name),
            isPresented: $confirmDelete,
            titleVisibility: .visible
        ) {
            Button(loc("Delete"), role: .destructive) { store.deleteSubscription(subscription) }
            Button(loc("Cancel"), role: .cancel) {}
        }
    }

    private var expiryText: String {
        guard let expire = details?.expire else { return loc("No expiration date") }
        let calendar = Calendar.current
        let days = calendar.dateComponents(
            [.day],
            from: calendar.startOfDay(for: Date()),
            to: calendar.startOfDay(for: expire)
        ).day ?? 0
        let date = expire.formatted(.dateTime.day().month(.twoDigits).year())
        if days < 0 { return locf("Subscription expired on %@", date) }
        return locf("Subscription expires on %@ (%d %@ remaining)", date, days, dayWord(days))
    }

    private func dayWord(_ value: Int) -> String {
        return loc(value == 1 ? "day" : "days")
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
    @State private var section = "Appearance"
    @Namespace private var settingsSelection
    private let sections = ["Appearance", "Routing", "DNS", "Automation", "Workspaces", "Data", "About"]

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
                                    Text(loc(item)).lineLimit(1)
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
                    case "Appearance": AppearanceSettings(seed: seed)
                    case "Routing": RoutingSettings()
                    case "DNS": DNSSettings()
                    case "Automation": AutomationSettings()
                    case "Workspaces": WorkspaceSettings(seed: seed)
                    case "Data": DataSettings()
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
        case "Appearance": "paintpalette"
        case "Routing": "point.3.connected.trianglepath.dotted"
        case "DNS": "network"
        case "Automation": "clock.arrow.circlepath"
        case "Workspaces": "person.2"
        case "Data": "externaldrive"
        default: "info.circle"
        }
    }
}

struct AppearanceSettings: View {
    @EnvironmentObject private var store: AppStore
    let seed: Color
    @AppStorage("SeedColor") private var seedName = SeedColor.purple.rawValue

    var body: some View {
        SettingHeader("Appearance", icon: "paintpalette.fill")
        HStack {
            Text(loc("Language")).font(.system(size: 10, weight: .medium))
            Spacer()
            Picker("", selection: Binding(
                get: { store.language },
                set: { store.setLanguage($0) }
            )) {
                ForEach(AppLanguage.allCases) { language in
                    Text(language.name).tag(language)
                }
            }
            .labelsHidden()
            .frame(width: 150)
            .controlSize(.small)
        }
        .compactSettingBox()
        VStack(alignment: .leading, spacing: 7) {
            Text(loc("Interface Theme")).font(.system(size: 10, weight: .semibold))
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
                    .help(loc(item.rawValue))
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
        SettingHeader("Routing", icon: "arrow.triangle.branch")
        EnumPickerRow(title: "Mode", selection: $store.settings.routeMode)
        CompactToggle(title: "Bypass LAN", subtitle: "Connect to local devices directly", value: $store.settings.bypassLAN)
        CompactToggle(title: "Kill Switch", subtitle: "Block traffic leaks if the connection drops", value: $store.settings.killSwitch)
        CompactToggle(title: "IPv6", subtitle: "Allow IPv6 inside the tunnel", value: $store.settings.ipv6)
        CompactToggle(title: "FakeDNS", subtitle: "Map DNS responses for transparent routing", value: $fakeDNS)
        CompactToggle(title: "Ad Blocking", subtitle: "Use geosite:category-ads-all rules", value: $adBlock)
        CompactToggle(title: "Bypass China", subtitle: "Route geoip:cn and geosite:cn directly", value: $chinaBypass)
        TokenCompactEditor(title: "Direct", values: $store.settings.directDomains)
        TokenCompactEditor(title: "Blocked", values: $store.settings.blockedDomains)
        TokenCompactEditor(title: "Apps Outside VPN", values: $store.settings.excludedApps)
    }
}

struct DNSSettings: View {
    @EnvironmentObject private var store: AppStore
    @AppStorage("RemoteDNS") private var remoteDNS = "https://1.1.1.1/dns-query"
    @AppStorage("DirectDNS") private var directDNS = "system"
    @AppStorage("GeoIPURL") private var geoIPURL = ""
    @AppStorage("GeoSiteURL") private var geoSiteURL = ""
    var body: some View {
        SettingHeader("DNS and Geo", icon: "network")
        CompactToggle(title: "Secure DNS", subtitle: "Send DNS queries through the VPN", value: $store.settings.dnsEnabled)
        CompactTextRow(title: "VPN DNS", text: $store.settings.dnsServer)
        CompactTextRow(title: "Remote DNS", text: $remoteDNS)
        CompactTextRow(title: "Direct DNS", text: $directDNS)
        CompactTextRow(title: "geoip.dat URL", text: $geoIPURL)
        CompactTextRow(title: "geosite.dat URL", text: $geoSiteURL)
        HStack {
            Spacer()
            Button(loc("Update Geo Files")) {
                Task { await store.updateGeoFiles(geoIPURL: geoIPURL, geoSiteURL: geoSiteURL) }
            }
            .font(.system(size: 9, weight: .semibold))
        }
    }
}

struct AutomationSettings: View {
    @EnvironmentObject private var store: AppStore
    @AppStorage("SubscriptionInterval") private var interval = "24 Hours"
    @AppStorage("SubscriptionUserAgent") private var userAgent = "Happ/2.18.1/macOSarm64"
    @AppStorage("LatencyMethod") private var latency = LatencyMethod.tcp.rawValue
    var body: some View {
        SettingHeader("Automation", icon: "clock.arrow.circlepath")
        EnumPickerRow(title: "Connection", selection: $store.settings.mode)
        CompactToggle(title: "Auto Connect", subtitle: "Connect after launch", value: $store.settings.autoConnect)
        CompactToggle(title: "Auto Reconnect", subtitle: "Restore the tunnel after interruption", value: $store.settings.autoReconnect)
        ToggleRowWithAction(
            title: "Launch at Login",
            value: store.settings.launchAtLogin,
            action: { store.setLaunchAtLogin($0) }
        )
        CompactPicker(title: "Subscription Updates", selection: $interval, values: ["Off", "1 Hour", "6 Hours", "12 Hours", "24 Hours", "7 Days"])
        CompactPicker(title: "Latency Test", selection: $latency, values: LatencyMethod.allCases.map(\.rawValue))
        CompactTextRow(title: "User-Agent", text: $userAgent)
        .onAppear {
            let legacyIntervals = [
                "\u{412}\u{44B}\u{43A}\u{43B}.": "Off",
                "1 \u{447}\u{430}\u{441}": "1 Hour",
                "6 \u{447}\u{430}\u{441}\u{43E}\u{432}": "6 Hours",
                "12 \u{447}\u{430}\u{441}\u{43E}\u{432}": "12 Hours",
                "24 \u{447}\u{430}\u{441}\u{430}": "24 Hours",
                "7 \u{434}\u{43D}\u{435}\u{439}": "7 Days"
            ]
            if let migrated = legacyIntervals[interval] { interval = migrated }
        }
    }
}

struct WorkspaceSettings: View {
    @EnvironmentObject private var store: AppStore
    let seed: Color
    @State private var workspaceToDelete: VPNWorkspace?
    var body: some View {
        SettingHeader("User Workspaces", icon: "person.2.fill")
        ForEach(store.workspaces) { workspace in
            HStack {
                Circle().fill(seed).frame(width: 10, height: 10)
                Text(loc(workspace.name)).font(.system(size: 10, weight: .semibold))
                Spacer()
                if workspace.id == store.activeWorkspaceID { Text(loc("Active")).font(.system(size: 8)).foregroundStyle(seed) }
                else { Button(loc("Switch")) { store.switchWorkspace(workspace.id) }.font(.system(size: 9)) }
                if store.workspaces.count > 1 {
                    Button { workspaceToDelete = workspace } label: { Image(systemName: "trash") }
                        .buttonStyle(.plain).foregroundStyle(.red.opacity(0.7))
                }
            }.compactSettingBox()
        }
        Text(loc("Each workspace stores its own configurations, subscriptions, and active server."))
            .font(.system(size: 9)).foregroundStyle(.secondary)
        .confirmationDialog(
            loc("Delete this user workspace?"),
            isPresented: Binding(
                get: { workspaceToDelete != nil },
                set: { if !$0 { workspaceToDelete = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button(loc("Delete"), role: .destructive) {
                if let workspaceToDelete { store.deleteWorkspace(workspaceToDelete.id) }
                workspaceToDelete = nil
            }
            Button(loc("Cancel"), role: .cancel) { workspaceToDelete = nil }
        } message: {
            Text(workspaceToDelete?.name ?? "")
        }
    }
}

struct DataSettings: View {
    @EnvironmentObject private var store: AppStore
    @State private var confirmClearLogs = false
    var body: some View {
        SettingHeader("Data and Diagnostics", icon: "externaldrive.fill")
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 6) {
                Button(loc("Create Backup")) { saveBackup() }
                    .frame(width: 120)
                Button(loc("Restore")) { restoreBackup() }
                    .frame(width: 120)
                Spacer()
            }
            HStack(spacing: 6) {
                Button(loc("Copy Log")) {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(store.logs.joined(separator: "\n"), forType: .string)
                }
                .frame(width: 120)
                Button(loc("Save Log")) { saveLog() }
                    .frame(width: 120)
                Button(loc("Clear")) { confirmClearLogs = true }
                    .frame(width: 80)
                Spacer()
            }
        }
        .font(.system(size: 9))
        ScrollView {
            Text(store.logs.isEmpty ? loc("Logs will appear after connecting.") : store.logs.joined(separator: "\n"))
                .font(.system(size: 8, design: .monospaced))
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(8)
        }
        .frame(height: 150)
        .background(.black.opacity(0.22), in: RoundedRectangle(cornerRadius: 10))
        .confirmationDialog(
            loc("Clear the diagnostics log?"),
            isPresented: $confirmClearLogs,
            titleVisibility: .visible
        ) {
            Button(loc("Clear"), role: .destructive) { store.logs.removeAll() }
            Button(loc("Cancel"), role: .cancel) {}
        }
    }

    private func saveBackup() {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "materialTun-backup.json"
        panel.allowedContentTypes = [.json]
        if panel.runModal() == .OK, let url = panel.url {
            do { try store.backup(to: url); store.showToast(loc("Backup created")) }
            catch { store.showToast(error.localizedDescription) }
        }
    }
    private func restoreBackup() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        if panel.runModal() == .OK, let url = panel.url {
            do { try store.restoreBackup(from: url); store.showToast(loc("Data restored")) }
            catch { store.showToast(loc("Invalid backup")) }
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
            Text(loc("A compact Xray + sing-box client for macOS"))
                .font(.system(size: 9)).foregroundStyle(.secondary)
            Button(loc("Check for Updates")) { Task { await store.checkForUpdates() } }
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
            Text(loc("Import")).font(.system(size: 18, weight: .bold, design: .rounded))
            TextEditor(text: $text)
                .font(.system(size: 10, design: .monospaced))
                .scrollContentBackground(.hidden)
                .padding(8).frame(height: 115)
                .background(.black.opacity(0.18), in: RoundedRectangle(cornerRadius: 12))
            if let first = parsed.first {
                VStack(alignment: .leading, spacing: 4) {
                    Label(locf("%d configurations", parsed.count), systemImage: "checkmark.circle.fill").foregroundStyle(.green)
                    Text("\(first.type.rawValue) · \(first.host):\(first.port)")
                    Text(first.rawURI.contains("security=reality") ? "REALITY" : loc("Link parameters verified"))
                        .foregroundStyle(.secondary)
                }.font(.system(size: 10)).padding(9).compactCard()
            } else if !text.isEmpty {
                Label(loc("Format not recognized yet"), systemImage: "exclamationmark.triangle.fill")
                    .font(.system(size: 10)).foregroundStyle(.orange)
            }
            HStack {
                Button(loc("From Clipboard")) { text = NSPasteboard.general.string(forType: .string) ?? "" }
                Spacer()
                Button(loc("Cancel")) { dismiss() }
                Button(loc("Import")) {
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
            Text(loc("Profile")).font(.system(size: 18, weight: .bold))
            CompactTextRow(title: "Name", text: $server.name)
            CompactTextRow(title: "Server", text: $server.host)
            HStack {
                Text(loc("Port")).font(.system(size: 10))
                Spacer()
                TextField("", value: $server.port, format: .number).frame(width: 90)
                    .textFieldStyle(.plain)
            }.compactSettingBox()
            CompactToggle(title: "allowInsecure", subtitle: "Do not verify the TLS certificate", value: $options.allowInsecure)
            CompactToggle(title: "Mux", subtitle: "Multiplex connections", value: $options.mux)
            CompactToggle(title: "TLS Fragmentation", subtitle: "Anti-DPI ClientHello fragmentation", value: $options.tlsFragment)
            if options.tlsFragment {
                CompactTextRow(title: "Packet Size", text: $options.fragmentLength)
                CompactTextRow(title: "Interval", text: $options.fragmentInterval)
            }
            SecureField(loc("Secrets are hidden · edit the original link if needed"), text: .constant(""))
                .textFieldStyle(.plain)
                .font(.system(size: 9))
                .padding(8)
                .background(Color(hex: "2B2930"), in: RoundedRectangle(cornerRadius: 10))
            HStack {
                Spacer()
                Button(loc("Cancel")) { dismiss() }
                Button(loc("Save")) {
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
            Text(loc("New Subscription")).font(.system(size: 18, weight: .bold))
            Text(loc("The name will be detected automatically from the provider response."))
                .font(.system(size: 9))
                .foregroundStyle(.secondary)
            CompactTextRow(title: "URL", text: $url)
            HStack {
                Spacer()
                Button(loc("Cancel")) { dismiss() }
                Button(loc("Add")) {
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
                Text(loc("User Workspaces")).font(.system(size: 17, weight: .bold))
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
                        Text(loc(workspace.name)).font(.system(size: 11, weight: .semibold))
                        Spacer()
                        Text("\(workspace.servers.count)").font(.system(size: 9)).foregroundStyle(.secondary)
                        if store.activeWorkspaceID == workspace.id { Image(systemName: "checkmark").foregroundStyle(seed) }
                    }.padding(9).compactCard()
                }.buttonStyle(.plain)
            }
            Divider()
            TextField(loc("New Workspace"), text: $name)
                .textFieldStyle(.plain)
                .padding(8)
                .background(Color(hex: "2B2930"), in: RoundedRectangle(cornerRadius: 10))
            HStack {
                Spacer()
                Button(loc("Create")) {
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
            Text(loc(["Welcome", "Add a Configuration", "Allow TUN"][page]))
                .font(.system(size: 22, weight: .bold, design: .rounded))
            Text(loc([
                "A compact VPN client for Xray and sing-box.",
                "Paste a link or open a file, subscription, or QR code.",
                "For full-device VPN, macOS will request an administrator password. System Proxy works without it."
            ][page]))
            .font(.system(size: 11)).foregroundStyle(.secondary)
            .multilineTextAlignment(.center).frame(width: 340)
            Spacer()
            HStack {
                if page > 0 { Button(loc("Back")) { page -= 1 } }
                Spacer()
                Button(loc(page == 2 ? "Get Started" : "Next")) {
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
            Text(loc(title)).font(.system(size: 12, weight: .semibold))
            Text(loc(subtitle)).font(.system(size: 9)).foregroundStyle(.secondary)
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
            Text(loc(title)).font(.system(size: 13, weight: .bold, design: .rounded))
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
                Text(loc(title)).font(.system(size: 10, weight: .medium))
                Text(loc(subtitle)).font(.system(size: 8)).foregroundStyle(.secondary)
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
            Text(loc(title)).font(.system(size: 10, weight: .medium))
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
            Text(loc(title)).font(.system(size: 10, weight: .medium))
            Spacer()
            Picker("", selection: $selection) {
                ForEach(values, id: \.self) { Text(loc($0)).tag($0) }
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
            Text(loc(title)).font(.system(size: 10, weight: .medium))
            Spacer()
            Picker("", selection: $selection) {
                ForEach(values) { Text(loc($0.rawValue)).tag($0) }
            }.labelsHidden().frame(width: 165).controlSize(.small)
        }.compactSettingBox()
    }
}

struct CompactTextRow: View {
    let title: String
    @Binding var text: String
    var body: some View {
        HStack {
            Text(loc(title)).font(.system(size: 10, weight: .medium))
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
                Text(loc(title)).font(.system(size: 10, weight: .medium))
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
            Button(loc(store.state.connected ? "Disconnect" : "Connect")) { store.toggleConnection() }
            Menu(loc("Server")) {
                ForEach(store.servers) { server in
                    Button(server.name) { store.selectedServerID = server.id; store.save() }
                }
            }
            Menu(loc("Workspace")) {
                ForEach(store.workspaces) { workspace in
                    Button(loc(workspace.name)) { store.switchWorkspace(workspace.id) }
                }
            }
            Divider()
            Button(loc("Open")) { NSApp.activate(ignoringOtherApps: true); openWindow(id: "main") }
            Button(loc("Quit")) { NSApp.terminate(nil) }
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
        let label = UserDefaults.standard.string(forKey: "SubscriptionInterval") ?? "24 Hours"
        let seconds: TimeInterval
        switch label {
        case "1 Hour", "1 \u{447}\u{430}\u{441}": seconds = 3600
        case "6 Hours", "6 \u{447}\u{430}\u{441}\u{43E}\u{432}": seconds = 21600
        case "12 Hours", "12 \u{447}\u{430}\u{441}\u{43E}\u{432}": seconds = 43200
        case "7 Days", "7 \u{434}\u{43D}\u{435}\u{439}": seconds = 604800
        case "Off", "\u{412}\u{44B}\u{43A}\u{43B}.": return
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
