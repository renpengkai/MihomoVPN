//
// CoreManager.swift
// MihomoVPN
// Mihomo 内核管理: 应用包内自带一份 (Contents/MacOS/mihomo), 启动时安装到数据目录;
// 也可从 GitHub Releases 更新或导入本地文件。
//

import Foundation

@MainActor
final class CoreManager: ObservableObject {

    @Published private(set) var version: String?
    @Published private(set) var rootVersion: String?
    @Published private(set) var busy = false
    @Published var message: String?

    init() {
        Self.installBundledIfNeeded()
        refresh()
    }

    nonisolated static var bundledVersion: String? {
        guard let v = Bundle.main.object(forInfoDictionaryKey: "MVPNCoreVersion") as? String, !v.isEmpty else {
            return nil
        }
        return v
    }

    var isInstalled: Bool { FileManager.default.isExecutableFile(atPath: Paths.core.path) }

    func refresh() {
        Task {
            let result = await Task.detached {
                (CoreManager.readVersion(Paths.core.path), CoreManager.readVersion(Paths.rootCore))
            }.value
            version = result.0
            rootVersion = result.1
        }
    }

    func download(mirror: String) async {
        guard !busy else { return }
        busy = true
        defer { busy = false }
        do {
            message = "正在查询最新版本…"
            let asset = try await Self.latestAsset()
            message = "正在下载 Mihomo \(asset.tag)…"
            guard let url = URL(string: SubscriptionFetcher.withMirror(asset.url, mirror: mirror)) else {
                throw AppError("下载地址无效")
            }
            let (file, response) = try await URLSession.shared.download(from: url)
            defer { try? FileManager.default.removeItem(at: file) }
            let code = (response as? HTTPURLResponse)?.statusCode ?? 0
            guard code == 200 else { throw AppError("下载失败，HTTP \(code)") }
            try await Task.detached { try CoreManager.installArchive(file) }.value
            message = "已安装 Mihomo \(asset.tag)"
            refresh()
        } catch {
            message = "失败：\(error.localizedDescription)"
        }
    }

    /// 支持直接选择 mihomo 可执行文件或官方 .gz 包
    func importLocal(_ url: URL) async {
        busy = true
        defer { busy = false }
        do {
            try await Task.detached {
                let name = url.lastPathComponent.lowercased()
                if name.hasSuffix(".gz") {
                    try CoreManager.installArchive(url)
                } else {
                    try CoreManager.placeBinary(url)
                }
            }.value
            message = "已导入本地内核"
            refresh()
        } catch {
            message = "导入失败：\(error.localizedDescription)"
        }
    }

    // MARK: - 后台执行

    nonisolated static func readVersion(_ path: String) -> String? {
        guard FileManager.default.isExecutableFile(atPath: path) else { return nil }
        let r = Shell.run(path, ["-v"])
        guard r.status == 0 else { return nil }
        // 形如 "Mihomo Meta v1.19.32 darwin arm64 with go1.24.x ..."
        if let range = r.output.range(of: #"v?\d+\.\d+\.\d+"#, options: .regularExpression) {
            var v = String(r.output[range])
            if v.hasPrefix("v") { v.removeFirst() }
            return v
        }
        return nil
    }

    nonisolated static func installBundledIfNeeded() {
        guard let bundledVersion,
              let bundled = Bundle.main.executableURL?.deletingLastPathComponent().appendingPathComponent("mihomo"),
              FileManager.default.isExecutableFile(atPath: bundled.path) else { return }
        if let installed = readVersion(Paths.core.path),
           compare(installed, bundledVersion) != .orderedAscending { return }
        try? placeBinary(bundled)
    }

    nonisolated static func compare(_ a: String, _ b: String) -> ComparisonResult {
        let pa = a.split(separator: ".").compactMap { Int($0) }
        let pb = b.split(separator: ".").compactMap { Int($0) }
        for i in 0..<max(pa.count, pb.count) {
            let x = i < pa.count ? pa[i] : 0
            let y = i < pb.count ? pb[i] : 0
            if x != y { return x < y ? .orderedAscending : .orderedDescending }
        }
        return .orderedSame
    }

    nonisolated static func latestAsset() async throws -> (tag: String, url: String) {
        var req = URLRequest(url: URL(string: "https://api.github.com/repos/MetaCubeX/mihomo/releases/latest")!,
                             timeoutInterval: 20)
        req.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        let (data, _) = try await URLSession.shared.data(for: req)
        guard let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let tag = obj["tag_name"] as? String,
              let assets = obj["assets"] as? [[String: Any]] else {
            throw AppError("无法解析 GitHub 发布信息（可能触发了访问频率限制，可稍后重试或导入本地文件）")
        }
        let ver = tag.hasPrefix("v") ? String(tag.dropFirst()) : tag
        #if arch(arm64)
        let name = "mihomo-darwin-arm64-v\(ver).gz"
        #else
        let name = "mihomo-darwin-amd64-v\(ver).gz"
        #endif
        guard let asset = assets.first(where: { ($0["name"] as? String) == name }),
              let url = asset["browser_download_url"] as? String else {
            throw AppError("发布 \(tag) 中没有适用于本机的文件")
        }
        return (tag, url)
    }

    nonisolated static func installArchive(_ archive: URL) throws {
        let fm = FileManager.default
        let work = fm.temporaryDirectory.appendingPathComponent("mihomovpn-core-\(UUID().uuidString)")
        try fm.createDirectory(at: work, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: work) }
        let out = work.appendingPathComponent("mihomo")
        fm.createFile(atPath: out.path, contents: nil)
        guard let handle = try? FileHandle(forWritingTo: out) else { throw AppError("无法写入临时文件") }
        let pipe = Process()
        pipe.executableURL = URL(fileURLWithPath: "/usr/bin/gzip")
        pipe.arguments = ["-dc", archive.path]
        pipe.standardOutput = handle
        pipe.standardError = FileHandle.nullDevice
        try pipe.run()
        pipe.waitUntilExit()
        try? handle.close()
        guard pipe.terminationStatus == 0 else { throw AppError("解压失败") }
        try placeBinary(out)
    }

    nonisolated static func placeBinary(_ src: URL) throws {
        let fm = FileManager.default
        let dst = Paths.core
        try fm.createDirectory(at: dst.deletingLastPathComponent(), withIntermediateDirectories: true)
        let staging = dst.appendingPathExtension("new")
        try? fm.removeItem(at: staging)
        try fm.copyItem(at: src, to: staging)
        try fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: staging.path)
        Shell.run("/usr/bin/xattr", ["-c", staging.path])
        guard readVersion(staging.path) != nil else {
            try? fm.removeItem(at: staging)
            throw AppError("不是有效的 Mihomo 可执行文件（请确认架构匹配本机）")
        }
        if fm.fileExists(atPath: dst.path) { try fm.removeItem(at: dst) }
        try fm.moveItem(at: staging, to: dst)
    }
}
