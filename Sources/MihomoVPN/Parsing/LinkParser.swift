//
// LinkParser.swift
// MihomoVPN
// 分享链接 → Clash Meta proxy。
//

import Foundation

struct LinkURL {
    var user = ""
    var host = ""
    var portText = ""
    var query: [String: String] = [:]
    var name = ""

    var port: Int? { Int(portText) }

    init?(_ link: String) {
        guard let r = link.range(of: "://") else { return nil }
        var rest = String(link[r.upperBound...])
        if let h = rest.firstIndex(of: "#") {
            name = LinkURL.decode(String(rest[rest.index(after: h)...]))
            rest = String(rest[..<h])
        }
        if let q = rest.firstIndex(of: "?") {
            query = LinkURL.parseQuery(String(rest[rest.index(after: q)...]))
            rest = String(rest[..<q])
        }
        if let at = rest.lastIndex(of: "@") {
            user = LinkURL.decode(String(rest[..<at]))
            rest = String(rest[rest.index(after: at)...])
        }
        if let slash = rest.firstIndex(of: "/") { rest = String(rest[..<slash]) }
        guard let hp = LinkURL.splitHost(rest) else { return nil }
        host = hp.host
        portText = hp.port
    }

    static func decode(_ s: String) -> String {
        (s.removingPercentEncoding ?? s).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func splitHost(_ s: String) -> (host: String, port: String)? {
        if s.hasPrefix("["), let close = s.firstIndex(of: "]") {
            let host = String(s[s.index(after: s.startIndex)..<close])
            let after = s[s.index(after: close)...]
            return (host, after.hasPrefix(":") ? String(after.dropFirst()) : "")
        }
        guard let c = s.firstIndex(of: ":") else { return s.isEmpty ? nil : (s, "") }
        return (String(s[..<c]), String(s[s.index(after: c)...]))
    }

    static func parseQuery(_ s: String) -> [String: String] {
        var result: [String: String] = [:]
        for pair in s.split(separator: "&") {
            let kv = pair.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
            guard let k = kv.first, !k.isEmpty else { continue }
            result[decode(String(k)).lowercased()] = kv.count > 1 ? decode(String(kv[1])) : ""
        }
        return result
    }
}

enum LinkParser {

    static func parse(_ line: String) -> ProxyNode? {
        let s = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let r = s.range(of: "://") else { return nil }
        switch s[..<r.lowerBound].lowercased() {
        case "ss": return shadowsocks(s)
        case "vmess": return vmess(s)
        case "vless": return standard(s, type: "vless")
        case "trojan": return standard(s, type: "trojan")
        case "hysteria2", "hy2": return hysteria2(s)
        case "hysteria": return hysteria(s)
        case "tuic": return tuic(s)
        case "socks", "socks5": return socks(s)
        case "anytls": return anytls(s)
        default: return nil
        }
    }

    static func shadowsocks(_ link: String) -> ProxyNode? {
        var body = String(link.dropFirst("ss://".count))
        var name = ""
        if let h = body.firstIndex(of: "#") {
            name = LinkURL.decode(String(body[body.index(after: h)...]))
            body = String(body[..<h])
        }
        var query: [String: String] = [:]
        if let q = body.firstIndex(of: "?") {
            query = LinkURL.parseQuery(String(body[body.index(after: q)...]))
            body = String(body[..<q])
        }
        while body.hasSuffix("/") { body.removeLast() }
        if !body.contains("@"), let decoded = Base64.decode(body) { body = decoded }
        guard let at = body.lastIndex(of: "@") else { return nil }
        var info = String(body[..<at])
        info = info.contains(":") ? LinkURL.decode(info) : (Base64.decode(info) ?? LinkURL.decode(info))
        guard let c = info.firstIndex(of: ":"),
              let hp = LinkURL.splitHost(String(body[body.index(after: at)...])) else { return nil }
        var fields: [String: JSON] = [
            "cipher": .string(String(info[..<c])),
            "password": .string(String(info[info.index(after: c)...])),
            "udp": true,
        ]
        if let plugin = nonEmpty(query["plugin"]) {
            applyPlugin(plugin, to: &fields)
        }
        return NodeBuilder.make("ss", name: name, server: hp.host, port: Int(hp.port), fields: fields)
    }

    static func applyPlugin(_ spec: String, to fields: inout [String: JSON]) {
        let parts = spec.split(separator: ";", maxSplits: 1).map(String.init)
        var name = parts.first ?? ""
        let options = parts.count > 1 ? parts[1] : ""
        if name == "simple-obfs" || name == "obfs" { name = "obfs" }
        fields["plugin"] = .string(name)
        if !options.isEmpty {
            var opts: [String: JSON] = [:]
            for part in options.split(separator: ";") {
                let kv = part.split(separator: "=", maxSplits: 1).map(String.init)
                if kv.count == 2 {
                    opts[kv[0]] = .string(kv[1])
                } else if kv.count == 1, !kv[0].isEmpty {
                    opts[kv[0]] = true
                }
            }
            if !opts.isEmpty { fields["plugin-opts"] = .object(opts) }
        }
    }

    static func vmess(_ link: String) -> ProxyNode? {
        let body = String(link.dropFirst("vmess://".count)).components(separatedBy: "#")[0]
        guard let text = Base64.decode(body), let data = text.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return standard(link, type: "vmess")
        }
        let j = YMap(obj)
        guard let uuid = j.str("id") else { return nil }
        var fields: [String: JSON] = [
            "uuid": .string(uuid),
            "alterId": .int(j.int("aid") ?? 0),
            "cipher": .string(j.str("scy") ?? "auto"),
            "udp": true,
        ]
        let net = (j.str("net") ?? "tcp").lowercased()
        fields["network"] = .string(net == "websocket" ? "ws" : net)
        let security = j.str("tls")?.lowercased() ?? ""
        if security == "tls" || security == "reality" {
            fields["tls"] = true
            if let sni = j.first("sni", "host") { fields["servername"] = .string(sni) }
            if j.bool("allowInsecure") || j.bool("skip-cert-verify") { fields["skip-cert-verify"] = true }
            if let fp = j.str("fp") { fields["client-fingerprint"] = .string(fp) }
            if let pbk = j.str("pbk") {
                var reality: [String: JSON] = ["public-key": .string(pbk)]
                if let sid = j.str("sid") { reality["short-id"] = .string(sid) }
                fields["reality-opts"] = .object(reality)
            }
        }
        applyTransport(&fields, network: net, path: j.str("path"), host: j.str("host"))
        return NodeBuilder.make("vmess", name: j.str("ps"), server: j.str("add"), port: j.int("port"), fields: fields)
    }

    static func standard(_ link: String, type: String) -> ProxyNode? {
        guard let u = LinkURL(link), !u.user.isEmpty else { return nil }
        let q = u.query
        var fields: [String: JSON] = ["udp": true]
        switch type {
        case "trojan":
            fields["password"] = .string(u.user)
        case "vless":
            fields["uuid"] = .string(u.user)
            if let flow = nonEmpty(q["flow"]) { fields["flow"] = .string(flow) }
        default:
            fields["uuid"] = .string(u.user)
            fields["cipher"] = .string(nonEmpty(q["encryption"]) ?? "auto")
            fields["alterId"] = 0
        }
        let network = (q["type"] ?? "tcp").lowercased()
        if network != "tcp" && network != "raw" {
            fields["network"] = .string(network == "websocket" ? "ws" : network)
        }
        let security = (q["security"] ?? (type == "trojan" ? "tls" : "")).lowercased()
        if ["tls", "reality", "xtls"].contains(security) || (type == "trojan" && security != "none") {
            fields["tls"] = true
            if let sni = nonEmpty(q["sni"]) ?? nonEmpty(q["peer"]) { fields["servername"] = .string(sni) }
            if flag(q["allowinsecure"]) || flag(q["insecure"]) { fields["skip-cert-verify"] = true }
            if let fp = nonEmpty(q["fp"]) { fields["client-fingerprint"] = .string(fp) }
            if let alpn = nonEmpty(q["alpn"]) {
                fields["alpn"] = .array(alpn.split(separator: ",").map { JSON.string($0.trimmingCharacters(in: .whitespaces)) })
            }
            if let pbk = nonEmpty(q["pbk"]) {
                var reality: [String: JSON] = ["public-key": .string(pbk)]
                if let sid = q["sid"] { reality["short-id"] = .string(sid) }
                fields["reality-opts"] = .object(reality)
            }
        }
        applyTransport(&fields, network: network, path: q["path"], host: q["host"], service: q["servicename"])
        return NodeBuilder.make(type, name: u.name, server: u.host, port: u.port, fields: fields)
    }

    static func hysteria2(_ link: String) -> ProxyNode? {
        guard let u = LinkURL(link) else { return nil }
        let q = u.query
        var fields: [String: JSON] = ["password": .string(u.user)]
        var port: Int?
        let spec = u.portText + (nonEmpty(q["mport"]).map { "," + $0 } ?? "")
        var ports: [String] = []
        for part in spec.split(separator: ",") {
            let p = String(part)
            if p.contains("-") {
                ports.append(p)
            } else if let n = Int(p) {
                if port == nil { port = n } else { ports.append("\(n)-\(n)") }
            }
        }
        if !ports.isEmpty { fields["ports"] = .string(ports.joined(separator: ",")) }
        if let obfs = nonEmpty(q["obfs"]), obfs != "none" {
            fields["obfs"] = .string(obfs)
            if let pw = q["obfs-password"] { fields["obfs-password"] = .string(pw) }
        }
        if let sni = nonEmpty(q["sni"]) { fields["sni"] = .string(sni) }
        if flag(q["insecure"]) { fields["skip-cert-verify"] = true }
        return NodeBuilder.make("hysteria2", name: u.name, server: u.host, port: port, fields: fields)
    }

    static func hysteria(_ link: String) -> ProxyNode? {
        guard let u = LinkURL(link) else { return nil }
        let q = u.query
        var fields: [String: JSON] = [
            "up": .string(q["upmbps"] ?? "10"),
            "down": .string(q["downmbps"] ?? "50"),
        ]
        if let auth = nonEmpty(q["auth"]) { fields["auth-str"] = .string(auth) }
        if let obfs = nonEmpty(q["obfsparam"]) { fields["obfs"] = .string(obfs) }
        if let sni = nonEmpty(q["peer"]) ?? nonEmpty(q["sni"]) { fields["sni"] = .string(sni) }
        if flag(q["insecure"]) { fields["skip-cert-verify"] = true }
        return NodeBuilder.make("hysteria", name: u.name, server: u.host, port: u.port, fields: fields)
    }

    static func tuic(_ link: String) -> ProxyNode? {
        guard let u = LinkURL(link), let c = u.user.firstIndex(of: ":") else { return nil }
        let q = u.query
        var fields: [String: JSON] = [
            "uuid": .string(String(u.user[..<c])),
            "password": .string(String(u.user[u.user.index(after: c)...])),
        ]
        if let cc = nonEmpty(q["congestion_control"]) { fields["congestion-controller"] = .string(cc) }
        if let mode = nonEmpty(q["udp_relay_mode"]) { fields["udp-relay-mode"] = .string(mode) }
        if let sni = nonEmpty(q["sni"]) { fields["sni"] = .string(sni) }
        if flag(q["allow_insecure"]) || flag(q["insecure"]) { fields["skip-cert-verify"] = true }
        return NodeBuilder.make("tuic", name: u.name, server: u.host, port: u.port, fields: fields)
    }

    static func socks(_ link: String) -> ProxyNode? {
        guard let u = LinkURL(link) else { return nil }
        var fields: [String: JSON] = ["udp": true]
        var info = u.user
        if !info.isEmpty, !info.contains(":"), let decoded = Base64.decode(info) { info = decoded }
        if let c = info.firstIndex(of: ":") {
            fields["username"] = .string(String(info[..<c]))
            fields["password"] = .string(String(info[info.index(after: c)...]))
        }
        return NodeBuilder.make("socks5", name: u.name, server: u.host, port: u.port, fields: fields)
    }

    static func anytls(_ link: String) -> ProxyNode? {
        guard let u = LinkURL(link), !u.user.isEmpty else { return nil }
        let q = u.query
        var fields: [String: JSON] = ["password": .string(u.user)]
        if let sni = nonEmpty(q["sni"]) { fields["sni"] = .string(sni) }
        if flag(q["insecure"]) || flag(q["allowinsecure"]) { fields["skip-cert-verify"] = true }
        if let fp = nonEmpty(q["fp"]) { fields["client-fingerprint"] = .string(fp) }
        return NodeBuilder.make("anytls", name: u.name, server: u.host, port: u.port, fields: fields)
    }

    private static func applyTransport(_ fields: inout [String: JSON], network: String,
                                       path: String?, host: String?, service: String? = nil) {
        switch network.lowercased() {
        case "ws", "websocket":
            var opts: [String: JSON] = [:]
            if let path { opts["path"] = .string(path) }
            if let host, !host.isEmpty { opts["headers"] = ["Host": .string(host)] }
            fields["ws-opts"] = .object(opts)
        case "grpc", "gun":
            fields["grpc-opts"] = ["grpc-service-name": .string(service ?? path ?? "")]
        case "h2", "http":
            var opts: [String: JSON] = [:]
            if let path { opts["path"] = .array([.string(path)]) }
            if let host, !host.isEmpty { opts["host"] = .array([.string(host)]) }
            fields[network == "h2" ? "h2-opts" : "http-opts"] = .object(opts)
        default:
            break
        }
    }

    private static func flag(_ v: String?) -> Bool {
        guard let v = v?.lowercased() else { return false }
        return v == "1" || v == "true" || v == "yes"
    }

    private static func nonEmpty(_ v: String?) -> String? {
        guard let v, !v.isEmpty else { return nil }
        return v
    }
}
