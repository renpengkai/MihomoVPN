//
// ConfigBuilder.swift
// MihomoVPN
// 由节点列表生成 Mihomo (Clash Meta) JSON 配置。
//

import Foundation

enum ConfigBuilder {

    static let defaultTestURL = "https://www.gstatic.com/generate_204"
    static let proxyGroup = "PROXY"
    static let autoGroup = "AUTO"

    struct Options {
        var mode: ProxyMode
        var tun: Bool
        var mixedPort: Int
        var apiPort: Int
        var secret: String
        var allowLAN: Bool
        var testURL: String
    }

    static func build(nodes: [ProxyNode], selected: String?, options o: Options) throws -> Data {
        guard !nodes.isEmpty else { throw AppError("没有可用节点") }
        let names = nodes.map(\.tag)

        let proxies: [JSON] = nodes.map { node in
            // 纠正订阅里 YAML 残留的字符串 bool/int (如 skip-cert-verify: "true")
            var p = ClashParser.normalize(node.proxy)
            p["name"] = .string(node.tag)
            return p
        }

        let initial = selected.flatMap { names.contains($0) ? $0 : nil } ?? autoGroup
        let auto: JSON = [
            "name": .string(autoGroup),
            "type": "url-test",
            "proxies": .array(names.map(JSON.string)),
            "url": .string(o.testURL),
            "interval": 300,
            "tolerance": 50,
        ]
        let selector: JSON = [
            "name": .string(proxyGroup),
            "type": "select",
            "proxies": .array([JSON.string(autoGroup)] + names.map(JSON.string)),
        ]

        var config: [String: JSON] = [
            "mixed-port": .int(o.mixedPort),
            "allow-lan": .bool(o.allowLAN),
            "bind-address": .string(o.allowLAN ? "*" : "127.0.0.1"),
            "mode": .string(o.mode.rawValue),
            "log-level": "silent",
            "ipv6": true,
            "unified-delay": true,
            "tcp-concurrent": true,
            "find-process-mode": "off",
            "external-controller": .string("127.0.0.1:\(o.apiPort)"),
            "secret": .string(o.secret),
            "dns": [
                "enable": true,
                "listen": "0.0.0.0:1053",
                "enhanced-mode": "fake-ip",
                "fake-ip-range": "198.18.0.1/16",
                "nameserver": ["223.5.5.5", "119.29.29.29"],
                "fallback": ["1.1.1.1", "8.8.8.8"],
                "fallback-filter": ["geoip": true, "geoip-code": "CN", "ipcidr": ["240.0.0.0/4"]],
            ],
            "proxies": .array(proxies),
            "proxy-groups": .array([selector, auto]),
            "rules": .array([
                "GEOIP,LAN,DIRECT",
                "GEOIP,CN,DIRECT",
                "MATCH,\(proxyGroup)",
            ].map(JSON.string)),
        ]

        if o.tun {
            config["tun"] = [
                "enable": true,
                "stack": "mixed",
                "auto-route": true,
                "auto-detect-interface": true,
                "dns-hijack": ["any:53"],
            ]
        }

        // initial 由连接后 Clash API 覆盖; 生成阶段仅保证 AUTO 在列表首位
        _ = initial

        let root: JSON = .object(config)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(root)
    }
}
