//
// System.swift
// MihomoVPN
// 路径常量、子进程执行、进程路径查询。
//

import Foundation

enum Paths {
    static let support: URL = {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let url = base.appendingPathComponent("MihomoVPN", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }()

    /// 用户态内核 (启动时从应用包内复制, 或在设置中下载)
    static var core: URL { support.appendingPathComponent("core/mihomo") }
    static var config: URL { support.appendingPathComponent("config.json") }
    static var state: URL { support.appendingPathComponent("profiles.json") }

    /// 以下与 mvpnhelper 内的常量保持一致
    static let helper = "/Library/PrivilegedHelperTools/io.github.renpengkai.mihomovpn.helper"
    static let rootCore = "/Library/PrivilegedHelperTools/io.github.renpengkai.mihomovpn.core"
}

enum Shell {
    /// 输出写临时文件而不是管道: 特权组件会拉起常驻的内核进程, 若内核继承了管道写端, 这里将永远读不到 EOF
    @discardableResult
    static func run(_ path: String, _ args: [String]) -> (status: Int32, output: String) {
        let fm = FileManager.default
        let out = fm.temporaryDirectory.appendingPathComponent("mihomovpn-\(UUID().uuidString).out")
        fm.createFile(atPath: out.path, contents: nil)
        defer { try? fm.removeItem(at: out) }
        guard let handle = try? FileHandle(forWritingTo: out) else { return (-1, "无法创建临时文件") }

        let p = Process()
        p.executableURL = URL(fileURLWithPath: path)
        p.arguments = args
        p.standardOutput = handle
        p.standardError = handle
        p.standardInput = FileHandle.nullDevice
        do {
            try p.run()
        } catch {
            try? handle.close()
            return (-1, error.localizedDescription)
        }
        p.waitUntilExit()
        try? handle.close()
        let text = (try? String(contentsOf: out, encoding: .utf8)) ?? ""
        return (p.terminationStatus, text.trimmingCharacters(in: .whitespacesAndNewlines))
    }
}

enum Proc {
    static func path(of pid: pid_t) -> String? {
        var buf = [CChar](repeating: 0, count: 4096)
        guard proc_pidpath(pid, &buf, UInt32(buf.count)) > 0 else { return nil }
        return String(cString: buf)
    }
}
