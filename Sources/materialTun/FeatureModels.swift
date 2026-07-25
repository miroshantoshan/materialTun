import SwiftUI
import AppKit
import Foundation
import Network
import CoreImage
import ServiceManagement
import Darwin

enum LatencyMethod: String, Codable, CaseIterable, Identifiable {
    case tcp = "TCP"
    case httpHead = "HTTP HEAD"
    case httpGet = "HTTP GET"
    var id: String { rawValue }
}

enum ProfileSort: String, CaseIterable, Identifiable {
    case name = "Name"
    case latency = "Latency"
    var id: String { rawValue }
}

struct ProfileOptions: Codable, Hashable {
    var allowInsecure = false
    var mux = false
    var tlsFragment = false
    var fragmentLength = "10-20"
    var fragmentInterval = "10-20"
}

struct SubscriptionDetails: Codable, Hashable {
    var upload: Int64?
    var download: Int64?
    var total: Int64?
    var expire: Date?
    var lastError: String?
    var iconURL: String?
}

struct VPNWorkspace: Codable, Identifiable, Hashable {
    var id = UUID()
    var name: String
    var colorHex: String
    var servers: [ServerProfile]
    var subscriptions: [Subscription]
    var selectedServerID: UUID?
}

struct materialTunBackup: Codable {
    var workspaces: [VPNWorkspace]
    var activeWorkspaceID: UUID?
    var settings: AppSettings
    var profileOptions: [UUID: ProfileOptions]
    var subscriptionDetails: [UUID: SubscriptionDetails]
}

extension AppStore {
    var activeWorkspace: VPNWorkspace? {
        workspaces.first { $0.id == activeWorkspaceID }
    }

    func loadExtendedState() {
        let workspaceURL = supportURL.appendingPathComponent("workspaces.json")
        if let data = try? Data(contentsOf: workspaceURL),
           let decoded = try? JSONDecoder().decode([VPNWorkspace].self, from: data),
           !decoded.isEmpty {
            workspaces = decoded.map { workspace in
                var migrated = workspace
                if migrated.name == "\u{41B}\u{438}\u{447}\u{43D}\u{44B}\u{439}" {
                    migrated.name = "Personal"
                } else if migrated.name == "\u{41D}\u{43E}\u{432}\u{44B}\u{439} \u{43F}\u{440}\u{43E}\u{444}\u{438}\u{43B}\u{44C}" {
                    migrated.name = "New Workspace"
                }
                return migrated
            }
            let savedID = UserDefaults.standard.string(forKey: "materialTunActiveWorkspace").flatMap(UUID.init(uuidString:))
            activeWorkspaceID = workspaces.contains(where: { $0.id == savedID }) ? savedID : workspaces[0].id
            loadWorkspace(activeWorkspaceID!)
        } else {
            let workspace = VPNWorkspace(
                name: "Personal",
                colorHex: "6750A4",
                servers: servers,
                subscriptions: subscriptions,
                selectedServerID: selectedServerID
            )
            workspaces = [workspace]
            activeWorkspaceID = workspace.id
        }

        if let data = try? Data(contentsOf: supportURL.appendingPathComponent("profile-options.json")),
           let value = try? JSONDecoder().decode([UUID: ProfileOptions].self, from: data) {
            profileOptions = value
        }
        if let data = try? Data(contentsOf: supportURL.appendingPathComponent("subscription-details.json")),
           let value = try? JSONDecoder().decode([UUID: SubscriptionDetails].self, from: data) {
            subscriptionDetails = value
        }
    }

    func saveExtendedState() {
        try? FileManager.default.createDirectory(at: supportURL, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        if let data = try? encoder.encode(workspaces) {
            try? data.write(to: supportURL.appendingPathComponent("workspaces.json"), options: .atomic)
        }
        if let data = try? encoder.encode(profileOptions) {
            try? data.write(to: supportURL.appendingPathComponent("profile-options.json"), options: .atomic)
        }
        if let data = try? encoder.encode(subscriptionDetails) {
            try? data.write(to: supportURL.appendingPathComponent("subscription-details.json"), options: .atomic)
        }
        UserDefaults.standard.set(activeWorkspaceID?.uuidString, forKey: "materialTunActiveWorkspace")
    }

    func persistActiveWorkspace() {
        guard let id = activeWorkspaceID,
              let index = workspaces.firstIndex(where: { $0.id == id }) else { return }
        workspaces[index].servers = servers
        workspaces[index].subscriptions = subscriptions
        workspaces[index].selectedServerID = selectedServerID
    }

    func switchWorkspace(_ id: UUID) {
        guard id != activeWorkspaceID, workspaces.contains(where: { $0.id == id }) else { return }
        if state.connected { disconnect() }
        persistActiveWorkspace()
        activeWorkspaceID = id
        loadWorkspace(id)
        save()
        showToast(loc("Workspace switched"))
    }

    func createWorkspace(name: String, colorHex: String) {
        persistActiveWorkspace()
        let workspace = VPNWorkspace(
            name: name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "New Workspace" : name,
            colorHex: colorHex,
            servers: [],
            subscriptions: [],
            selectedServerID: nil
        )
        workspaces.append(workspace)
        activeWorkspaceID = workspace.id
        loadWorkspace(workspace.id)
        save()
    }

    func renameWorkspace(_ id: UUID, name: String) {
        guard let index = workspaces.firstIndex(where: { $0.id == id }) else { return }
        workspaces[index].name = name
        saveExtendedState()
    }

    func deleteWorkspace(_ id: UUID) {
        guard workspaces.count > 1, let index = workspaces.firstIndex(where: { $0.id == id }) else { return }
        workspaces.remove(at: index)
        if activeWorkspaceID == id {
            activeWorkspaceID = workspaces[0].id
            loadWorkspace(workspaces[0].id)
        }
        save()
    }

    private func loadWorkspace(_ id: UUID) {
        guard let workspace = workspaces.first(where: { $0.id == id }) else { return }
        servers = workspace.servers
        subscriptions = workspace.subscriptions
        selectedServerID = workspace.selectedServerID ?? workspace.servers.first?.id
    }

    func duplicate(_ server: ServerProfile) {
        var copy = server
        copy.id = UUID()
        copy.name += " Copy"
        copy.subscriptionID = nil
        copy.lastUsed = nil
        copy.ping = nil
        servers.append(copy)
        profileOptions[copy.id] = profileOptions[server.id]
        save()
    }

    func deleteServer(_ server: ServerProfile) {
        servers.removeAll { $0.id == server.id }
        profileOptions[server.id] = nil
        if selectedServerID == server.id { selectedServerID = servers.first?.id }
        save()
    }

    func exportProfile(_ server: ServerProfile, format: String) {
        let value: String
        switch format {
        case "JSON":
            let object: [String: Any] = [
                "name": server.name, "protocol": server.type.rawValue,
                "server": server.host, "port": server.port, "link": server.rawURI
            ]
            let data = try? JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys])
            value = data.flatMap { String(data: $0, encoding: .utf8) } ?? server.rawURI
        case "palazikVPN":
            value = "palazikvpn://import?url=" + (server.rawURI.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "")
        default:
            value = server.rawURI
        }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(value, forType: .string)
        showToast(locf("%@ copied", format))
    }

    func saveProfileQR(_ server: ServerProfile) {
        guard let data = server.rawURI.data(using: .utf8),
              let filter = CIFilter(name: "CIQRCodeGenerator") else {
            showToast(loc("Could not create QR code"))
            return
        }
        filter.setValue(data, forKey: "inputMessage")
        filter.setValue("M", forKey: "inputCorrectionLevel")
        guard let output = filter.outputImage?.transformed(by: CGAffineTransform(scaleX: 9, y: 9)) else { return }
        let representation = NSCIImageRep(ciImage: output)
        let image = NSImage(size: representation.size)
        image.addRepresentation(representation)
        guard let tiff = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiff),
              let png = bitmap.representation(using: .png, properties: [:]) else { return }
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "\(server.name)-QR.png"
        panel.allowedContentTypes = [.png]
        if panel.runModal() == .OK, let url = panel.url {
            do { try png.write(to: url, options: .atomic); showToast(loc("QR code saved")) }
            catch { showToast(error.localizedDescription) }
        }
    }

    func testLatency(_ id: UUID, method: LatencyMethod? = nil) {
        guard let server = servers.first(where: { $0.id == id }) else { return }
        let selectedMethod = method ?? LatencyMethod(rawValue: UserDefaults.standard.string(forKey: "LatencyMethod") ?? "") ?? .tcp
        if let index = servers.firstIndex(where: { $0.id == id }) { servers[index].ping = -1 }
        Task {
            let result = await LatencyTester.measure(server: server, method: selectedMethod, testURL: settings.testURL)
            if let index = servers.firstIndex(where: { $0.id == id }) {
                servers[index].ping = result ?? 0
                save()
            }
        }
    }

    func testAllConcurrently(method: LatencyMethod) {
        UserDefaults.standard.set(method.rawValue, forKey: "LatencyMethod")
        for index in servers.indices { servers[index].ping = -1 }
        let snapshot = servers
        Task {
            await withTaskGroup(of: (UUID, Int?).self) { group in
                for server in snapshot {
                    group.addTask {
                        (server.id, await LatencyTester.measure(server: server, method: method, testURL: self.settings.testURL))
                    }
                }
                for await (id, latency) in group {
                    if let index = servers.firstIndex(where: { $0.id == id }) {
                        servers[index].ping = latency ?? 0
                    }
                }
            }
            save()
            showToast(loc("Latency test completed"))
        }
    }

    func selectFastest() {
        guard let fastest = servers.filter({ ($0.ping ?? 0) > 0 }).min(by: { ($0.ping ?? .max) < ($1.ping ?? .max) }) else {
            showToast(loc("Test latency first"))
            return
        }
        selectedServerID = fastest.id
        save()
        showToast(locf("Selected %@ · %d ms", fastest.name, fastest.ping ?? 0))
    }

    func refreshSubscriptionEnhanced(_ subscription: Subscription) async {
        guard let url = URL(string: subscription.url) else { return }
        let request = subscriptionRequest(url: url)
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            let text = String(data: data, encoding: .utf8) ?? ""
            let result = await parseSubscription(text, subscriptionID: subscription.id)
            if result.isRejected {
                throw NSError(
                    domain: "materialTun.Subscription",
                    code: 403,
                    userInfo: [NSLocalizedDescriptionKey: loc("The provider rejected this VPN client")]
                )
            }
            let parsed = result.profiles
            guard !parsed.isEmpty else {
                throw NSError(
                    domain: "materialTun.Subscription",
                    code: 422,
                    userInfo: [NSLocalizedDescriptionKey: loc("The subscription contains no supported configurations")]
                )
            }
            replaceProfiles(parsed, for: subscription.id)
            let count = parsed.count
            if let index = subscriptions.firstIndex(where: { $0.id == subscription.id }) {
                subscriptions[index].lastUpdated = Date()
                if let http = response as? HTTPURLResponse,
                   let title = subscriptionTitle(response: http, fallbackURL: url) {
                    subscriptions[index].name = title
                }
            }
            if let http = response as? HTTPURLResponse,
               let info = http.value(forHTTPHeaderField: "Subscription-Userinfo") {
                var details = parseSubscriptionInfo(info)
                details.iconURL = await subscriptionIconURL(response: http, subscriptionURL: url)
                subscriptionDetails[subscription.id] = details
            } else if let http = response as? HTTPURLResponse {
                var details = subscriptionDetails[subscription.id] ?? SubscriptionDetails()
                details.iconURL = await subscriptionIconURL(response: http, subscriptionURL: url)
                subscriptionDetails[subscription.id] = details
            }
            save()
            showToast(locf("Updated %d configurations", count))
        } catch {
            var details = subscriptionDetails[subscription.id] ?? SubscriptionDetails()
            details.lastError = error.localizedDescription
            subscriptionDetails[subscription.id] = details
            showToast(loc("Update failed"))
        }
    }

    func subscriptionRequest(url: URL) -> URLRequest {
        var request = URLRequest(url: url, timeoutInterval: 25)
        let custom = UserDefaults.standard.string(forKey: "SubscriptionUserAgent")?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let outdatedAgents = ["materialTun/1.0", "Happ/2.18.1/macOS"]
        let userAgent = custom.flatMap { !$0.isEmpty && !outdatedAgents.contains($0) ? $0 : nil }
            ?? "Happ/2.18.1/macOSarm64"
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("*/*", forHTTPHeaderField: "Accept")
        request.setValue("ru-RU,ru;q=0.9,en;q=0.7", forHTTPHeaderField: "Accept-Language")
        request.setValue("no-cache", forHTTPHeaderField: "Cache-Control")
        request.setValue(subscriptionHWID, forHTTPHeaderField: "X-HWID")
        request.setValue("macOS \(ProcessInfo.processInfo.operatingSystemVersionString)", forHTTPHeaderField: "X-Device-OS")
        request.setValue(deviceModel, forHTTPHeaderField: "X-Device-model")
        request.setValue(Locale.current.identifier, forHTTPHeaderField: "X-Device-Locale")
        return request
    }

    private var subscriptionHWID: String {
        if let saved = UserDefaults.standard.string(forKey: "materialTunSubscriptionHWID"), !saved.isEmpty { return saved }
        let value = UUID().uuidString.lowercased()
        UserDefaults.standard.set(value, forKey: "materialTunSubscriptionHWID")
        return value
    }

    private var deviceModel: String {
        var size = 0
        sysctlbyname("hw.model", nil, &size, nil, 0)
        var buffer = [CChar](repeating: 0, count: max(size, 1))
        sysctlbyname("hw.model", &buffer, &size, nil, 0)
        let bytes = buffer.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }
        return String(decoding: bytes, as: UTF8.self)
    }

    func subscriptionTitle(response: HTTPURLResponse, fallbackURL: URL) -> String? {
        let candidates = [
            response.value(forHTTPHeaderField: "profile-title"),
            response.value(forHTTPHeaderField: "Profile-Title"),
            response.value(forHTTPHeaderField: "content-disposition")
        ].compactMap { $0 }

        for raw in candidates {
            var value = raw
            if let filenameRange = value.range(of: #"filename\*?=(?:UTF-8'')?\"?([^\";]+)"#, options: .regularExpression) {
                value = String(value[filenameRange])
                    .replacingOccurrences(of: #"^filename\*?=(?:UTF-8'')?\"?"#, with: "", options: .regularExpression)
            }
            value = value.trimmingCharacters(in: CharacterSet(charactersIn: "\"' "))
            if let decoded = value.removingPercentEncoding { value = decoded }
            let encodedValue: String
            if value.lowercased().hasPrefix("base64:") {
                encodedValue = String(value.dropFirst("base64:".count))
            } else {
                encodedValue = value
            }
            if let data = ConfigParser.decodeBase64(encodedValue),
               let decoded = String(data: data, encoding: .utf8),
               !decoded.isEmpty {
                value = decoded
            }
            value = value.replacingOccurrences(of: ".txt", with: "")
                .replacingOccurrences(of: ".json", with: "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if !value.isEmpty, value.count < 100 { return value }
        }
        return fallbackURL.host?.replacingOccurrences(of: "www.", with: "")
    }

    func updateAllSubscriptions() async {
        let enabledSubscriptions = subscriptions.filter(\.autoUpdate)
        for subscription in enabledSubscriptions { await refreshSubscriptionEnhanced(subscription) }
    }

    private func parseSubscriptionInfo(_ value: String) -> SubscriptionDetails {
        let pairs = Dictionary(uniqueKeysWithValues: value.split(separator: ";").compactMap { item -> (String, String)? in
            let parts = item.split(separator: "=", maxSplits: 1).map { $0.trimmingCharacters(in: .whitespaces) }
            return parts.count == 2 ? (parts[0].lowercased(), parts[1]) : nil
        })
        return SubscriptionDetails(
            upload: pairs["upload"].flatMap(Int64.init),
            download: pairs["download"].flatMap(Int64.init),
            total: pairs["total"].flatMap(Int64.init),
            expire: pairs["expire"].flatMap(TimeInterval.init).map(Date.init(timeIntervalSince1970:)),
            lastError: nil,
            iconURL: nil
        )
    }

    private func subscriptionIconURL(response: HTTPURLResponse, subscriptionURL: URL) async -> String? {
        let directHeaders = ["profile-icon", "profile-logo", "profile-image"]
        for header in directHeaders {
            if let value = response.value(forHTTPHeaderField: header),
               let url = URL(string: value, relativeTo: subscriptionURL)?.absoluteURL {
                return url.absoluteString
            }
        }

        let page = response.value(forHTTPHeaderField: "profile-web-page-url")
            .flatMap(URL.init(string:))
            ?? subscriptionURL
        do {
            let (data, _) = try await URLSession.shared.data(for: subscriptionRequest(url: page))
            if let html = String(data: data, encoding: .utf8),
               let range = html.range(
                    of: #"<link[^>]+rel=[\"'][^\"']*(?:icon|shortcut icon)[^\"']*[\"'][^>]+href=[\"']([^\"']+)"#,
                    options: [.regularExpression, .caseInsensitive]
               ) {
                let tag = String(html[range])
                if let hrefRange = tag.range(of: #"href=[\"']([^\"']+)"#, options: [.regularExpression, .caseInsensitive]) {
                    let value = String(tag[hrefRange])
                        .replacingOccurrences(of: #"^href=[\"']"#, with: "", options: .regularExpression)
                        .replacingOccurrences(of: #"[\"']$"#, with: "", options: .regularExpression)
                    if let icon = URL(string: value, relativeTo: page)?.absoluteURL {
                        return icon.absoluteString
                    }
                }
            }
        } catch {}

        guard var components = URLComponents(url: page, resolvingAgainstBaseURL: false) else { return nil }
        components.path = "/favicon.ico"
        components.query = nil
        components.fragment = nil
        return components.url?.absoluteString
    }

    func importQRImage() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image]
        guard panel.runModal() == .OK, let url = panel.url,
              let image = CIImage(contentsOf: url),
              let detector = CIDetector(ofType: CIDetectorTypeQRCode, context: nil),
              let message = detector.features(in: image).compactMap({ ($0 as? CIQRCodeFeature)?.messageString }).first else {
            showToast(loc("QR code not found"))
            return
        }
        let count = addProfiles(from: message)
        showToast(count > 0 ? loc("QR code imported") : loc("QR code contains no configuration"))
    }

    func backup(to url: URL) throws {
        persistActiveWorkspace()
        let backup = materialTunBackup(
            workspaces: workspaces, activeWorkspaceID: activeWorkspaceID,
            settings: settings, profileOptions: profileOptions,
            subscriptionDetails: subscriptionDetails
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(backup).write(to: url, options: .atomic)
    }

    func restoreBackup(from url: URL) throws {
        let data = try Data(contentsOf: url)
        let backup = try JSONDecoder().decode(materialTunBackup.self, from: data)
        guard !backup.workspaces.isEmpty else { throw CocoaError(.fileReadCorruptFile) }
        workspaces = backup.workspaces
        activeWorkspaceID = backup.activeWorkspaceID ?? backup.workspaces[0].id
        settings = backup.settings
        profileOptions = backup.profileOptions
        subscriptionDetails = backup.subscriptionDetails
        loadWorkspace(activeWorkspaceID!)
        save()
    }

    func setLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled { try SMAppService.mainApp.register() }
            else { try SMAppService.mainApp.unregister() }
            settings.launchAtLogin = enabled
            save()
        } catch {
            showToast(locf("macOS: %@", error.localizedDescription))
        }
    }

    func checkForUpdates() async {
        updateStatus = loc("Checking…")
        guard let url = URL(string: "https://api.github.com/repos/palazik/palazikVPN/releases/latest") else { return }
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
            updateStatus = (json?["tag_name"] as? String).map { locf("Latest version: %@", $0) } ?? loc("No releases yet")
        } catch {
            updateStatus = loc("Could not check for updates")
        }
    }

    func updateGeoFiles(geoIPURL: String, geoSiteURL: String) async {
        let targets = [
            (geoIPURL, "geoip.dat"),
            (geoSiteURL, "geosite.dat")
        ].filter { !$0.0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        guard !targets.isEmpty else {
            showToast(loc("Enter the Geo file URLs"))
            return
        }
        let folder = supportURL.appendingPathComponent("geo", isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            for (source, name) in targets {
                guard let url = URL(string: source) else { throw URLError(.badURL) }
                let (data, response) = try await URLSession.shared.data(from: url)
                guard data.count > 1024, (response as? HTTPURLResponse)?.statusCode ?? 200 < 300 else {
                    throw URLError(.badServerResponse)
                }
                try data.write(to: folder.appendingPathComponent(name), options: .atomic)
            }
            showToast(loc("Geo files updated"))
        } catch {
            showToast(locf("Geo: %@", error.localizedDescription))
        }
    }

    func completeOnboarding() {
        onboardingComplete = true
        UserDefaults.standard.set(true, forKey: "materialTunOnboardingComplete")
    }

    func connectWithSingBox(_ server: ServerProfile) {
        guard settings.mode == .systemProxy else {
            state = .failed(loc("Select System Proxy for this protocol"))
            return
        }
        guard let binary = Bundle.main.url(forResource: "sing-box", withExtension: nil) else {
            state = .failed(loc("sing-box not found"))
            return
        }
        disconnect(silent: true)
        state = .connecting
        do {
            let data = try SingBoxConfigBuilder.make(server: server, settings: settings, options: profileOptions[server.id] ?? .init())
            let configURL = supportURL.appendingPathComponent("runtime-singbox.json")
            try data.write(to: configURL, options: .atomic)
            let process = Process()
            let output = Pipe()
            process.executableURL = binary
            process.arguments = ["run", "-c", configURL.path]
            process.standardOutput = output
            process.standardError = output
            output.fileHandleForReading.readabilityHandler = { [weak self] handle in
                let text = String(data: handle.availableData, encoding: .utf8) ?? ""
                Task { @MainActor in self?.log(text.trimmingCharacters(in: .whitespacesAndNewlines)) }
            }
            try process.run()
            xrayProcess = process
            Task {
                try? await Task.sleep(for: .milliseconds(700))
                guard process.isRunning else {
                    state = .failed(loc("sing-box failed to start"))
                    return
                }
                applySystemProxy()
                state = .connected(Date())
                startStats()
                log(loc("Connected through sing-box"))
            }
        } catch {
            state = .failed(error.localizedDescription)
        }
    }
}

enum LatencyTester {
    static func measure(server: ServerProfile, method: LatencyMethod, testURL: String) async -> Int? {
        let start = Date()
        switch method {
        case .tcp:
            let connection = NWConnection(host: NWEndpoint.Host(server.host), port: NWEndpoint.Port(rawValue: UInt16(clamping: server.port))!, using: .tcp)
            return await withTaskGroup(of: Int?.self) { group in
                group.addTask {
                    await withCheckedContinuation { continuation in
                        connection.stateUpdateHandler = { state in
                            switch state {
                            case .ready:
                                connection.cancel()
                                continuation.resume(returning: Int(Date().timeIntervalSince(start) * 1000))
                            case .failed:
                                connection.cancel()
                                continuation.resume(returning: nil)
                            default: break
                            }
                        }
                        connection.start(queue: .global(qos: .utility))
                    }
                }
                group.addTask {
                    try? await Task.sleep(for: .seconds(3))
                    connection.cancel()
                    return nil
                }
                let result = await group.next() ?? nil
                group.cancelAll()
                return result
            }
        case .httpHead, .httpGet:
            let scheme = server.port == 443 ? "https" : "http"
            guard let url = URL(string: "\(scheme)://\(server.host):\(server.port)/") ?? URL(string: testURL) else { return nil }
            var request = URLRequest(url: url, timeoutInterval: 4)
            request.httpMethod = method == .httpHead ? "HEAD" : "GET"
            do {
                _ = try await URLSession.shared.data(for: request)
                return Int(Date().timeIntervalSince(start) * 1000)
            } catch { return nil }
        }
    }
}

enum SingBoxConfigBuilder {
    static func make(server: ServerProfile, settings: AppSettings, options: ProfileOptions) throws -> Data {
        guard let url = URLComponents(string: server.rawURI) else { throw URLError(.badURL) }
        let query = Dictionary(uniqueKeysWithValues: (url.queryItems ?? []).map { ($0.name, $0.value ?? "") })
        var outbound: [String: Any] = [
            "type": server.type.rawValue.lowercased(),
            "tag": "proxy",
            "server": server.host,
            "server_port": server.port
        ]
        switch server.type {
        case .hysteria2:
            outbound["type"] = "hysteria2"
            outbound["password"] = url.user ?? ""
            outbound["tls"] = tls(server: server, query: query, insecure: options.allowInsecure)
        case .tuic:
            outbound["type"] = "tuic"
            outbound["uuid"] = url.user ?? ""
            outbound["password"] = url.password ?? query["password"] ?? ""
            outbound["congestion_control"] = query["congestion_control"] ?? "bbr"
            outbound["tls"] = tls(server: server, query: query, insecure: options.allowInsecure)
        case .anytls:
            outbound["type"] = "anytls"
            outbound["password"] = url.user ?? ""
            outbound["tls"] = tls(server: server, query: query, insecure: options.allowInsecure)
        case .wireguard:
            outbound["type"] = "wireguard"
            outbound["private_key"] = url.user ?? query["private_key"] ?? ""
            outbound["peer_public_key"] = query["public_key"] ?? query["peer_public_key"] ?? ""
            outbound["local_address"] = (query["address"] ?? "172.16.0.2/32").split(separator: ",").map(String.init)
        default:
            throw NSError(domain: "materialTun", code: 40, userInfo: [NSLocalizedDescriptionKey: loc("Unsupported sing-box profile")])
        }
        let config: [String: Any] = [
            "log": ["level": settings.logLevel],
            "inbounds": [[
                "type": "mixed", "tag": "mixed-in",
                "listen": "127.0.0.1", "listen_port": settings.localSocksPort
            ], [
                "type": "http", "tag": "http-in",
                "listen": "127.0.0.1", "listen_port": settings.localHTTPPort
            ]],
            "outbounds": [outbound, ["type": "direct", "tag": "direct"], ["type": "block", "tag": "block"]],
            "route": ["final": "proxy", "auto_detect_interface": true]
        ]
        return try JSONSerialization.data(withJSONObject: config, options: [.prettyPrinted, .sortedKeys])
    }

    private static func tls(server: ServerProfile, query: [String: String], insecure: Bool) -> [String: Any] {
        [
            "enabled": true,
            "server_name": query["sni"] ?? server.host,
            "insecure": insecure,
            "alpn": query["alpn"].map { $0.split(separator: ",").map(String.init) } ?? ["h3"]
        ]
    }
}

extension Color {
    init(hex: String) {
        let value = UInt64(hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted), radix: 16) ?? 0x6750A4
        self.init(
            red: Double((value >> 16) & 0xFF) / 255,
            green: Double((value >> 8) & 0xFF) / 255,
            blue: Double(value & 0xFF) / 255
        )
    }
}
