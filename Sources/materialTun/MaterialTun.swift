import SwiftUI
import AppKit
import Foundation
import ServiceManagement
import CoreImage
import UniformTypeIdentifiers
import Network

private extension String {
    var xmlEscaped: String {
        replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&apos;")
    }

    func ifEmpty(_ fallback: String) -> String { isEmpty ? fallback : self }
}

enum AppTab: String, CaseIterable {
    case home = "Home"
    case servers = "Servers"
    case settings = "Settings"

    var icon: String {
        switch self {
        case .home: "bolt.fill"
        case .servers: "server.rack"
        case .settings: "slider.horizontal.3"
        }
    }

    var title: String { loc(rawValue) }
}

enum ProxyProtocol: String, Codable, CaseIterable, Sendable {
    case vless = "VLESS"
    case vmess = "VMess"
    case trojan = "Trojan"
    case shadowsocks = "Shadowsocks"
    case socks = "SOCKS"
    case http = "HTTP"
    case hysteria2 = "Hysteria2"
    case tuic = "TUIC"
    case wireguard = "WireGuard"
    case anytls = "AnyTLS"
    case raw = "Xray JSON"

    var color: Color {
        switch self {
        case .vless: .cyan
        case .vmess: .indigo
        case .trojan: .orange
        case .shadowsocks: .pink
        case .socks: .mint
        case .http: .blue
        case .hysteria2: .green
        case .tuic: .yellow
        case .wireguard: .teal
        case .anytls: .purple
        case .raw: .purple
        }
    }

    var usesSingBox: Bool {
        [.hysteria2, .tuic, .wireguard, .anytls].contains(self)
    }
}

enum ConnectionMode: String, Codable, CaseIterable, Identifiable {
    case systemProxy = "System Proxy"
    case tun = "TUN"
    var id: String { rawValue }

    init(from decoder: Decoder) throws {
        let value = try decoder.singleValueContainer().decode(String.self)
        switch value {
        case "System Proxy", "\u{421}\u{438}\u{441}\u{442}\u{435}\u{43C}\u{43D}\u{44B}\u{439} \u{43F}\u{440}\u{43E}\u{43A}\u{441}\u{438}": self = .systemProxy
        case "TUN": self = .tun
        default: throw DecodingError.dataCorruptedError(in: try decoder.singleValueContainer(), debugDescription: "Unknown connection mode: \(value)")
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}

enum RouteMode: String, Codable, CaseIterable, Identifiable {
    case global = "Global"
    case rules = "Rules"
    case direct = "Direct"
    var id: String { rawValue }

    init(from decoder: Decoder) throws {
        let value = try decoder.singleValueContainer().decode(String.self)
        switch value {
        case "Global", "\u{413}\u{43B}\u{43E}\u{431}\u{430}\u{43B}\u{44C}\u{43D}\u{43E}": self = .global
        case "Rules", "\u{41F}\u{43E} \u{43F}\u{440}\u{430}\u{432}\u{438}\u{43B}\u{430}\u{43C}": self = .rules
        case "Direct", "\u{41D}\u{430}\u{43F}\u{440}\u{44F}\u{43C}\u{443}\u{44E}": self = .direct
        default: throw DecodingError.dataCorruptedError(in: try decoder.singleValueContainer(), debugDescription: "Unknown route mode: \(value)")
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}

struct ServerProfile: Codable, Identifiable, Hashable, Sendable {
    var id = UUID()
    var name: String
    var type: ProxyProtocol
    var host: String
    var port: Int
    var rawURI: String
    var subscriptionID: UUID?
    var ping: Int?
    var lastUsed: Date?
    var favorite = false
}

struct Subscription: Codable, Identifiable, Hashable {
    var id = UUID()
    var name: String
    var url: String
    var lastUpdated: Date?
    var autoUpdate = true
}

struct ParsedSubscription: Sendable {
    let profiles: [ServerProfile]
    let isRejected: Bool
}

struct AppSettings: Codable, Equatable {
    var mode: ConnectionMode = .tun
    var routeMode: RouteMode = .rules
    var autoConnect = false
    var autoReconnect = true
    var launchAtLogin = false
    var disconnectOnSleep = false
    var killSwitch = false
    var ipv6 = true
    var sniffing = true
    var bypassLAN = true
    var dnsEnabled = true
    var dnsServer = "1.1.1.1"
    var testURL = "https://www.gstatic.com/generate_204"
    var localSocksPort = 10808
    var localHTTPPort = 10809
    var logLevel = "warning"
    var directDomains = ["localhost", "*.local", "apple.com"]
    var blockedDomains = [String]()
    var excludedCIDRs = ["10.0.0.0/8", "172.16.0.0/12", "192.168.0.0/16"]
    var excludedApps = [String]()
}

struct ProxyEndpointState: Codable {
    var enabled: Bool
    var host: String
    var port: Int
}

struct ServiceProxySnapshot: Codable {
    var service: String
    var socks: ProxyEndpointState
    var web: ProxyEndpointState
    var secureWeb: ProxyEndpointState
}

struct TunnelHelperCommand: Codable {
    let id: UUID
    let action: String
}

struct TunnelHelperStatus: Codable {
    let commandID: UUID?
    let state: String
    let message: String?
    let pid: Int32?
}

enum ConnectionState: Equatable {
    case disconnected
    case connecting
    case connected(Date)
    case disconnecting
    case failed(String)

    var title: String {
        switch self {
        case .disconnected: loc("Disconnected")
        case .connecting: loc("Connecting…")
        case .connected: loc("Protected")
        case .disconnecting: loc("Disconnecting…")
        case .failed: loc("Error")
        }
    }

    var connected: Bool {
        if case .connected = self { return true }
        return false
    }

}

@MainActor
final class AppStore: ObservableObject {
    static let shared = AppStore()

    @Published var tab: AppTab = .home
    @Published var servers = [ServerProfile]()
    @Published var subscriptions = [Subscription]()
    @Published var selectedServerID: UUID?
    @Published var settings = AppSettings()
    @Published var state: ConnectionState = .disconnected
    @Published var downRate: Double = 0
    @Published var upRate: Double = 0
    @Published var sessionDownloaded: Double = 0
    @Published var sessionUploaded: Double = 0
    @Published var toast: String?
    @Published var logs = [String]()
    @Published var workspaces = [VPNWorkspace]()
    @Published var activeWorkspaceID: UUID?
    @Published var profileOptions = [UUID: ProfileOptions]()
    @Published var subscriptionDetails = [UUID: SubscriptionDetails]()
    @Published var updateStatus = ""
    @Published var language = AppLanguage(
        rawValue: UserDefaults.standard.string(forKey: "AppLanguage") ?? ""
    ) ?? .english
    @Published var onboardingComplete = UserDefaults.standard.bool(forKey: "materialTunOnboardingComplete")

    var xrayProcess: Process?
    private var connectionAttemptID: UUID?
    private var statsTimer: Timer?
    private var lastTrafficSample: (down: Double, up: Double)?
    private let decoder = JSONDecoder()
    private let encoder = JSONEncoder()

    var supportURL: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("materialTun", isDirectory: true)
    }

    var selectedServer: ServerProfile? {
        get { servers.first { $0.id == selectedServerID } }
        set { selectedServerID = newValue?.id; save() }
    }

    private init() {
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        load()
        loadExtendedState()
        if !UserDefaults.standard.bool(forKey: "materialTunFullDeviceModeConfigured") {
            settings.mode = .tun
            UserDefaults.standard.set(true, forKey: "materialTunFullDeviceModeConfigured")
            save()
        }
        if !UserDefaults.standard.bool(forKey: "materialTunGlobalRoutingConfigured") {
            settings.routeMode = .global
            UserDefaults.standard.set(true, forKey: "materialTunGlobalRoutingConfigured")
            save()
        }
    }

    func load() {
        try? FileManager.default.createDirectory(at: supportURL, withIntermediateDirectories: true)
        if let data = try? Data(contentsOf: supportURL.appendingPathComponent("servers.json")),
           let value = try? decoder.decode([ServerProfile].self, from: data) { servers = value }
        if let data = try? Data(contentsOf: supportURL.appendingPathComponent("subscriptions.json")),
           let value = try? decoder.decode([Subscription].self, from: data) { subscriptions = value }
        if let data = try? Data(contentsOf: supportURL.appendingPathComponent("settings.json")),
           let value = try? decoder.decode(AppSettings.self, from: data) { settings = value }
        if let text = try? String(contentsOf: supportURL.appendingPathComponent("selected.txt"), encoding: .utf8) {
            selectedServerID = UUID(uuidString: text.trimmingCharacters(in: .whitespacesAndNewlines))
        }
        if selectedServerID == nil { selectedServerID = servers.first?.id }
    }

    func save() {
        persistActiveWorkspace()
        try? FileManager.default.createDirectory(at: supportURL, withIntermediateDirectories: true)
        if let data = try? encoder.encode(servers) { try? data.write(to: supportURL.appendingPathComponent("servers.json"), options: .atomic) }
        if let data = try? encoder.encode(subscriptions) { try? data.write(to: supportURL.appendingPathComponent("subscriptions.json"), options: .atomic) }
        if let data = try? encoder.encode(settings) { try? data.write(to: supportURL.appendingPathComponent("settings.json"), options: .atomic) }
        try? selectedServerID?.uuidString.write(to: supportURL.appendingPathComponent("selected.txt"), atomically: true, encoding: .utf8)
        saveExtendedState()
    }

    func showToast(_ text: String) {
        toast = text
        Task {
            try? await Task.sleep(for: .seconds(2.4))
            if toast == text { toast = nil }
        }
    }

    func setLanguage(_ language: AppLanguage) {
        UserDefaults.standard.set(language.rawValue, forKey: "AppLanguage")
        self.language = language
    }

    func addProfiles(from input: String, subscriptionID: UUID? = nil) -> Int {
        let parsed = ConfigParser.parseMany(input, subscriptionID: subscriptionID)
        mergeProfiles(parsed)
        if selectedServerID == nil { selectedServerID = servers.first?.id }
        save()
        return parsed.count
    }

    func parseSubscription(_ text: String, subscriptionID: UUID) async -> ParsedSubscription {
        await Task.detached(priority: .userInitiated) {
            let profiles = ConfigParser.parseMany(text, subscriptionID: subscriptionID)
            return ParsedSubscription(
                profiles: profiles,
                isRejected: ConfigParser.isRejectedSubscription(text, parsedProfiles: profiles)
            )
        }.value
    }

    private func mergeProfiles(_ profiles: [ServerProfile]) {
        var merged = servers
        var indexes = Dictionary(merged.enumerated().map { ($0.element.rawURI, $0.offset) }, uniquingKeysWith: { first, _ in first })
        for profile in profiles {
            if let index = indexes[profile.rawURI] {
                var updated = profile
                updated.id = merged[index].id
                updated.ping = merged[index].ping
                updated.lastUsed = merged[index].lastUsed
                updated.favorite = merged[index].favorite
                merged[index] = updated
            } else {
                indexes[profile.rawURI] = merged.count
                merged.append(profile)
            }
        }
        servers = merged
    }

    func replaceProfiles(_ profiles: [ServerProfile], for subscriptionID: UUID) {
        let oldProfiles = servers.filter { $0.subscriptionID == subscriptionID }
        let oldByURI = Dictionary(oldProfiles.map { ($0.rawURI, $0) }, uniquingKeysWith: { first, _ in first })
        let replacements = profiles.map { profile -> ServerProfile in
            guard let old = oldByURI[profile.rawURI] else { return profile }
            var updated = profile
            updated.id = old.id
            updated.ping = old.ping
            updated.lastUsed = old.lastUsed
            updated.favorite = old.favorite
            return updated
        }
        var updatedServers = servers.filter { $0.subscriptionID != subscriptionID }
        updatedServers.append(contentsOf: replacements)
        servers = updatedServers
        if !servers.contains(where: { $0.id == selectedServerID }) {
            selectedServerID = replacements.first?.id ?? servers.first?.id
        }
    }

    func importFiles(_ urls: [URL]) {
        var count = 0
        for url in urls {
            guard url.startAccessingSecurityScopedResource() || FileManager.default.isReadableFile(atPath: url.path) else { continue }
            defer { url.stopAccessingSecurityScopedResource() }
            if let text = try? String(contentsOf: url, encoding: .utf8) { count += addProfiles(from: text) }
        }
        showToast(count > 0 ? locf("Servers added: %d", count) : loc("No supported configurations found"))
    }

    func addSubscription(name: String, url: String) async {
        guard let remote = URL(string: url), ["http", "https"].contains(remote.scheme?.lowercased() ?? "") else {
            showToast(loc("Invalid subscription URL"))
            return
        }
        var item = Subscription(name: name.isEmpty ? (remote.host?.replacingOccurrences(of: "www.", with: "") ?? "Subscription") : name, url: url)
        subscriptions.append(item)
        do {
            let (data, response) = try await URLSession.shared.data(for: subscriptionRequest(url: remote))
            let text = String(data: data, encoding: .utf8) ?? ""
            let result = await parseSubscription(text, subscriptionID: item.id)
            guard !result.isRejected else {
                throw NSError(domain: "materialTun.Subscription", code: 403, userInfo: [NSLocalizedDescriptionKey: loc("The provider rejected this client")])
            }
            let parsed = result.profiles
            guard !parsed.isEmpty else {
                throw NSError(domain: "materialTun.Subscription", code: 422, userInfo: [NSLocalizedDescriptionKey: loc("The subscription contains no supported configurations")])
            }
            mergeProfiles(parsed)
            let count = parsed.count
            item.lastUpdated = Date()
            if name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
               let http = response as? HTTPURLResponse,
               let detected = subscriptionTitle(response: http, fallbackURL: remote) {
                item.name = detected
            }
            if let i = subscriptions.firstIndex(where: { $0.id == item.id }) { subscriptions[i] = item }
            save()
            showToast(locf("Subscription added · %d servers", count))
        } catch {
            save()
            showToast(loc("Subscription saved, but currently unavailable"))
        }
    }

    func updateSubscription(_ subscription: Subscription) async {
        guard let url = URL(string: subscription.url) else { return }
        do {
            let (data, response) = try await URLSession.shared.data(for: subscriptionRequest(url: url))
            let text = String(data: data, encoding: .utf8) ?? ""
            let result = await parseSubscription(text, subscriptionID: subscription.id)
            guard !result.isRejected else {
                throw NSError(domain: "materialTun.Subscription", code: 403, userInfo: [NSLocalizedDescriptionKey: loc("The provider rejected this client")])
            }
            let parsed = result.profiles
            guard !parsed.isEmpty else {
                throw NSError(domain: "materialTun.Subscription", code: 422, userInfo: [NSLocalizedDescriptionKey: loc("The subscription contains no supported configurations")])
            }
            replaceProfiles(parsed, for: subscription.id)
            let count = parsed.count
            if let i = subscriptions.firstIndex(where: { $0.id == subscription.id }) {
                subscriptions[i].lastUpdated = Date()
                if let http = response as? HTTPURLResponse,
                   let detected = subscriptionTitle(response: http, fallbackURL: url) {
                    subscriptions[i].name = detected
                }
            }
            save()
            showToast(locf("Updated %d configurations", count))
        } catch {
            showToast(loc("Could not update subscription"))
        }
    }

    func deleteSubscription(_ subscription: Subscription) {
        servers.removeAll { $0.subscriptionID == subscription.id }
        subscriptions.removeAll { $0.id == subscription.id }
        if !servers.contains(where: { $0.id == selectedServerID }) { selectedServerID = servers.first?.id }
        save()
    }

    func ping(_ id: UUID) {
        guard let index = servers.firstIndex(where: { $0.id == id }) else { return }
        let host = servers[index].host
        servers[index].ping = -1
        Task {
            let result = await Task.detached(priority: .utility) { () -> Int? in
                let task = Process()
                let pipe = Pipe()
                task.executableURL = URL(fileURLWithPath: "/sbin/ping")
                task.arguments = ["-c", "1", "-W", "1200", host]
                task.standardOutput = pipe
                task.standardError = pipe
                do {
                    try task.run()
                    task.waitUntilExit()
                    let data = pipe.fileHandleForReading.readDataToEndOfFile()
                    let output = String(data: data, encoding: .utf8) ?? ""
                    guard let range = output.range(of: #"time[=<]([0-9.]+)"#, options: .regularExpression) else { return nil }
                    let token = output[range].replacingOccurrences(of: "time=", with: "").replacingOccurrences(of: "time<", with: "")
                    return Int(Double(token) ?? 0)
                } catch { return nil }
            }.value
            if let current = self.servers.firstIndex(where: { $0.id == id }) {
                self.servers[current].ping = result ?? 0
                self.save()
            }
        }
    }

    func pingAll() {
        for (offset, server) in servers.enumerated() {
            Task {
                try? await Task.sleep(for: .milliseconds(offset * 90))
                ping(server.id)
            }
        }
    }

    func toggleConnection() {
        switch state {
        case .connecting, .connected, .disconnecting:
            disconnect()
        case .disconnected, .failed:
            connect()
        }
    }

    func connect() {
        guard let server = selectedServer else {
            showToast(loc("Add and select a server first"))
            tab = .servers
            return
        }
        if server.type.usesSingBox {
            connectWithSingBox(server)
            return
        }
        guard let xray = Bundle.main.url(forResource: "xray", withExtension: nil) else {
            state = .failed(loc("Xray engine not found"))
            return
        }
        disconnect(silent: true)
        _ = shell("/usr/bin/pkill", ["-f", "\(xray.path) run"])
        let attemptID = UUID()
        connectionAttemptID = attemptID
        state = .connecting
        log(locf("Preparing %@ · %@:%d", server.type.rawValue, server.host, server.port))
        do {
            let config = try XrayConfigBuilder.make(
                server: server,
                settings: settings,
                options: profileOptions[server.id] ?? .init()
            )
            let configURL = supportURL.appendingPathComponent("runtime-xray.json")
            try config.write(to: configURL, options: .atomic)

            let process = Process()
            let output = Pipe()
            process.executableURL = xray
            process.arguments = ["run", "-config", configURL.path]
            var environment = ProcessInfo.processInfo.environment
            let customGeo = supportURL.appendingPathComponent("geo", isDirectory: true)
            environment["XRAY_LOCATION_ASSET"] = FileManager.default.fileExists(atPath: customGeo.appendingPathComponent("geoip.dat").path)
                ? customGeo.path
                : Bundle.main.resourceURL?.path
            process.environment = environment
            process.standardOutput = output
            process.standardError = output
            output.fileHandleForReading.readabilityHandler = { [weak self] handle in
                let text = String(data: handle.availableData, encoding: .utf8) ?? ""
                guard !text.isEmpty else { return }
                Task { @MainActor in self?.log(text.trimmingCharacters(in: .whitespacesAndNewlines)) }
            }
            process.terminationHandler = { [weak self] task in
                Task { @MainActor in
                    guard let self, self.state.connected else { return }
                    self.state = .failed(locf("Xray exited with code %d", task.terminationStatus))
                    self.restoreSystemProxy()
                }
            }
            try process.run()
            xrayProcess = process
            Task {
                let ready = await waitForLocalProxy(port: settings.localHTTPPort, process: process)
                guard connectionAttemptID == attemptID, state == .connecting else {
                    if process.isRunning { process.terminate() }
                    return
                }
                guard process.isRunning else {
                    state = .failed(loc("Configuration failed to start"))
                    return
                }
                guard ready else {
                    process.terminate()
                    xrayProcess = nil
                    state = .failed(locf("The local proxy did not open port %d", settings.localHTTPPort))
                    log(locf("Xray is running, but port %d is unavailable", settings.localHTTPPort))
                    return
                }
                if settings.mode == .tun {
                    try await startTun()
                    guard connectionAttemptID == attemptID, state == .connecting else {
                        stopTun()
                        if process.isRunning { process.terminate() }
                        return
                    }
                } else {
                    applySystemProxy()
                    guard systemProxyIsEnabled() else {
                        process.terminate()
                        xrayProcess = nil
                        state = .failed(loc("macOS did not allow System Proxy to be enabled"))
                        log(loc("Could not apply System Proxy settings"))
                        return
                    }
                }
                if let i = servers.firstIndex(where: { $0.id == server.id }) { servers[i].lastUsed = Date() }
                state = .connected(Date())
                connectionAttemptID = nil
                startStats()
                save()
                log(loc("Connected"))
            }
        } catch {
            state = .failed(error.localizedDescription)
            log(locf("Error: %@", error.localizedDescription))
        }
    }

    private func waitForLocalProxy(port: Int, process: Process) async -> Bool {
        for _ in 0..<30 {
            guard process.isRunning else { return false }
            let result = await Task.detached(priority: .utility) { () -> Bool in
                let probe = Process()
                probe.executableURL = URL(fileURLWithPath: "/usr/bin/nc")
                probe.arguments = ["-z", "-w", "1", "127.0.0.1", "\(port)"]
                probe.standardOutput = FileHandle.nullDevice
                probe.standardError = FileHandle.nullDevice
                do {
                    try probe.run()
                    probe.waitUntilExit()
                    return probe.terminationStatus == 0
                } catch {
                    return false
                }
            }.value
            if result { return true }
            try? await Task.sleep(for: .milliseconds(100))
        }
        return false
    }

    func disconnect(silent: Bool = false) {
        connectionAttemptID = nil
        if !silent { state = .disconnecting }
        statsTimer?.invalidate()
        statsTimer = nil
        if settings.mode == .tun { stopTun() }
        restoreSystemProxy()
        xrayProcess?.terminate()
        xrayProcess = nil
        downRate = 0
        upRate = 0
        if !silent {
            state = .disconnected
            log(loc("Disconnected"))
        }
    }

    func startStats() {
        statsTimer?.invalidate()
        lastTrafficSample = nil
        statsTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self, let pid = self.xrayProcess?.processIdentifier else { return }
                let output = self.shell("/usr/bin/nettop", ["-P", "-L", "1", "-J", "bytes_in,bytes_out", "-p", "\(pid)"])
                guard let line = output.split(separator: "\n").dropFirst().first else { return }
                let columns = line.split(separator: ",", omittingEmptySubsequences: false)
                guard columns.count >= 3,
                      let down = Double(columns[columns.count - 3]),
                      let up = Double(columns[columns.count - 2]) else { return }
                if let previous = self.lastTrafficSample {
                    self.downRate = max(0, down - previous.down)
                    self.upRate = max(0, up - previous.up)
                    self.sessionDownloaded += self.downRate
                    self.sessionUploaded += self.upRate
                }
                self.lastTrafficSample = (down, up)
            }
        }
    }

    private func networkServices() -> [String] {
        let result = shell("/usr/sbin/networksetup", ["-listallnetworkservices"])
        return result.split(separator: "\n").dropFirst().map(String.init).filter { !$0.hasPrefix("*") }
    }

    func applySystemProxy() {
        captureSystemProxy()
        for service in networkServices() {
            _ = shell("/usr/sbin/networksetup", ["-setsocksfirewallproxy", service, "127.0.0.1", "\(settings.localSocksPort)"])
            _ = shell("/usr/sbin/networksetup", ["-setsocksfirewallproxystate", service, "on"])
            _ = shell("/usr/sbin/networksetup", ["-setwebproxy", service, "127.0.0.1", "\(settings.localHTTPPort)"])
            _ = shell("/usr/sbin/networksetup", ["-setwebproxystate", service, "on"])
            _ = shell("/usr/sbin/networksetup", ["-setsecurewebproxy", service, "127.0.0.1", "\(settings.localHTTPPort)"])
            _ = shell("/usr/sbin/networksetup", ["-setsecurewebproxystate", service, "on"])
            if settings.bypassLAN {
                _ = shell("/usr/sbin/networksetup", ["-setproxybypassdomains", service, "localhost", "*.local", "127.0.0.1", "10.0.0.0/8", "172.16.0.0/12", "192.168.0.0/16"])
            }
        }
    }

    private func systemProxyIsEnabled() -> Bool {
        for service in networkServices() {
            let socks = readProxy(service: service, getter: "-getsocksfirewallproxy")
            if socks.enabled && socks.host == "127.0.0.1" && socks.port == settings.localSocksPort {
                return true
            }
        }
        return false
    }

    private func restoreSystemProxy() {
        let backupURL = supportURL.appendingPathComponent("proxy-backup.json")
        if let data = try? Data(contentsOf: backupURL),
           let snapshots = try? decoder.decode([ServiceProxySnapshot].self, from: data) {
            for snapshot in snapshots {
                restoreProxy(snapshot.socks, service: snapshot.service, setter: "-setsocksfirewallproxy", stateSetter: "-setsocksfirewallproxystate")
                restoreProxy(snapshot.web, service: snapshot.service, setter: "-setwebproxy", stateSetter: "-setwebproxystate")
                restoreProxy(snapshot.secureWeb, service: snapshot.service, setter: "-setsecurewebproxy", stateSetter: "-setsecurewebproxystate")
            }
            try? FileManager.default.removeItem(at: backupURL)
        } else {
            for service in networkServices() {
                _ = shell("/usr/sbin/networksetup", ["-setsocksfirewallproxystate", service, "off"])
                _ = shell("/usr/sbin/networksetup", ["-setwebproxystate", service, "off"])
                _ = shell("/usr/sbin/networksetup", ["-setsecurewebproxystate", service, "off"])
            }
        }
    }

    func recoverProxyIfNeeded() {
        guard FileManager.default.fileExists(atPath: supportURL.appendingPathComponent("proxy-backup.json").path) else { return }
        restoreSystemProxy()
        log(loc("Restored system proxy settings after the previous shutdown"))
    }

    private func captureSystemProxy() {
        let backupURL = supportURL.appendingPathComponent("proxy-backup.json")
        guard !FileManager.default.fileExists(atPath: backupURL.path) else { return }
        let snapshots = networkServices().map {
            ServiceProxySnapshot(
                service: $0,
                socks: readProxy(service: $0, getter: "-getsocksfirewallproxy"),
                web: readProxy(service: $0, getter: "-getwebproxy"),
                secureWeb: readProxy(service: $0, getter: "-getsecurewebproxy")
            )
        }
        if let data = try? encoder.encode(snapshots) { try? data.write(to: backupURL, options: .atomic) }
    }

    private func readProxy(service: String, getter: String) -> ProxyEndpointState {
        let output = shell("/usr/sbin/networksetup", [getter, service])
        var enabled = false
        var host = ""
        var port = 0
        for line in output.split(separator: "\n") {
            let parts = line.split(separator: ":", maxSplits: 1).map { $0.trimmingCharacters(in: .whitespaces) }
            guard parts.count == 2 else { continue }
            if parts[0] == "Enabled" { enabled = parts[1].lowercased() == "yes" }
            if parts[0] == "Server" { host = parts[1] }
            if parts[0] == "Port" { port = Int(parts[1]) ?? 0 }
        }
        return ProxyEndpointState(enabled: enabled, host: host, port: port)
    }

    private func restoreProxy(_ state: ProxyEndpointState, service: String, setter: String, stateSetter: String) {
        if !state.host.isEmpty, state.port > 0 {
            _ = shell("/usr/sbin/networksetup", [setter, service, state.host, "\(state.port)"])
        }
        _ = shell("/usr/sbin/networksetup", [stateSetter, service, state.enabled ? "on" : "off"])
    }

    private func startTun() async throws {
        guard Bundle.main.url(forResource: "sing-box", withExtension: nil) != nil else {
            throw NSError(domain: "materialTun", code: 2, userInfo: [NSLocalizedDescriptionKey: loc("sing-box engine not found")])
        }
        let configURL = supportURL.appendingPathComponent("runtime-tun.json")
        var tunRules = [[String: Any]]()
        tunRules.append([
            "process_name": ["xray", "sing-box"],
            "outbound": "direct"
        ])
        if !settings.excludedCIDRs.isEmpty {
            tunRules.append(["ip_cidr": settings.excludedCIDRs, "outbound": "direct"])
        }
        if !settings.excludedApps.isEmpty {
            tunRules.append(["process_name": settings.excludedApps, "outbound": "direct"])
        }

        let config: [String: Any] = [
            "log": ["level": settings.logLevel],
            "inbounds": [[
                "type": "tun", "tag": "tun-in",
                "address": ["172.19.0.1/30"], "auto_route": true,
                "strict_route": true, "stack": "system"
            ]],
            "outbounds": [[
                "type": "socks", "tag": "xray",
                "server": "127.0.0.1", "server_port": settings.localSocksPort
            ], [
                "type": "direct", "tag": "direct"
            ]],
            "route": [
                "auto_detect_interface": true,
                "rules": tunRules,
                "final": settings.routeMode == .direct ? "direct" : "xray"
            ]
        ]
        let data = try JSONSerialization.data(withJSONObject: config, options: [.prettyPrinted, .sortedKeys])
        try data.write(to: configURL, options: .atomic)
        try await ensureTunnelHelperInstalled()
        try await sendTunnelHelperCommand("start", expectedState: "running")
    }

    private func stopTun() {
        guard FileManager.default.fileExists(atPath: "/Library/PrivilegedHelperTools/local.materialtun.helper") else { return }
        let command = TunnelHelperCommand(id: UUID(), action: "stop")
        if let data = try? encoder.encode(command) {
            try? data.write(to: supportURL.appendingPathComponent("helper-command.json"), options: .atomic)
        }
    }

    private func ensureTunnelHelperInstalled() async throws {
        let helperPath = "/Library/PrivilegedHelperTools/local.materialtun.helper"
        let singBoxPath = "/Library/PrivilegedHelperTools/local.materialtun.sing-box"
        let plistPath = "/Library/LaunchDaemons/local.materialtun.helper.plist"
        if FileManager.default.isExecutableFile(atPath: helperPath),
           FileManager.default.isExecutableFile(atPath: singBoxPath),
           FileManager.default.fileExists(atPath: plistPath) {
            return
        }

        guard let bundledHelper = Bundle.main.bundleURL
            .appendingPathComponent("Contents/Library/HelperTools/materialTunHelper") as URL?,
              FileManager.default.isExecutableFile(atPath: bundledHelper.path),
              let bundledSingBox = Bundle.main.url(forResource: "sing-box", withExtension: nil) else {
            throw NSError(domain: "materialTun", code: 5, userInfo: [NSLocalizedDescriptionKey: loc("The system helper is missing from the application")])
        }

        let plist = """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0">
        <dict>
          <key>Label</key><string>local.materialtun.helper</string>
          <key>ProgramArguments</key>
          <array>
            <string>/Library/PrivilegedHelperTools/local.materialtun.helper</string>
            <string>--watch</string>
            <string>\(supportURL.path.xmlEscaped)</string>
          </array>
          <key>RunAtLoad</key><true/>
          <key>KeepAlive</key><true/>
          <key>ProcessType</key><string>Interactive</string>
        </dict>
        </plist>
        """
        let encodedPlist = Data(plist.utf8).base64EncodedString()
        let oldPID = (try? String(contentsOf: supportURL.appendingPathComponent("tun.pid"), encoding: .utf8)
            .trimmingCharacters(in: .whitespacesAndNewlines)) ?? ""
        let installCommand = """
        mkdir -p /Library/PrivilegedHelperTools /Library/LaunchDaemons;
        \(oldPID.allSatisfy(\.isNumber) && !oldPID.isEmpty ? "kill \(oldPID) 2>/dev/null || true;" : "")
        launchctl bootout system/local.materialtun.helper 2>/dev/null || true;
        cp \(quote(bundledHelper.path)) \(quote(helperPath));
        cp \(quote(bundledSingBox.path)) \(quote(singBoxPath));
        chown root:wheel \(quote(helperPath)) \(quote(singBoxPath));
        chmod 755 \(quote(helperPath)) \(quote(singBoxPath));
        printf %s \(quote(encodedPlist)) | /usr/bin/base64 -D > \(quote(plistPath));
        chown root:wheel \(quote(plistPath));
        chmod 644 \(quote(plistPath));
        launchctl bootstrap system \(quote(plistPath));
        launchctl enable system/local.materialtun.helper;
        launchctl kickstart -k system/local.materialtun.helper
        """
        let script = "do shell script \(appleScriptString(installCommand)) with administrator privileges"
        let result = await Task.detached(priority: .userInitiated) {
            let process = Process()
            let pipe = Pipe()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
            process.arguments = ["-e", script]
            process.standardOutput = pipe
            process.standardError = pipe
            do {
                try process.run()
                process.waitUntilExit()
                return (process.terminationStatus, String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? "")
            } catch {
                return (Int32(-1), error.localizedDescription)
            }
        }.value
        guard result.0 == 0 else {
            throw NSError(domain: "materialTun", code: 6, userInfo: [NSLocalizedDescriptionKey: locf("Could not install the helper: %@", result.1)])
        }
        try? await Task.sleep(for: .milliseconds(500))
    }

    private func sendTunnelHelperCommand(_ action: String, expectedState: String) async throws {
        let command = TunnelHelperCommand(id: UUID(), action: action)
        let commandURL = supportURL.appendingPathComponent("helper-command.json")
        let statusURL = supportURL.appendingPathComponent("helper-status.json")
        try encoder.encode(command).write(to: commandURL, options: .atomic)

        for _ in 0..<60 {
            if let data = try? Data(contentsOf: statusURL),
               let status = try? decoder.decode(TunnelHelperStatus.self, from: data),
               status.commandID == command.id {
                if status.state == expectedState { return }
                if status.state == "failed" {
                    let log = (try? String(contentsOf: supportURL.appendingPathComponent("tun.log"), encoding: .utf8)) ?? ""
                    throw NSError(
                        domain: "materialTun",
                        code: 7,
                        userInfo: [NSLocalizedDescriptionKey: status.message ?? log.ifEmpty("TUN failed to start")]
                    )
                }
            }
            try? await Task.sleep(for: .milliseconds(100))
        }
        throw NSError(domain: "materialTun", code: 8, userInfo: [NSLocalizedDescriptionKey: loc("The system helper did not respond")])
    }

    private func shell(_ executable: String, _ arguments: [String]) -> String {
        let process = Process()
        let pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.standardOutput = pipe
        process.standardError = pipe
        do {
            try process.run()
            process.waitUntilExit()
            return String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        } catch { return error.localizedDescription }
    }

    private func quote(_ value: String) -> String { "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'" }
    private func appleScriptString(_ value: String) -> String {
        "\"" + value.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"") + "\""
    }

    func log(_ text: String) {
        guard !text.isEmpty else { return }
        let stamp = Date.now.formatted(date: .omitted, time: .standard)
        logs.append("[\(stamp)] \(text)")
        if logs.count > 300 { logs.removeFirst(logs.count - 300) }
    }
}

enum ConfigParser {
    static func isRejectedSubscription(_ raw: String, parsedProfiles: [ServerProfile]? = nil) -> Bool {
        let text = decodeBase64TextIfNeeded(raw)
        let lower = text.lowercased()
        if lower.contains("app not supported") || lower.contains("unsupported client") { return true }
        let parsed = parsedProfiles ?? parseMany(raw)
        return parsed.count == 1
            && parsed[0].host == "0.0.0.0"
            && parsed[0].port == 1
            && parsed[0].name.localizedCaseInsensitiveContains("not supported")
    }

    static func parseMany(_ raw: String, subscriptionID: UUID? = nil) -> [ServerProfile] {
        let text = decodeBase64TextIfNeeded(raw)
        if let data = text.data(using: .utf8),
           let json = try? JSONSerialization.jsonObject(with: data) {
            if let object = json as? [String: Any] {
                return [rawJSONProfile(object, data: data, subscriptionID: subscriptionID, index: 1)]
            }
            if let array = json as? [[String: Any]] {
                return array.enumerated().compactMap { index, object in
                    guard let itemData = try? JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys]) else { return nil }
                    return rawJSONProfile(object, data: itemData, subscriptionID: subscriptionID, index: index + 1)
                }
            }
        }
        return text
            .components(separatedBy: .newlines)
            .flatMap { $0.components(separatedBy: CharacterSet(charactersIn: " \t")) }
            .compactMap { parseLine($0.trimmingCharacters(in: .whitespacesAndNewlines), subscriptionID: subscriptionID) }
    }

    private static func rawJSONProfile(
        _ object: [String: Any],
        data: Data,
        subscriptionID: UUID?,
        index: Int
    ) -> ServerProfile {
        let name = (object["remarks"] as? String)
            ?? (object["name"] as? String)
            ?? "Xray JSON \(index)"
        var host = "custom"
        var port = 0
        if let outbounds = object["outbounds"] as? [[String: Any]] {
            for outbound in outbounds {
                guard let settings = outbound["settings"] as? [String: Any] else { continue }
                if let vnext = settings["vnext"] as? [[String: Any]], let server = vnext.first {
                    host = server["address"] as? String ?? host
                    port = server["port"] as? Int ?? port
                    break
                }
                if let servers = settings["servers"] as? [[String: Any]], let server = servers.first {
                    host = server["address"] as? String ?? host
                    port = server["port"] as? Int ?? port
                    break
                }
            }
        }
        return ServerProfile(
            name: name,
            type: .raw,
            host: host,
            port: port,
            rawURI: String(data: data, encoding: .utf8) ?? "{}",
            subscriptionID: subscriptionID
        )
    }

    static func parseLine(_ raw: String, subscriptionID: UUID?) -> ServerProfile? {
        guard !raw.isEmpty else { return nil }
        let lower = raw.lowercased()
        if lower.hasPrefix("vmess://") { return parseVMess(raw, subscriptionID) }
        guard let url = URLComponents(string: raw), let scheme = url.scheme?.lowercased() else { return nil }
        let name = url.fragment?.removingPercentEncoding?.trimmingCharacters(in: .whitespacesAndNewlines)
        let displayName = (name?.isEmpty == false ? name! : (url.host ?? scheme.uppercased()))
        let port = url.port ?? defaultPort(scheme)
        switch scheme {
        case "vless":
            return ServerProfile(name: displayName, type: .vless, host: url.host ?? "", port: port, rawURI: raw, subscriptionID: subscriptionID)
        case "trojan":
            return ServerProfile(name: displayName, type: .trojan, host: url.host ?? "", port: port, rawURI: raw, subscriptionID: subscriptionID)
        case "socks", "socks5":
            return ServerProfile(name: displayName, type: .socks, host: url.host ?? "", port: port, rawURI: raw, subscriptionID: subscriptionID)
        case "http", "https":
            return ServerProfile(name: displayName, type: .http, host: url.host ?? "", port: port, rawURI: raw, subscriptionID: subscriptionID)
        case "hysteria2", "hy2":
            return ServerProfile(name: displayName, type: .hysteria2, host: url.host ?? "", port: port, rawURI: raw, subscriptionID: subscriptionID)
        case "tuic":
            return ServerProfile(name: displayName, type: .tuic, host: url.host ?? "", port: port, rawURI: raw, subscriptionID: subscriptionID)
        case "wireguard", "wg":
            return ServerProfile(name: displayName, type: .wireguard, host: url.host ?? "", port: port, rawURI: raw, subscriptionID: subscriptionID)
        case "anytls":
            return ServerProfile(name: displayName, type: .anytls, host: url.host ?? "", port: port, rawURI: raw, subscriptionID: subscriptionID)
        case "ss":
            return parseShadowsocks(raw, subscriptionID)
        default:
            return nil
        }
    }

    private static func parseVMess(_ raw: String, _ subscriptionID: UUID?) -> ServerProfile? {
        let payload = String(raw.dropFirst("vmess://".count))
        guard let data = decodeBase64(payload),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        let host = "\(json["add"] ?? "")"
        let port = Int("\(json["port"] ?? "443")") ?? 443
        let name = "\(json["ps"] ?? host)"
        return ServerProfile(name: name.isEmpty ? host : name, type: .vmess, host: host, port: port, rawURI: raw, subscriptionID: subscriptionID)
    }

    private static func parseShadowsocks(_ raw: String, _ subscriptionID: UUID?) -> ServerProfile? {
        let bodyAndFragment = String(raw.dropFirst(5))
        let parts = bodyAndFragment.split(separator: "#", maxSplits: 1).map(String.init)
        let body = parts[0]
        let name = parts.count > 1 ? (parts[1].removingPercentEncoding ?? parts[1]) : "Shadowsocks"
        if let url = URLComponents(string: raw), let host = url.host {
            return ServerProfile(name: name, type: .shadowsocks, host: host, port: url.port ?? 8388, rawURI: raw, subscriptionID: subscriptionID)
        }
        guard let decodedData = decodeBase64(body),
              let decoded = String(data: decodedData, encoding: .utf8),
              let split = decoded.lastIndex(of: "@") else { return nil }
        let endpoint = decoded[decoded.index(after: split)...]
        let hp = endpoint.split(separator: ":", maxSplits: 1)
        guard hp.count == 2 else { return nil }
        return ServerProfile(name: name, type: .shadowsocks, host: String(hp[0]), port: Int(hp[1]) ?? 8388, rawURI: raw, subscriptionID: subscriptionID)
    }

    private static func decodeBase64TextIfNeeded(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.contains("://") || trimmed.hasPrefix("{") { return trimmed }
        if let data = decodeBase64(trimmed), let text = String(data: data, encoding: .utf8), text.contains("://") { return text }
        return trimmed
    }

    static func decodeBase64(_ value: String) -> Data? {
        var normalized = value.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        normalized += String(repeating: "=", count: (4 - normalized.count % 4) % 4)
        return Data(base64Encoded: normalized, options: .ignoreUnknownCharacters)
    }

    private static func defaultPort(_ scheme: String) -> Int {
        ["vless", "vmess", "trojan", "hysteria2", "hy2", "tuic", "anytls"].contains(scheme) ? 443 : 1080
    }
}

enum XrayConfigBuilder {
    static func make(server: ServerProfile, settings: AppSettings, options: ProfileOptions = .init()) throws -> Data {
        if server.type == .raw, let data = server.rawURI.data(using: .utf8) {
            return try prepareRawConfig(data, settings: settings)
        }
        let outbound = try makeOutbound(server, options: options)
        var routingRules = [[String: Any]]()
        if settings.routeMode == .direct {
            routingRules.append(["type": "field", "network": "tcp,udp", "outboundTag": "direct"])
        } else if settings.routeMode == .rules {
            if settings.bypassLAN {
                routingRules.append(["type": "field", "ip": ["geoip:private"] + settings.excludedCIDRs, "outboundTag": "direct"])
            }
            if !settings.directDomains.isEmpty {
                routingRules.append(["type": "field", "domain": settings.directDomains.map(normalizeDomain), "outboundTag": "direct"])
            }
            if !settings.blockedDomains.isEmpty {
                routingRules.append(["type": "field", "domain": settings.blockedDomains.map(normalizeDomain), "outboundTag": "blocked"])
            }
            if UserDefaults.standard.bool(forKey: "AdBlock") {
                routingRules.append(["type": "field", "domain": ["geosite:category-ads-all"], "outboundTag": "blocked"])
            }
            if UserDefaults.standard.bool(forKey: "ChinaBypass") {
                routingRules.append(["type": "field", "domain": ["geosite:cn"], "outboundTag": "direct"])
                routingRules.append(["type": "field", "ip": ["geoip:cn"], "outboundTag": "direct"])
            }
        }
        let config: [String: Any] = [
            "log": ["loglevel": settings.logLevel],
            "dns": ["servers": settings.dnsEnabled ? [settings.dnsServer, "localhost"] : ["localhost"]],
            "inbounds": [
                [
                    "tag": "socks-in", "listen": "127.0.0.1", "port": settings.localSocksPort,
                    "protocol": "socks", "settings": ["auth": "noauth", "udp": true],
                    "sniffing": ["enabled": settings.sniffing, "destOverride": ["http", "tls", "quic"]]
                ],
                [
                    "tag": "http-in", "listen": "127.0.0.1", "port": settings.localHTTPPort,
                    "protocol": "http", "settings": [:]
                ]
            ],
            "outbounds": [
                outbound,
                ["tag": "direct", "protocol": "freedom", "settings": [:]],
                ["tag": "blocked", "protocol": "blackhole", "settings": [:]]
            ],
            "routing": [
                "domainStrategy": UserDefaults.standard.string(forKey: "DomainStrategy") ?? "IPIfNonMatch",
                "rules": routingRules
            ]
        ]
        return try JSONSerialization.data(withJSONObject: config, options: [.prettyPrinted, .sortedKeys])
    }

    private static func prepareRawConfig(_ data: Data, settings: AppSettings) throws -> Data {
        guard var config = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { return data }
        guard settings.routeMode != .rules else { return data }

        let outbounds = config["outbounds"] as? [[String: Any]] ?? []
        let proxyTag = outbounds.first {
            let proto = ($0["protocol"] as? String)?.lowercased() ?? ""
            return !["freedom", "blackhole", "dns"].contains(proto)
        }?["tag"] as? String ?? "proxy"

        if settings.routeMode == .global {
            config["routing"] = [
                "domainStrategy": "AsIs",
                "rules": [[
                    "type": "field",
                    "network": "tcp,udp",
                    "outboundTag": proxyTag
                ]]
            ]
        } else {
            let directTag = outbounds.first {
                ($0["protocol"] as? String)?.lowercased() == "freedom"
            }?["tag"] as? String ?? "direct"
            config["routing"] = [
                "domainStrategy": "AsIs",
                "rules": [[
                    "type": "field",
                    "network": "tcp,udp",
                    "outboundTag": directTag
                ]]
            ]
        }
        return try JSONSerialization.data(withJSONObject: config, options: [.prettyPrinted, .sortedKeys])
    }

    private static func makeOutbound(_ server: ServerProfile, options: ProfileOptions) throws -> [String: Any] {
        var outbound: [String: Any]
        switch server.type {
        case .vless: outbound = try vless(server.rawURI)
        case .vmess: outbound = try vmess(server.rawURI)
        case .trojan: outbound = try trojan(server.rawURI)
        case .shadowsocks: outbound = try shadowsocks(server.rawURI)
        case .socks: outbound = try socks(server.rawURI)
        case .http: outbound = try http(server.rawURI)
        case .hysteria2, .tuic, .wireguard, .anytls:
            throw badConfig("This protocol runs through sing-box")
        case .raw: return [:]
        }
        if options.mux { outbound["mux"] = ["enabled": true, "concurrency": 8] }
        if options.allowInsecure,
           var stream = outbound["streamSettings"] as? [String: Any] {
            if var tls = stream["tlsSettings"] as? [String: Any] {
                tls["allowInsecure"] = true
                stream["tlsSettings"] = tls
            }
            if var reality = stream["realitySettings"] as? [String: Any] {
                reality["allowInsecure"] = true
                stream["realitySettings"] = reality
            }
            outbound["streamSettings"] = stream
        }
        return outbound
    }

    private static func vless(_ raw: String) throws -> [String: Any] {
        guard let u = URLComponents(string: raw), let host = u.host, let id = u.user else { throw badConfig("VLESS") }
        let q = query(u)
        var stream: [String: Any] = ["network": q["type"] ?? "tcp", "security": q["security"] ?? "none"]
        applyTransport(&stream, q)
        if q["security"] == "reality" {
            stream["realitySettings"] = [
                "serverName": q["sni"] ?? host, "fingerprint": q["fp"] ?? "chrome",
                "publicKey": q["pbk"] ?? "", "shortId": q["sid"] ?? "",
                "spiderX": q["spx"] ?? "/"
            ]
        } else if q["security"] == "tls" {
            stream["tlsSettings"] = ["serverName": q["sni"] ?? host, "fingerprint": q["fp"] ?? "chrome", "allowInsecure": q["allowInsecure"] == "1"]
        }
        let user: [String: Any] = ["id": id, "encryption": q["encryption"] ?? "none", "flow": q["flow"] ?? ""]
        return ["tag": "proxy", "protocol": "vless", "settings": ["vnext": [["address": host, "port": u.port ?? 443, "users": [user]]]], "streamSettings": stream]
    }

    private static func vmess(_ raw: String) throws -> [String: Any] {
        let payload = String(raw.dropFirst(8))
        guard let data = ConfigParser.decodeBase64(payload),
              let j = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { throw badConfig("VMess") }
        let host = "\(j["add"] ?? "")"
        let network = "\(j["net"] ?? "tcp")"
        let security = "\(j["tls"] ?? "")".isEmpty ? "none" : "\(j["tls"] ?? "tls")"
        var stream: [String: Any] = ["network": network, "security": security]
        let q = ["type": network, "host": "\(j["host"] ?? "")", "path": "\(j["path"] ?? "/")", "sni": "\(j["sni"] ?? "")"]
        applyTransport(&stream, q)
        if security == "tls" { stream["tlsSettings"] = ["serverName": "\(j["sni"] ?? host)", "allowInsecure": false] }
        let user: [String: Any] = ["id": "\(j["id"] ?? "")", "alterId": Int("\(j["aid"] ?? "0")") ?? 0, "security": "\(j["scy"] ?? "auto")"]
        return ["tag": "proxy", "protocol": "vmess", "settings": ["vnext": [["address": host, "port": Int("\(j["port"] ?? "443")") ?? 443, "users": [user]]]], "streamSettings": stream]
    }

    private static func trojan(_ raw: String) throws -> [String: Any] {
        guard let u = URLComponents(string: raw), let host = u.host, let password = u.user else { throw badConfig("Trojan") }
        let q = query(u)
        var stream: [String: Any] = ["network": q["type"] ?? "tcp", "security": q["security"] ?? "tls"]
        applyTransport(&stream, q)
        if stream["security"] as? String == "tls" {
            stream["tlsSettings"] = ["serverName": q["sni"] ?? host, "fingerprint": q["fp"] ?? "chrome", "allowInsecure": q["allowInsecure"] == "1"]
        }
        return ["tag": "proxy", "protocol": "trojan", "settings": ["servers": [["address": host, "port": u.port ?? 443, "password": password]]], "streamSettings": stream]
    }

    private static func shadowsocks(_ raw: String) throws -> [String: Any] {
        let body = String(raw.dropFirst(5)).split(separator: "#", maxSplits: 1).first.map(String.init) ?? ""
        var credentials = ""
        var host = ""
        var port = 8388
        if let u = URLComponents(string: raw), let h = u.host {
            host = h; port = u.port ?? 8388
            credentials = u.user ?? ""
            if let decoded = ConfigParser.decodeBase64(credentials), let text = String(data: decoded, encoding: .utf8) { credentials = text }
        } else if let data = ConfigParser.decodeBase64(body), let text = String(data: data, encoding: .utf8), let at = text.lastIndex(of: "@") {
            credentials = String(text[..<at])
            let hp = text[text.index(after: at)...].split(separator: ":", maxSplits: 1)
            host = hp.first.map(String.init) ?? ""
            port = hp.count > 1 ? Int(hp[1]) ?? 8388 : 8388
        }
        let cp = credentials.split(separator: ":", maxSplits: 1).map(String.init)
        guard cp.count == 2, !host.isEmpty else { throw badConfig("Shadowsocks") }
        return ["tag": "proxy", "protocol": "shadowsocks", "settings": ["servers": [["address": host, "port": port, "method": cp[0], "password": cp[1]]]]]
    }

    private static func socks(_ raw: String) throws -> [String: Any] {
        guard let u = URLComponents(string: raw), let host = u.host else { throw badConfig("SOCKS") }
        var server: [String: Any] = ["address": host, "port": u.port ?? 1080]
        if let user = u.user { server["users"] = [["user": user, "pass": u.password ?? ""]] }
        return ["tag": "proxy", "protocol": "socks", "settings": ["servers": [server]]]
    }

    private static func http(_ raw: String) throws -> [String: Any] {
        guard let u = URLComponents(string: raw), let host = u.host else { throw badConfig("HTTP") }
        var server: [String: Any] = ["address": host, "port": u.port ?? 8080]
        if let user = u.user { server["users"] = [["user": user, "pass": u.password ?? ""]] }
        return ["tag": "proxy", "protocol": "http", "settings": ["servers": [server]]]
    }

    private static func query(_ u: URLComponents) -> [String: String] {
        Dictionary(uniqueKeysWithValues: (u.queryItems ?? []).map { ($0.name, $0.value ?? "") })
    }

    private static func applyTransport(_ stream: inout [String: Any], _ q: [String: String]) {
        let network = q["type"] ?? "tcp"
        if network == "ws" {
            stream["wsSettings"] = ["path": q["path"] ?? "/", "headers": ["Host": q["host"] ?? ""]]
        } else if network == "grpc" {
            stream["grpcSettings"] = ["serviceName": q["serviceName"] ?? q["path"] ?? "", "multiMode": q["mode"] == "multi"]
        } else if network == "httpupgrade" {
            stream["httpupgradeSettings"] = ["path": q["path"] ?? "/", "host": q["host"] ?? ""]
        } else if network == "xhttp" || network == "splithttp" {
            stream["xhttpSettings"] = ["path": q["path"] ?? "/", "host": q["host"] ?? "", "mode": q["mode"] ?? "auto"]
        }
    }

    private static func normalizeDomain(_ value: String) -> String {
        if value.hasPrefix("*.") { return "domain:" + String(value.dropFirst(2)) }
        if value.contains(".") { return "domain:" + value }
        return value
    }

    private static func badConfig(_ name: String) -> NSError {
        NSError(domain: "materialTun", code: 1, userInfo: [NSLocalizedDescriptionKey: "Invalid \(name) configuration"])
    }
}

#if false
struct GlassCard<Content: View>: View {
    var padding: CGFloat = 18
    @ViewBuilder var content: Content
    var body: some View {
        content
            .padding(padding)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .stroke(.white.opacity(0.18), lineWidth: 1)
            }
            .shadow(color: .black.opacity(0.22), radius: 18, y: 9)
    }
}

enum PalazikPalette {
    static let background = Color(red: 0.035, green: 0.055, blue: 0.10)
    static let card = Color.white.opacity(0.07)
    static let cardBlue = Color.white.opacity(0.10)
    static let activeCard = Color.accentColor.opacity(0.18)
    static let nav = Color.white.opacity(0.08)
    static let mint = Color(red: 0.42, green: 0.72, blue: 1.0)
    static let mintDark = Color.white
    static let purple = Color.accentColor.opacity(0.34)
    static let onSurface = Color.white.opacity(0.94)
    static let outline = Color.white.opacity(0.55)
}

struct RootView: View {
    @EnvironmentObject private var store: AppStore

    var body: some View {
        HStack(spacing: 0) {
            MaterialNavigationRail()
                .padding(.leading, 10)
                .padding(.vertical, 10)
            ZStack {
                LiquidBackground()
                Group {
                    switch store.tab {
                    case .home: HomeView()
                    case .servers: ServersView()
                    case .settings: SettingsView()
                    }
                }
                .padding(.horizontal, 18)
                .padding(.vertical, 16)
                if let toast = store.toast {
                    VStack {
                        Text(toast)
                            .font(.system(size: 13, weight: .semibold))
                            .padding(.horizontal, 16).padding(.vertical, 10)
                            .background(PalazikPalette.activeCard, in: Capsule())
                            .shadow(radius: 18)
                            .padding(.top, 18)
                        Spacer()
                    }
                }
            }
        }
        .foregroundStyle(PalazikPalette.onSurface)
        .frame(minWidth: 700, idealWidth: 760, minHeight: 500, idealHeight: 560)
        .animation(.spring(response: 0.38, dampingFraction: 0.82), value: store.tab)
        .animation(.easeInOut(duration: 0.2), value: store.toast)
        .onOpenURL { url in
            if ["vless", "vmess", "trojan", "ss", "socks", "socks5"].contains(url.scheme?.lowercased() ?? "") {
                let count = store.addProfiles(from: url.absoluteString)
                store.showToast(count > 0 ? "Configuration added" : "Link not recognized")
                store.tab = .servers
            } else if url.isFileURL {
                store.importFiles([url])
                store.tab = .servers
            }
        }
    }
}

struct MaterialNavigationRail: View {
    @EnvironmentObject private var store: AppStore
    @Namespace private var selectionIndicator

    var body: some View {
        VStack(spacing: 2) {
            ZStack {
                RoundedRectangle(cornerRadius: 18).fill(PalazikPalette.purple)
                Image(systemName: "shield.lefthalf.filled")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(PalazikPalette.mint)
            }
            .frame(width: 48, height: 48)
            .padding(.bottom, 6)

            ForEach(AppTab.allCases, id: \.self) { tab in
                Button {
                    guard store.tab != tab else { return }
                    withAnimation(.spring(response: 0.46, dampingFraction: 0.78, blendDuration: 0.12)) {
                        store.tab = tab
                    }
                } label: {
                    VStack(spacing: 5) {
                        ZStack {
                            if store.tab == tab {
                                Capsule()
                                    .fill(.ultraThinMaterial)
                                    .overlay {
                                        Capsule()
                                            .fill(Color.accentColor.opacity(0.22))
                                            .overlay { Capsule().stroke(.white.opacity(0.24)) }
                                    }
                                    .matchedGeometryEffect(
                                        id: "material-navigation-selection",
                                        in: selectionIndicator,
                                        properties: .frame,
                                        anchor: .center,
                                        isSource: true
                                    )
                                    .shadow(color: PalazikPalette.mint.opacity(0.12), radius: 8, y: 3)
                            }
                            Image(systemName: tab.icon)
                                .font(.system(size: 18, weight: .medium))
                                .symbolEffect(.bounce, value: store.tab == tab)
                        }
                        .frame(width: store.tab == tab ? 62 : 56, height: 34)
                        Text(tab.rawValue)
                            .font(.system(size: 10, weight: store.tab == tab ? .semibold : .regular))
                    }
                    .frame(width: 78, height: 68)
                    .contentShape(Rectangle())
                    .foregroundStyle(store.tab == tab ? PalazikPalette.onSurface : PalazikPalette.onSurface.opacity(0.7))
                }
                .buttonStyle(.plain)
            }
            Spacer()
        }
        .padding(.vertical, 12)
        .frame(width: 82)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .stroke(.white.opacity(0.20), lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.28), radius: 24, y: 10)
        .padding(.trailing, 10)
        .animation(.spring(response: 0.46, dampingFraction: 0.78), value: store.tab)
    }
}

struct LiquidBackground: View {
    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(red: 0.025, green: 0.045, blue: 0.085),
                    Color(red: 0.055, green: 0.075, blue: 0.14)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            Circle().fill(.blue.opacity(0.28)).frame(width: 380).blur(radius: 90).offset(x: 260, y: -210)
            Circle().fill(.purple.opacity(0.22)).frame(width: 340).blur(radius: 90).offset(x: -230, y: 230)
        }
        .ignoresSafeArea()
    }
}

struct BottomBar: View {
    @EnvironmentObject private var store: AppStore
    var body: some View {
        HStack(spacing: 8) {
            ForEach(AppTab.allCases, id: \.self) { tab in
                Button {
                    store.tab = tab
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: tab.icon)
                        if store.tab == tab { Text(tab.rawValue) }
                    }
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(store.tab == tab ? PalazikPalette.mintDark : Color.white.opacity(0.72))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(store.tab == tab ? PalazikPalette.mint : .clear, in: Capsule())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(6)
        .background(PalazikPalette.nav.opacity(0.97), in: Capsule())
        .overlay { Capsule().stroke(.white.opacity(0.025)) }
        .shadow(color: .black.opacity(0.38), radius: 18, y: 8)
    }
}

struct HomeView: View {
    @EnvironmentObject private var store: AppStore
    @State private var now = Date()

    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                HStack {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("materialTun")
                            .font(.system(size: 30, weight: .semibold, design: .rounded))
                        Text(store.selectedServer?.name ?? "No profile selected")
                            .font(.system(size: 13))
                            .foregroundStyle(PalazikPalette.onSurface.opacity(0.72))
                    }
                    Spacer()
                    StatusPill()
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 18) {
                        HomeServerPill()
                        Text(store.state.title)
                            .font(.system(size: 23, weight: .medium, design: .rounded))
                        Button { store.toggleConnection() } label: {
                            Label(store.state.connected ? "Disconnect" : "Connect",
                                  systemImage: store.state.connected ? "stop.fill" : "play.fill")
                                .font(.system(size: 16, weight: .semibold))
                                .padding(.horizontal, 24).padding(.vertical, 14)
                                .background(PalazikPalette.mint, in: Capsule())
                                .foregroundStyle(PalazikPalette.mintDark)
                        }
                        .buttonStyle(.plain)
                        .disabled(store.state == .connecting || store.state == .disconnecting)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    .padding(18)
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 20))
                    .overlay { RoundedRectangle(cornerRadius: 20).stroke(.white.opacity(0.16)) }

                    ConnectOrb()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 20))
                        .overlay {
                            RoundedRectangle(cornerRadius: 20)
                                .fill(Color.accentColor.opacity(0.12))
                                .overlay { RoundedRectangle(cornerRadius: 20).stroke(.white.opacity(0.18)) }
                        }
                }
                .frame(minHeight: 210)

                HStack(spacing: 12) {
                    MetricCard(icon: "arrow.down", title: "Download", value: formatRate(store.downRate), tint: PalazikPalette.mint)
                    MetricCard(icon: "arrow.up", title: "Upload", value: formatRate(store.upRate), tint: PalazikPalette.mint)
                    CompactStat(icon: "clock.fill", title: "Session", value: duration)
                }
            }
            .padding(.bottom, 6)
        }
        .scrollIndicators(.hidden)
        .onReceive(Timer.publish(every: 1, on: .main, in: .common).autoconnect()) { now = $0 }
    }

    private var duration: String {
        guard case let .connected(start) = store.state else { return "00:00" }
        let seconds = Int(now.timeIntervalSince(start))
        return String(format: "%02d:%02d", seconds / 60, seconds % 60)
    }
    private func pingText(_ ping: Int?) -> String {
        guard let ping else { return "Ping" }
        if ping == -1 { return "…" }
        if ping == 0 { return "—" }
        return "\(ping) ms"
    }
    private func formatRate(_ value: Double) -> String {
        if value > 1_000_000 { return String(format: "%.1f MB/s", value / 1_000_000) }
        return String(format: "%.0f KB/s", value / 1_000)
    }
}

struct HomeServerPill: View {
    @EnvironmentObject private var store: AppStore
    var body: some View {
        Button { store.tab = .servers } label: {
            HStack(spacing: 10) {
                Image(systemName: "server.rack").foregroundStyle(PalazikPalette.mint)
                VStack(alignment: .leading, spacing: 0) {
                    Text(store.selectedServer?.name ?? "No profile selected")
                        .font(.system(size: 14, weight: .bold)).lineLimit(1)
                    Text(store.selectedServer.map { "\($0.host):\($0.port)" } ?? "Open Profiles to import")
                        .font(.system(size: 11, weight: .medium)).foregroundStyle(.white.opacity(0.62)).lineLimit(1)
                }
            }
            .padding(.horizontal, 15).padding(.vertical, 10)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14))
            .overlay { RoundedRectangle(cornerRadius: 14).stroke(.white.opacity(0.14)) }
        }
        .buttonStyle(.plain)
    }
}

struct ConnectOrb: View {
    @EnvironmentObject private var store: AppStore
    var body: some View {
        ZStack {
            Circle()
                .fill(PalazikPalette.mint.opacity(0.14))
                .frame(width: 180, height: 180)
            Circle()
                .fill(store.state.connected ? PalazikPalette.mint : PalazikPalette.cardBlue)
                .frame(width: 122, height: 122)
            Button { store.toggleConnection() } label: {
                VStack(spacing: 8) {
                    Image(systemName: store.state.connected ? "shield.checkered" : "shield")
                        .font(.system(size: 42, weight: .medium))
                }
                .foregroundStyle(store.state.connected ? PalazikPalette.mintDark : PalazikPalette.mint)
                .frame(width: 160, height: 160)
                .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .disabled(store.state == .connecting || store.state == .disconnecting)
        }
        .frame(height: 190)
    }
}

struct StatusPill: View {
    @EnvironmentObject private var store: AppStore
    var body: some View {
        HStack(spacing: 8) {
            Circle().fill(store.state.connected ? PalazikPalette.mint : .gray).frame(width: 8)
            Text(store.state.connected ? "CONNECTED" : "DISCONNECTED")
                .font(.system(size: 12, weight: .bold, design: .rounded))
                .foregroundStyle(store.state.connected ? PalazikPalette.mint : Color.white.opacity(0.62))
        }
        .padding(.horizontal, 18).padding(.vertical, 9)
        .background((store.state.connected ? PalazikPalette.mint : .gray).opacity(0.13), in: Capsule())
    }
}

struct ConnectedServerCard: View {
    @EnvironmentObject private var store: AppStore
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "checkmark.shield.fill").font(.title2).foregroundStyle(PalazikPalette.mint)
            VStack(alignment: .leading, spacing: 2) {
                Text(store.selectedServer?.name ?? "Active profile").font(.system(size: 14, weight: .bold))
                Text("Connected · \(store.selectedServer?.host ?? "")")
                    .font(.caption).foregroundStyle(.white.opacity(0.62))
            }
            Spacer()
        }
        .padding(15)
        .background(PalazikPalette.card, in: RoundedRectangle(cornerRadius: 18))
    }
}

struct MetricCard: View {
    let icon: String
    let title: String
    let value: String
    let tint: Color
    var body: some View {
        GlassCard(padding: 14) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 6) {
                    Image(systemName: icon).foregroundStyle(tint)
                    Text(title).font(.caption).foregroundStyle(.white.opacity(0.58))
                }
                Text(value).font(.system(size: 20, weight: .bold, design: .rounded))
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

struct CompactStat: View {
    let icon: String
    let title: String
    let value: String
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Image(systemName: icon).foregroundStyle(PalazikPalette.mint)
            Text(value).font(.system(size: 11, weight: .semibold)).lineLimit(1)
            Text(title).font(.caption2).foregroundStyle(.white.opacity(0.5))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
        .overlay { RoundedRectangle(cornerRadius: 16).stroke(.white.opacity(0.12)) }
    }
}

struct QuickItem: View {
    let icon: String
    let label: String
    var body: some View {
        HStack(spacing: 7) {
            Image(systemName: icon).foregroundStyle(.cyan)
            Text(label).font(.system(size: 12, weight: .medium)).lineLimit(1)
        }
    }
}

struct ServersView: View {
    @EnvironmentObject private var store: AppStore
    @State private var search = ""
    @State private var showingAdd = false
    @State private var showingSubscription = false
    @State private var editingServer: ServerProfile?

    private var filtered: [ServerProfile] {
        guard !search.isEmpty else { return store.servers }
        return store.servers.filter { $0.name.localizedCaseInsensitiveContains(search) || $0.host.localizedCaseInsensitiveContains(search) }
    }

    var body: some View {
        VStack(spacing: 16) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Profiles").font(.system(size: 40, weight: .regular, design: .rounded))
                    Text("Manage servers and subscriptions · \(store.servers.count) profiles")
                        .foregroundStyle(PalazikPalette.onSurface.opacity(0.62))
                }
                Spacer()
                Button { store.pingAll() } label: { Image(systemName: "network") }
                    .help("Test all servers")
                    .buttonStyle(PalazikIconButton())
                Menu {
                    Button("Paste Configuration") { showingAdd = true }
                    Button("Add Subscription") { showingSubscription = true }
                    Button("Import File…") { openFiles() }
                } label: {
                    Label("Import profile", systemImage: "plus")
                        .font(.system(size: 14, weight: .semibold))
                        .padding(.horizontal, 16).padding(.vertical, 10)
                        .background(PalazikPalette.mint, in: Capsule())
                        .foregroundStyle(PalazikPalette.mintDark)
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
            }

            HStack {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("Search profiles", text: $search)
                    .textFieldStyle(.plain)
            }
            .padding(.horizontal, 14).padding(.vertical, 11)
            .background(PalazikPalette.cardBlue, in: RoundedRectangle(cornerRadius: 16))

            if store.servers.isEmpty {
                Spacer()
                VStack(spacing: 14) {
                    Image(systemName: "key.fill").font(.system(size: 44)).foregroundStyle(PalazikPalette.mint)
                    Text("No profiles yet").font(.title3.bold())
                    Text("Import VLESS, VMess, Trojan, Shadowsocks,\nSOCKS or a subscription URL.")
                        .multilineTextAlignment(.center).foregroundStyle(.secondary)
                    Button("Import profile") { showingAdd = true }
                        .buttonStyle(.plain)
                        .padding(.horizontal, 18).padding(.vertical, 10)
                        .background(PalazikPalette.mint, in: Capsule())
                        .foregroundStyle(PalazikPalette.mintDark)
                }
                Spacer()
            } else {
                ScrollView {
                    LazyVStack(spacing: 10) {
                        if !store.subscriptions.isEmpty { subscriptionsSection }
                        ForEach(filtered) { server in
                            ServerRow(server: server, editingServer: $editingServer)
                        }
                    }
                    .padding(.vertical, 4)
                }
                .scrollIndicators(.hidden)
            }
        }
        .sheet(isPresented: $showingAdd) { AddConfigSheet() }
        .sheet(isPresented: $showingSubscription) { AddSubscriptionSheet() }
        .sheet(item: $editingServer) { server in EditServerSheet(server: server) }
    }

    private var subscriptionsSection: some View {
        VStack(spacing: 8) {
            ForEach(store.subscriptions) { sub in
                HStack {
                    Image(systemName: "link.circle.fill").foregroundStyle(.purple)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(sub.name).font(.system(size: 13, weight: .semibold))
                        Text(sub.lastUpdated?.formatted(date: .abbreviated, time: .shortened) ?? "Never updated")
                            .font(.caption2).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button { Task { await store.updateSubscription(sub) } } label: { Image(systemName: "arrow.clockwise") }
                        .buttonStyle(.plain)
                    Button { store.deleteSubscription(sub) } label: { Image(systemName: "trash") }
                        .buttonStyle(.plain).foregroundStyle(.red.opacity(0.8))
                }
                .padding(12)
                .background(PalazikPalette.nav, in: RoundedRectangle(cornerRadius: 16))
            }
        }
    }

    private func openFiles() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.allowedContentTypes = [.plainText, .json, .data]
        if panel.runModal() == .OK { store.importFiles(panel.urls) }
    }
}

struct PalazikIconButton: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 17, weight: .semibold))
            .frame(width: 38, height: 38)
            .background(PalazikPalette.card, in: Circle())
            .foregroundStyle(.white.opacity(configuration.isPressed ? 0.5 : 0.82))
    }
}

struct ServerRow: View {
    @EnvironmentObject private var store: AppStore
    let server: ServerProfile
    @Binding var editingServer: ServerProfile?
    var selected: Bool { store.selectedServerID == server.id }
    var body: some View {
        Button {
            store.selectedServerID = server.id
            store.save()
        } label: {
            HStack(spacing: 13) {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Text(server.type.rawValue.uppercased())
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(PalazikPalette.mint)
                            .padding(.horizontal, 9).padding(.vertical, 4)
                            .background(PalazikPalette.mint.opacity(0.13), in: Capsule())
                        if selected {
                            Text("ACTIVE")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundStyle(PalazikPalette.mint)
                                .padding(.horizontal, 9).padding(.vertical, 4)
                                .background(PalazikPalette.mint.opacity(0.13), in: Capsule())
                        }
                    }
                    HStack(spacing: 7) {
                        Text(flag(for: server.host)).font(.system(size: 18))
                        Text(server.name).font(.system(size: 14, weight: .semibold)).lineLimit(1)
                        if server.favorite { Image(systemName: "star.fill").font(.caption2).foregroundStyle(.yellow) }
                    }
                    Text("\(server.host):\(server.port)")
                        .font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
                Spacer()
                pingView
                Menu {
                    Button(server.favorite ? "Remove from Favorites" : "Add to Favorites") {
                        if let i = store.servers.firstIndex(where: { $0.id == server.id }) {
                            store.servers[i].favorite.toggle(); store.save()
                        }
                    }
                    Button("Test Ping") { store.ping(server.id) }
                    Button("Rename") { editingServer = server }
                    Button("Copy Link") {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(server.rawURI, forType: .string)
                    }
                    Divider()
                    Button("Delete", role: .destructive) {
                        store.servers.removeAll { $0.id == server.id }
                        if store.selectedServerID == server.id { store.selectedServerID = store.servers.first?.id }
                        store.save()
                    }
                } label: {
                    Image(systemName: "ellipsis").frame(width: 28, height: 28)
                }
                .menuStyle(.borderlessButton).fixedSize()
            }
            .padding(16)
            .frame(minHeight: 106)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 20))
            .overlay {
                RoundedRectangle(cornerRadius: 20)
                    .fill(selected ? Color.accentColor.opacity(0.18) : .clear)
                    .overlay { RoundedRectangle(cornerRadius: 20).stroke(.white.opacity(selected ? 0.22 : 0.12)) }
            }
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder private var pingView: some View {
        if let ping = server.ping {
            if ping == -1 { ProgressView().controlSize(.small).frame(width: 42) }
            else {
                Text(ping == 0 ? "—" : "\(ping) ms")
                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                    .foregroundStyle(pingColor(ping)).frame(width: 54, alignment: .trailing)
            }
        } else { Text("PING").font(.caption2).foregroundStyle(.tertiary).frame(width: 54) }
    }
    private func pingColor(_ ping: Int) -> Color {
        if ping == 0 { return .secondary }
        if ping < 100 { return .green }
        if ping < 220 { return .orange }
        return .red
    }
    private func flag(for host: String) -> String {
        let value = host.lowercased()
        if value.contains("fi") || value.contains("fin") { return "🇫🇮" }
        if value.contains("de") || value.contains("ger") { return "🇩🇪" }
        if value.contains("nl") { return "🇳🇱" }
        if value.contains("us") { return "🇺🇸" }
        if value.contains("ru") { return "🇷🇺" }
        if value.contains("jp") { return "🇯🇵" }
        return "🌐"
    }
}

struct AddConfigSheet: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.dismiss) private var dismiss
    @State private var text = ""
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Add Configuration").font(.title2.bold())
            Text("Paste one or more links, a Base64 subscription, or a complete Xray JSON configuration.")
                .foregroundStyle(.secondary)
            TextEditor(text: $text)
                .font(.system(.body, design: .monospaced))
                .scrollContentBackground(.hidden)
                .padding(10)
                .background(Color.black.opacity(0.18), in: RoundedRectangle(cornerRadius: 14))
                .frame(minHeight: 190)
            HStack {
                Button("From Clipboard") { text = NSPasteboard.general.string(forType: .string) ?? "" }
                Spacer()
                Button("Cancel") { dismiss() }
                Button("Add") {
                    let count = store.addProfiles(from: text)
                    store.showToast(count > 0 ? "Servers added: \(count)" : "Configuration not recognized")
                    if count > 0 { dismiss() }
                }
                .buttonStyle(.borderedProminent).disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(24).frame(width: 560)
    }
}

struct AddSubscriptionSheet: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var url = ""
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("New Subscription").font(.title2.bold())
            TextField("Name (optional)", text: $name)
            TextField("https://example.com/subscription", text: $url)
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                Button("Add") {
                    Task { await store.addSubscription(name: name, url: url); dismiss() }
                }
                .buttonStyle(.borderedProminent).disabled(url.isEmpty)
            }
        }
        .padding(24).frame(width: 500)
    }
}

struct EditServerSheet: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.dismiss) private var dismiss
    @State var server: ServerProfile
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Server").font(.title2.bold())
            TextField("Name", text: $server.name)
            HStack {
                TextField("Host", text: $server.host)
                TextField("Port", value: $server.port, format: .number).frame(width: 100)
            }
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                Button("Save") {
                    if let i = store.servers.firstIndex(where: { $0.id == server.id }) { store.servers[i] = server }
                    store.save(); dismiss()
                }.buttonStyle(.borderedProminent)
            }
        }.padding(24).frame(width: 480)
    }
}

struct SettingsView: View {
    @EnvironmentObject private var store: AppStore
    @State private var selection = "Connection"
    @Namespace private var settingsIndicator
    let sections = ["Connection", "Routing", "DNS and Network", "Automation", "Diagnostics"]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Settings").font(.system(size: 27, weight: .bold, design: .rounded))
            HStack(alignment: .top, spacing: 12) {
                GlassCard(padding: 7) {
                    VStack(spacing: 1) {
                        ForEach(sections, id: \.self) { item in
                            Button {
                                guard selection != item else { return }
                                withAnimation(.spring(response: 0.46, dampingFraction: 0.78)) {
                                    selection = item
                                }
                            } label: {
                                ZStack {
                                    if selection == item {
                                        RoundedRectangle(cornerRadius: 11)
                                            .fill(.ultraThinMaterial)
                                            .overlay {
                                                RoundedRectangle(cornerRadius: 11)
                                                    .fill(Color.accentColor.opacity(0.22))
                                                    .overlay { RoundedRectangle(cornerRadius: 11).stroke(.white.opacity(0.20)) }
                                            }
                                            .matchedGeometryEffect(
                                                id: "settings-selection",
                                                in: settingsIndicator,
                                                properties: .frame
                                            )
                                    }
                                    HStack {
                                        Image(systemName: icon(item)).frame(width: 20)
                                        Text(item)
                                        Spacer()
                                    }
                                    .padding(.horizontal, 10)
                                }
                                .font(.system(size: 12, weight: selection == item ? .semibold : .regular))
                                .frame(width: 164, height: 48)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                ScrollView {
                    GlassCard(padding: 15) {
                        settingsContent
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .id(selection)
                            .transition(.asymmetric(
                                insertion: .move(edge: .trailing).combined(with: .opacity),
                                removal: .move(edge: .leading).combined(with: .opacity)
                            ))
                    }
                    .padding(.bottom, 4)
                }
                .scrollIndicators(.hidden)
            }
        }
        .animation(.spring(response: 0.46, dampingFraction: 0.82), value: selection)
        .onChange(of: store.settings) { _, _ in store.save() }
    }

    @ViewBuilder private var settingsContent: some View {
        VStack(alignment: .leading, spacing: 17) {
            Text(selection).font(.title3.bold())
            Divider()
            switch selection {
            case "Connection": connection
            case "Routing": routing
            case "DNS and Network": network
            case "Automation": automation
            default: diagnostics
            }
        }
    }

    private var connection: some View {
        VStack(spacing: 13) {
            SettingPicker(title: "Mode", subtitle: "System Proxy requires no privileges; TUN covers more applications", selection: $store.settings.mode)
            SettingToggle(title: "Auto Reconnect", subtitle: "Restore the connection after a network failure", value: $store.settings.autoReconnect)
            SettingToggle(title: "Kill Switch", subtitle: "Prevent direct traffic if the TUN connection drops", value: $store.settings.killSwitch)
            SettingToggle(title: "Traffic Inspection", subtitle: "Detect HTTP, TLS, and QUIC for routing rules", value: $store.settings.sniffing)
            HStack {
                FieldSetting(title: "SOCKS Port", value: $store.settings.localSocksPort)
                FieldSetting(title: "HTTP Port", value: $store.settings.localHTTPPort)
            }
        }
    }

    private var routing: some View {
        VStack(spacing: 13) {
            SettingPicker(title: "Profile", subtitle: "Global, rules-based, or direct connection", selection: $store.settings.routeMode)
            SettingToggle(title: "Bypass LAN", subtitle: "Printers, AirDrop, and local devices connect directly", value: $store.settings.bypassLAN)
            TokenEditor(title: "Direct Domains", values: $store.settings.directDomains, placeholder: "example.com")
            TokenEditor(title: "Blocked Domains", values: $store.settings.blockedDomains, placeholder: "ads.example.com")
            TokenEditor(title: "Excluded CIDRs", values: $store.settings.excludedCIDRs, placeholder: "192.168.0.0/16")
            TokenEditor(title: "Direct Processes (TUN)", values: $store.settings.excludedApps, placeholder: "AppStore")
        }
    }

    private var network: some View {
        VStack(spacing: 13) {
            SettingToggle(title: "Secure DNS", subtitle: "Use the selected DNS inside the tunnel", value: $store.settings.dnsEnabled)
            HStack {
                Text("DNS Server"); Spacer()
                TextField("1.1.1.1", text: $store.settings.dnsServer).frame(width: 180)
            }
            SettingToggle(title: "IPv6", subtitle: "Allow IPv6 traffic", value: $store.settings.ipv6)
            HStack {
                Text("Test URL"); Spacer()
                TextField("https://…", text: $store.settings.testURL).frame(width: 280)
            }
        }
    }

    private var automation: some View {
        VStack(spacing: 13) {
            SettingToggle(title: "Connect at Launch", subtitle: "Start the last selected server", value: $store.settings.autoConnect)
            SettingToggle(title: "Launch at Login", subtitle: "Open materialTun after signing in to macOS", value: $store.settings.launchAtLogin)
            SettingToggle(title: "Disconnect on Sleep", subtitle: "Stop the tunnel when the Mac goes to sleep", value: $store.settings.disconnectOnSleep)
            Text("Subscriptions are updated automatically when the application launches.")
                .font(.caption).foregroundStyle(.secondary).frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var diagnostics: some View {
        VStack(alignment: .leading, spacing: 13) {
            HStack {
                Text("Log Level")
                Spacer()
                Picker("", selection: $store.settings.logLevel) {
                    ForEach(["none", "error", "warning", "info", "debug"], id: \.self) { Text($0.capitalized) }
                }.frame(width: 140)
            }
            ScrollView {
                Text(store.logs.isEmpty ? "Logs will appear after connecting." : store.logs.joined(separator: "\n"))
                    .font(.system(size: 11, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
            }
            .frame(height: 210)
            .background(Color.black.opacity(0.22), in: RoundedRectangle(cornerRadius: 12))
            HStack {
                Button("Clear") { store.logs.removeAll() }
                Button("Open Data Folder") {
                    let url = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("materialTun")
                    NSWorkspace.shared.open(url)
                }
            }
        }
    }

    private func icon(_ item: String) -> String {
        switch item {
        case "Connection": "bolt.horizontal.circle"
        case "Routing": "point.3.filled.connected.trianglepath.dotted"
        case "DNS and Network": "network"
        case "Automation": "clock.arrow.circlepath"
        default: "stethoscope"
        }
    }
}

struct SettingToggle: View {
    let title: String
    let subtitle: String
    @Binding var value: Bool
    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.system(size: 13, weight: .medium))
                Text(subtitle).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Toggle("", isOn: $value).labelsHidden().toggleStyle(.switch)
        }
    }
}

struct SettingPicker<T: Hashable & Identifiable & RawRepresentable>: View where T.RawValue == String {
    let title: String
    let subtitle: String
    @Binding var selection: T
    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.system(size: 13, weight: .medium))
                Text(subtitle).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Picker("", selection: $selection) {
                ForEach(ArrayMirror<T>.cases, id: \.id) { Text($0.rawValue).tag($0) }
            }.frame(width: 190)
        }
    }
}

enum ArrayMirror<T> {
    static var cases: [T] {
        if T.self == ConnectionMode.self { return ConnectionMode.allCases as! [T] }
        if T.self == RouteMode.self { return RouteMode.allCases as! [T] }
        return []
    }
}

struct FieldSetting: View {
    let title: String
    @Binding var value: Int
    var body: some View {
        HStack {
            Text(title).font(.caption)
            TextField("", value: $value, format: .number).frame(width: 70)
        }
        .padding(10).background(Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 12))
    }
}

struct TokenEditor: View {
    let title: String
    @Binding var values: [String]
    let placeholder: String
    @State private var newValue = ""
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.system(size: 13, weight: .medium))
            FlowTokens(values: values) { value in values.removeAll { $0 == value } }
            HStack {
                TextField(placeholder, text: $newValue)
                    .onSubmit(add)
                Button { add() } label: { Image(systemName: "plus") }
                    .disabled(newValue.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(12).background(Color.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 14))
    }
    private func add() {
        let value = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty, !values.contains(value) else { return }
        values.append(value); newValue = ""
    }
}

struct FlowTokens: View {
    let values: [String]
    let remove: (String) -> Void
    var body: some View {
        HStack {
            ForEach(values.prefix(5), id: \.self) { value in
                HStack(spacing: 5) {
                    Text(value).lineLimit(1)
                    Button { remove(value) } label: { Image(systemName: "xmark.circle.fill") }.buttonStyle(.plain)
                }
                .font(.caption2).padding(.horizontal, 8).padding(.vertical, 5)
                .background(.thinMaterial, in: Capsule())
            }
            if values.count > 5 { Text("+\(values.count - 5)").font(.caption).foregroundStyle(.secondary) }
            Spacer()
        }
    }
}

struct MenuBarView: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.openWindow) private var openWindow
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Circle().fill(store.state.connected ? .green : .gray).frame(width: 8)
                Text(store.state.title).font(.headline)
            }
            if let server = store.selectedServer {
                Text(server.name).font(.subheadline)
                Text("\(server.type.rawValue) · \(server.host)").font(.caption).foregroundStyle(.secondary)
            }
            Divider()
            Button(store.state.connected ? "Disconnect" : "Connect") { store.toggleConnection() }
                .keyboardShortcut("v")
            Menu("Select Server") {
                ForEach(store.servers) { server in
                    Button {
                        store.selectedServerID = server.id; store.save()
                    } label: {
                        if store.selectedServerID == server.id { Label(server.name, systemImage: "checkmark") }
                        else { Text(server.name) }
                    }
                }
            }
            Divider()
            Button("Open materialTun") {
                NSApp.activate(ignoringOtherApps: true)
                openWindow(id: "main")
            }
            Button("Quit") { NSApp.terminate(nil) }
        }
        .padding(12).frame(width: 260)
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        Task { @MainActor in
            let store = AppStore.shared
            store.recoverProxyIfNeeded()
            for subscription in store.subscriptions where subscription.autoUpdate {
                await store.updateSubscription(subscription)
            }
            if store.settings.autoConnect, store.selectedServer != nil {
                store.connect()
            }
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        MainActor.assumeIsolated {
            AppStore.shared.disconnect(silent: true)
        }
    }
}

@main
struct materialTunApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var store = AppStore.shared

    var body: some Scene {
        Window("materialTun", id: "main") {
            RootView()
                .environmentObject(store)
                .preferredColorScheme(.dark)
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 760, height: 560)
        .commands {
            CommandGroup(after: .appInfo) {
                Button("Connect / Disconnect") { store.toggleConnection() }
                    .keyboardShortcut("v", modifiers: [.command, .shift])
            }
        }

        MenuBarExtra {
            MenuBarView().environmentObject(store)
        } label: {
            Image(systemName: store.state.connected ? "shield.fill" : "shield")
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView().environmentObject(store).padding(24).frame(width: 720, height: 560)
        }
    }
}
#endif
