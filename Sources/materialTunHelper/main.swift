import Foundation
import Darwin

struct HelperCommand: Codable {
    let id: UUID
    let action: String
}

struct HelperStatus: Codable {
    let commandID: UUID?
    let state: String
    let message: String?
    let pid: Int32?
}

final class TunnelHelper: @unchecked Sendable {
    private let supportURL: URL
    private let commandURL: URL
    private let statusURL: URL
    private let pidURL: URL
    private let configURL: URL
    private let logURL: URL
    private let singBoxURL = URL(fileURLWithPath: "/Library/PrivilegedHelperTools/local.materialtun.sing-box")
    private var process: Process?
    private var lastCommandID: UUID?

    init(supportPath: String) {
        supportURL = URL(fileURLWithPath: supportPath, isDirectory: true)
        commandURL = supportURL.appendingPathComponent("helper-command.json")
        statusURL = supportURL.appendingPathComponent("helper-status.json")
        pidURL = supportURL.appendingPathComponent("tun.pid")
        configURL = supportURL.appendingPathComponent("runtime-tun.json")
        logURL = supportURL.appendingPathComponent("tun.log")
    }

    func run() {
        signal(SIGTERM, SIG_IGN)
        writeStatus(.init(commandID: nil, state: "ready", message: nil, pid: currentPID()))
        while true {
            autoreleasepool {
                processCommandIfNeeded()
                reconcileProcess()
            }
            Thread.sleep(forTimeInterval: 0.18)
        }
    }

    private func processCommandIfNeeded() {
        guard let data = try? Data(contentsOf: commandURL),
              let command = try? JSONDecoder().decode(HelperCommand.self, from: data),
              command.id != lastCommandID else { return }
        lastCommandID = command.id
        switch command.action {
        case "start": start(commandID: command.id)
        case "stop": stop(commandID: command.id)
        default:
            writeStatus(.init(commandID: command.id, state: "failed", message: "Unknown command", pid: currentPID()))
        }
    }

    private func start(commandID: UUID) {
        stopRunningTunnel()
        guard FileManager.default.isExecutableFile(atPath: singBoxURL.path),
              FileManager.default.isReadableFile(atPath: configURL.path) else {
            writeStatus(.init(commandID: commandID, state: "failed", message: "Missing sing-box or configuration", pid: nil))
            return
        }

        FileManager.default.createFile(atPath: logURL.path, contents: nil)
        guard let log = try? FileHandle(forWritingTo: logURL) else {
            writeStatus(.init(commandID: commandID, state: "failed", message: "Cannot open tunnel log", pid: nil))
            return
        }
        try? log.truncate(atOffset: 0)

        let task = Process()
        task.executableURL = singBoxURL
        task.arguments = ["run", "-c", configURL.path]
        task.standardInput = FileHandle.nullDevice
        task.standardOutput = log
        task.standardError = log
        task.terminationHandler = { [weak self] process in
            try? log.close()
            self?.writeStatus(.init(
                commandID: commandID,
                state: "failed",
                message: "sing-box exited with code \(process.terminationStatus)",
                pid: nil
            ))
        }
        do {
            try task.run()
            process = task
            try? "\(task.processIdentifier)".write(to: pidURL, atomically: true, encoding: .utf8)
            writeStatus(.init(commandID: commandID, state: "running", message: nil, pid: task.processIdentifier))
        } catch {
            try? log.close()
            writeStatus(.init(commandID: commandID, state: "failed", message: error.localizedDescription, pid: nil))
        }
    }

    private func stop(commandID: UUID) {
        stopRunningTunnel()
        writeStatus(.init(commandID: commandID, state: "stopped", message: nil, pid: nil))
    }

    private func stopRunningTunnel() {
        if let process, process.isRunning {
            process.terminate()
            process.waitUntilExit()
        } else if let pid = currentPID(), pid > 1 {
            kill(pid, SIGTERM)
            usleep(150_000)
            if kill(pid, 0) == 0 { kill(pid, SIGKILL) }
        }
        process = nil
        try? FileManager.default.removeItem(at: pidURL)
    }

    private func reconcileProcess() {
        if let process, !process.isRunning { self.process = nil }
    }

    private func currentPID() -> Int32? {
        guard let text = try? String(contentsOf: pidURL, encoding: .utf8),
              let pid = Int32(text.trimmingCharacters(in: .whitespacesAndNewlines)),
              kill(pid, 0) == 0 else { return nil }
        return pid
    }

    private func writeStatus(_ status: HelperStatus) {
        guard let data = try? JSONEncoder().encode(status) else { return }
        try? data.write(to: statusURL, options: .atomic)
        let (uid, gid) = ownerIdentity()
        if uid != 0 {
            chown(statusURL.path, uid, gid)
            chmod(statusURL.path, 0o600)
        }
    }

    private func ownerIdentity() -> (uid_t, gid_t) {
        var statInfo = stat()
        guard stat(supportURL.path, &statInfo) == 0 else { return (0, 0) }
        return (statInfo.st_uid, statInfo.st_gid)
    }
}

guard CommandLine.arguments.count == 3, CommandLine.arguments[1] == "--watch" else {
    fputs("Usage: materialTunHelper --watch <support-directory>\n", stderr)
    exit(64)
}

TunnelHelper(supportPath: CommandLine.arguments[2]).run()
