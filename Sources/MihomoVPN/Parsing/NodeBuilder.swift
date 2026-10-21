//
// NodeBuilder.swift
// MihomoVPN
// 构造 Clash Meta 格式的 proxy 对象。
//

import Foundation

enum NodeBuilder {

    static func make(_ type: String, name: String?, server: String?, port: Int?, fields: [String: JSON]) -> ProxyNode? {
        guard let server = server?.trimmingCharacters(in: .whitespaces), !server.isEmpty else { return nil }
        let port = port ?? 0
        // Hysteria2 端口跳跃可以只给 ports 范围
        guard (1...65535).contains(port) || fields["ports"] != nil else { return nil }
        var o = fields
        o["type"] = .string(type)
        o["server"] = .string(server)
        if port > 0 { o["port"] = .int(port) }
        let trimmed = name?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let tag = trimmed.isEmpty ? "\(server):\(port)" : trimmed
        return ProxyNode(tag: tag, proxy: .object(o))
    }
}

struct ParseResult {
    var nodes: [ProxyNode] = []
    var skipped = 0

    mutating func add(_ node: ProxyNode?) {
        if let node { nodes.append(node) } else { skipped += 1 }
    }

    mutating func merge(_ other: ParseResult) {
        nodes += other.nodes
        skipped += other.skipped
    }

    /// Mihomo 要求 proxy name 唯一, 且不能与分组名重名
    func uniqued() -> ParseResult {
        var used: Set<String> = [ConfigBuilder.proxyGroup, ConfigBuilder.autoGroup, "DIRECT", "REJECT"]
        var out = self
        out.nodes = nodes.map { node in
            var n = node
            var tag = node.tag
            var k = 2
            while used.contains(tag) {
                tag = "\(node.tag) \(k)"
                k += 1
            }
            used.insert(tag)
            n.tag = tag
            return n
        }
        return out
    }
}
