//
// Profile.swift
// MihomoVPN
// 节点、订阅配置与代理模式。
//

import Foundation

struct ProxyNode: Codable, Hashable, Identifiable {
    /// Clash proxy name, 同一配置内唯一
    var tag: String
    /// 不含 name 的 Clash Meta proxy 对象
    var proxy: JSON

    var id: String { tag }
    var type: String { proxy["type"]?.stringValue ?? "" }
    var server: String { proxy["server"]?.stringValue ?? "" }
    var port: Int { proxy["port"]?.intValue ?? 0 }

    /// 基于 UDP/QUIC 的协议, 未连接时无法用 TCP 握手测延迟
    var isUDP: Bool {
        ["hysteria", "hysteria2", "hy2", "tuic"].contains(type.lowercased())
    }

    var typeLabel: String {
        switch type.lowercased() {
        case "ss", "shadowsocks": return "SS"
        case "ssr": return "SSR"
        case "vmess": return "VMess"
        case "vless": return "VLESS"
        case "trojan": return "Trojan"
        case "hysteria": return "Hysteria"
        case "hysteria2", "hy2": return "Hy2"
        case "tuic": return "TUIC"
        case "socks5", "socks": return "SOCKS"
        case "http": return "HTTP"
        case "snell": return "Snell"
        case "wireguard": return "WG"
        case "anytls": return "AnyTLS"
        default: return type.uppercased()
        }
    }
}

struct Usage: Codable, Hashable {
    var upload: Int64
    var download: Int64
    var total: Int64
    var expire: Date?

    var used: Int64 { upload + download }
    var fraction: Double { total > 0 ? min(Double(used) / Double(total), 1) : 0 }
}

struct Profile: Codable, Hashable, Identifiable {
    enum Kind: String, Codable {
        case remote
        case local
    }

    var id = UUID()
    var name: String
    var kind: Kind
    var url = ""
    var userAgent = ""
    var githubToken = ""
    var nodes: [ProxyNode] = []
    var updatedAt: Date?
    var usage: Usage?
}

enum ProxyMode: String, CaseIterable, Identifiable {
    case rule
    case global
    case direct

    var id: Self { self }

    var title: String {
        switch self {
        case .rule: return "规则"
        case .global: return "全局"
        case .direct: return "直连"
        }
    }

    init(stored: String?) {
        self = ProxyMode(rawValue: stored ?? "") ?? .rule
    }
}

struct AppError: LocalizedError {
    let message: String
    init(_ message: String) { self.message = message }
    var errorDescription: String? { message }
}
