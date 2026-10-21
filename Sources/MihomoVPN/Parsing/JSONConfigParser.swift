//
// JSONConfigParser.swift
// MihomoVPN
// JSON 配置: Clash Meta proxies 列表、Shadowsocks SIP008、常见 V2ray outbound。
//

import Foundation

enum JSONConfigParser {

    static func parse(_ obj: Any) -> ParseResult? {
        if let d = obj as? [String: Any] {
            let m = YMap(d)
            if let proxies = d["proxies"] as? [Any] {
                var r = ParseResult()
                for item in proxies { r.add(ClashParser.node(item)) }
                return r
            }
            let servers = m.maps("servers")
            if !servers.isEmpty { return sip008(servers) }
            if m.str("server") != nil, m.str("method") != nil || m.str("cipher") != nil {
                return sip008([m])
            }
            let outbounds = m.maps("outbounds")
            if !outbounds.isEmpty {
                if outbounds.contains(where: { $0.raw["protocol"] != nil }) {
                    return v2ray(outbounds, remarks: m.str("remarks"))
                }
                return singBox(outbounds)
            }
            return nil
        }
        if let a = obj as? [Any] {
            var r = ParseResult()
            for item in a {
                if let sub = parse(item) { r.merge(sub) } else { r.skipped += 1 }
            }
            return r
        }
        return nil
    }

    static func sip008(_ servers: [YMap]) -> ParseResult {
        var r = ParseResult()
        for s in servers {
            guard let server = s.str("server"), let method = s.first("method", "cipher"),
                  let password = s.str("password") else {
                r.skipped += 1
                continue
            }
            var f: [String: JSON] = [
                "cipher": .string(method),
                "password": .string(password),
                "udp": true,
            ]
            if let plugin = s.str("plugin") {
                LinkParser.applyPlugin(plugin + (s.str("plugin_opts").map { ";\($0)" } ?? ""), to: &f)
            }
            r.add(NodeBuilder.make("ss", name: s.str("remarks") ?? s.str("name"),
                                   server: server, port: s.int("server_port") ?? s.int("port"), fields: f))
        }
        return r
    }

    static func singBox(_ outbounds: [YMap]) -> ParseResult {
        var r = ParseResult()
        for o in outbounds {
            guard let type = o.str("type") else { continue }
            let mapped: String?
            switch type {
            case "shadowsocks": mapped = "ss"
            case "socks": mapped = "socks5"
            case "vmess", "vless", "trojan", "hysteria", "hysteria2", "tuic", "http", "anytls": mapped = type
            default: mapped = nil
            }
            guard let clashType = mapped, let server = o.str("server") else { continue }
            var f: [String: JSON] = ["udp": true]
            switch clashType {
            case "ss":
                guard let method = o.str("method"), let password = o.str("password") else { r.skipped += 1; continue }
                f["cipher"] = .string(method)
                f["password"] = .string(password)
            case "vmess", "vless":
                guard let uuid = o.str("uuid") else { r.skipped += 1; continue }
                f["uuid"] = .string(uuid)
                if let alter = o.int("alter_id") { f["alterId"] = .int(alter) }
                if let sec = o.str("security") { f["cipher"] = .string(sec) }
                if let flow = o.str("flow") { f["flow"] = .string(flow) }
                if o.map("tls")?.bool("enabled") == true {
                    f["tls"] = true
                    if let sni = o.map("tls")?.str("server_name") { f["servername"] = .string(sni) }
                    if o.map("tls")?.bool("insecure") == true { f["skip-cert-verify"] = true }
                }
            case "trojan", "anytls":
                guard let password = o.str("password") else { r.skipped += 1; continue }
                f["password"] = .string(password)
                f["tls"] = true
                if let sni = o.map("tls")?.str("server_name") { f["sni"] = .string(sni) }
            case "hysteria2":
                f["password"] = .string(o.str("password") ?? "")
                if let sni = o.map("tls")?.str("server_name") { f["sni"] = .string(sni) }
            case "tuic":
                guard let uuid = o.str("uuid") else { r.skipped += 1; continue }
                f["uuid"] = .string(uuid)
                f["password"] = .string(o.str("password") ?? "")
            case "socks5", "http":
                if let u = o.str("username") { f["username"] = .string(u) }
                if let p = o.str("password") { f["password"] = .string(p) }
            default:
                break
            }
            r.add(NodeBuilder.make(clashType, name: o.str("tag"), server: server,
                                   port: o.int("server_port") ?? o.int("port"), fields: f))
        }
        return r
    }

    static func v2ray(_ outbounds: [YMap], remarks: String?) -> ParseResult {
        var r = ParseResult()
        for o in outbounds {
            guard let proto = o.str("protocol")?.lowercased(),
                  let settings = o.map("settings") else { continue }
            let name = o.str("tag") ?? remarks
            switch proto {
            case "shadowsocks":
                guard let server = settings.maps("servers").first else { r.skipped += 1; continue }
                r.add(NodeBuilder.make("ss", name: name, server: server.str("address"), port: server.int("port"), fields: [
                    "cipher": .string(server.str("method") ?? "aes-256-gcm"),
                    "password": .string(server.str("password") ?? ""),
                    "udp": true,
                ]))
            case "vmess", "vless":
                guard let vnext = settings.maps("vnext").first,
                      let user = vnext.maps("users").first else { r.skipped += 1; continue }
                var f: [String: JSON] = [
                    "uuid": .string(user.str("id") ?? ""),
                    "udp": true,
                ]
                if proto == "vmess" {
                    f["alterId"] = .int(user.int("alterId") ?? 0)
                    f["cipher"] = .string(user.str("security") ?? "auto")
                }
                r.add(NodeBuilder.make(proto, name: name, server: vnext.str("address"),
                                       port: vnext.int("port"), fields: f))
            case "trojan":
                guard let server = settings.maps("servers").first else { r.skipped += 1; continue }
                r.add(NodeBuilder.make("trojan", name: name, server: server.str("address"),
                                       port: server.int("port"), fields: [
                    "password": .string(server.str("password") ?? ""),
                    "udp": true,
                ]))
            default:
                r.skipped += 1
            }
        }
        return r
    }
}
