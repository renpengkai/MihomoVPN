//
// ClashParser.swift
// MihomoVPN
// Clash / Clash.Meta 配置中的 proxies 原样导入 (内核本身就是 Mihomo)。
//

import Foundation

enum ClashParser {

    /// Mihomo 原生支持的常见代理类型; 未知类型跳过以免配置校验失败
    static let supported: Set<String> = [
        "ss", "ssr", "vmess", "vless", "trojan", "hysteria", "hysteria2", "hy2",
        "tuic", "socks5", "http", "snell", "wireguard", "anytls", "mieru", "shadowtls",
    ]

    static func looksLike(_ text: String) -> Bool {
        text.range(of: #"(?m)^proxies\s*:"#, options: .regularExpression) != nil
    }

    static func parse(_ text: String) -> ParseResult {
        var result = ParseResult()
        guard let list = MiniYAML.topLevel("proxies", in: text) as? [Any] else { return result }
        for item in list {
            result.add(node(item))
        }
        return result
    }

    static func node(_ any: Any) -> ProxyNode? {
        guard let map = any as? [String: Any], let type = (map["type"] as? String)?.lowercased() else {
            return nil
        }
        guard supported.contains(type) else { return nil }
        guard let name = map["name"] as? String, !name.isEmpty else { return nil }
        guard map["server"] != nil || type == "wireguard" else { return nil }
        var dict = map
        dict.removeValue(forKey: "name")
        dict["type"] = type
        return ProxyNode(tag: name, proxy: JSON(any: dict))
    }
}
