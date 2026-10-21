//
// ClashParser.swift
// MihomoVPN
// Clash / Clash.Meta 配置中的 proxies 原样导入 (内核本身就是 Mihomo)。
// MiniYAML 标量全是 String, 写出前需把 bool/int 字段还原成正确类型。
//

import Foundation

enum ClashParser {

    /// Mihomo 原生支持的常见代理类型; 未知类型跳过以免配置校验失败
    static let supported: Set<String> = [
        "ss", "ssr", "vmess", "vless", "trojan", "hysteria", "hysteria2", "hy2",
        "tuic", "socks5", "http", "snell", "wireguard", "anytls", "mieru", "shadowtls",
    ]

    /// Clash Meta 中按 bool 解析的字段 (含子选项里同名键)
    static let boolKeys: Set<String> = [
        "skip-cert-verify", "tls", "udp", "tfo", "tcp-fast-open", "mptcp",
        "reduce-rtt", "disable-sni", "udp-over-tcp", "xudp", "smux",
        "v2ray-http-upgrade", "v2ray-http-upgrade-fast-open",
        "prefer-h3", "fast-open", "no-resolve", "force-cert-verify",
        "ipv6", "keepalive", "disable-udp", "allow-insecure",
    ]

    /// 必须是整数的字段; 不含 hysteria 的 up/down (可为 "100 Mbps" 字符串)
    static let intKeys: Set<String> = [
        "port", "alterId", "alter-id", "mtu", "hop-interval", "heartbeat-interval",
        "max-early-data", "idle-timeout", "keep-alive-interval", "cwnd",
        "initial-stream-receive-window", "max-stream-receive-window",
        "initial-connection-receive-window", "max-connection-receive-window",
        "recv-window-conn", "recv-window",
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
        return ProxyNode(tag: name, proxy: normalize(JSON(any: dict)))
    }

    /// 把 YAML 留下的 "true"/"443" 还原成 bool/int, 生成配置或重新导入时都可调用
    static func normalize(_ json: JSON) -> JSON {
        JSON(any: coerce(toAny(json)))
    }

    // MARK: - 类型纠正

    private static func coerce(_ value: Any, key: String? = nil) -> Any {
        if let dict = value as? [String: Any] {
            return Dictionary(uniqueKeysWithValues: dict.map { ($0.key, coerce($0.value, key: $0.key)) })
        }
        if let arr = value as? [Any] {
            return arr.map { coerce($0) }
        }
        guard let key, let s = value as? String else { return value }
        let trimmed = s.trimmingCharacters(in: .whitespacesAndNewlines)
        if boolKeys.contains(key) {
            return ["true", "1", "yes", "on"].contains(trimmed.lowercased())
        }
        if intKeys.contains(key), let i = Int(trimmed) {
            return i
        }
        return value
    }

    private static func toAny(_ json: JSON) -> Any {
        switch json {
        case .null: return NSNull()
        case .bool(let v): return v
        case .int(let v): return v
        case .double(let v): return v
        case .string(let v): return v
        case .array(let a): return a.map(toAny)
        case .object(let o): return o.mapValues(toAny)
        }
    }
}
