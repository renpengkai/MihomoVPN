//
// SubscriptionParser.swift
// MihomoVPN
// 自动识别: Clash YAML、JSON、分享链接列表、Base64。
//

import Foundation

enum SubscriptionParser {

    static func parse(_ text: String) -> ParseResult {
        parse(text, depth: 0).uniqued()
    }

    private static func parse(_ raw: String, depth: Int) -> ParseResult {
        var text = raw
        if text.hasPrefix("\u{FEFF}") { text.removeFirst() }
        text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return ParseResult() }

        if text.first == "{" || text.first == "[",
           let data = text.data(using: .utf8),
           let obj = try? JSONSerialization.jsonObject(with: data),
           let result = JSONConfigParser.parse(obj) {
            return result
        }
        if ClashParser.looksLike(text) {
            return ClashParser.parse(text)
        }
        if text.contains("://") {
            var result = ParseResult()
            text.enumerateLines { line, _ in
                let l = line.trimmingCharacters(in: .whitespaces)
                guard l.contains("://") else { return }
                result.add(LinkParser.parse(l))
            }
            return result
        }
        if depth < 2, let decoded = Base64.decode(text) {
            return parse(decoded, depth: depth + 1)
        }
        return ParseResult()
    }
}
