import SwiftUI
import UIKit

struct DTextView: View {
    var text: String
    private var depth: Int = 0

    init(text: String) {
        self.text = text
    }

    fileprivate init(text: String, depth: Int) {
        self.text = text
        self.depth = depth
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(Array(DTextParser.fragments(text, depth: depth).enumerated()), id: \.offset) { _, fragment in
                if let rows = fragment.rows {
                    ScrollView(.horizontal) {
                        Grid(alignment: .topLeading, horizontalSpacing: 12, verticalSpacing: 8) {
                            ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                                GridRow {
                                    ForEach(Array(row.enumerated()), id: \.offset) { _, cell in
                                        DTextView(text: cell, depth: depth + 1)
                                            .frame(width: 150, alignment: .leading)
                                    }
                                }
                            }
                        }
                    }
                } else if let title = fragment.title {
                    DTextDisclosure(title: title, text: fragment.text, expanded: fragment.expanded, depth: depth + 1)
                } else {
                    Text(AttributedString(DTextParser.parse(fragment.text)))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
    }
}

private struct DTextDisclosure: View {
    let title: String
    let text: String
    let depth: Int
    @State private var expanded: Bool

    init(title: String, text: String, expanded: Bool, depth: Int) {
        self.title = title
        self.text = text
        self.depth = depth
        _expanded = State(initialValue: expanded)
    }

    var body: some View {
        DisclosureGroup(title, isExpanded: $expanded) {
            DTextView(text: text, depth: depth)
        }
    }
}

enum DTextParser {
    struct Fragment {
        let text: String
        let title: String?
        var expanded: Bool = false
        var rows: [[String]]?
    }

    static func fragments(_ text: String, depth: Int = 0) -> [Fragment] {
        guard depth < 32 else { return [Fragment(text: "", title: nil)] }
        var result: [Fragment] = []
        var remaining = text[...]
        let pattern = #"\[(spoiler|section|table|ltable)(?:,expanded)?(?:=([^\]]*))?\]|\[code\]|`"#
        var cursor = remaining.startIndex
        while let opening = remaining.range(of: pattern, options: .regularExpression, range: cursor..<remaining.endIndex) {
            if remaining[opening] == "`" {
                if let end = remaining[opening.upperBound...].firstIndex(of: "`") {
                    cursor = remaining.index(after: end)
                } else {
                    cursor = opening.upperBound
                }
                continue
            }
            let marker = String(remaining[opening].dropFirst().dropLast())
            let parts = marker.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
            let tag = String(parts[0]).replacingOccurrences(of: ",expanded", with: "")
            guard let closing = closingRange(for: tag, in: remaining, after: opening.upperBound) else {
                cursor = opening.upperBound
                continue
            }
            if tag == "code" {
                cursor = closing.upperBound
                continue
            }
            if opening.lowerBound != remaining.startIndex {
                result.append(Fragment(text: String(remaining[..<opening.lowerBound]), title: nil))
            }
            let content = String(remaining[opening.upperBound..<closing.lowerBound])
            let title = parts.count == 2 && !parts[1].isEmpty ? String(parts[1]) : (tag == "spoiler" ? "Spoiler" : "Details")
            if tag == "table" || tag == "ltable" {
                let rows = tableRows(content, pipeSeparated: tag == "ltable")
                result.append(Fragment(text: rows.isEmpty ? String(remaining[opening.lowerBound..<closing.upperBound]) : content, title: nil, rows: rows.isEmpty ? nil : rows))
            } else {
                result.append(Fragment(text: content, title: title, expanded: parts[0].hasSuffix(",expanded")))
            }
            remaining = remaining[closing.upperBound...]
            cursor = remaining.startIndex
        }
        if !remaining.isEmpty { result.append(Fragment(text: String(remaining), title: nil)) }
        return result
    }

    static func parse(_ text: String) -> NSAttributedString {
        inline(text.replacingOccurrences(of: "\r\n", with: "\n"), attributes: [.font: UIFont.preferredFont(forTextStyle: .body)])
    }

    private static func inline(_ text: String, attributes: [NSAttributedString.Key: Any], depth: Int = 0) -> NSAttributedString {
        guard depth < 32 else { return NSAttributedString(string: text, attributes: attributes) }
        let result = NSMutableAttributedString(string: "")
        var remaining = text[...]
        while !remaining.isEmpty {
            if remaining.first == "\\", remaining.count > 1 {
                remaining.removeFirst()
                result.append(NSAttributedString(string: String(remaining.removeFirst()), attributes: attributes))
                continue
            }
            if remaining.first == "`", let end = remaining.dropFirst().firstIndex(of: "`") {
                var style = attributes
                let font = attributes[.font] as? UIFont ?? UIFont.preferredFont(forTextStyle: .body)
                style[.font] = UIFont.monospacedSystemFont(ofSize: font.pointSize, weight: .regular)
                result.append(NSAttributedString(string: String(remaining[remaining.index(after: remaining.startIndex)..<end]), attributes: style))
                remaining = remaining[remaining.index(after: end)...]
                continue
            }
            if remaining.hasPrefix("{{"), let end = remaining.range(of: "}}") {
                let query = String(remaining.dropFirst(2)[..<end.lowerBound])
                var components = URLComponents(string: "https://e621.net/posts")!
                components.queryItems = [URLQueryItem(name: "tags", value: query)]
                var style = attributes
                style[.link] = components.url
                result.append(NSAttributedString(string: query, attributes: style))
                remaining = remaining[end.upperBound...]
                continue
            }
            if let match = remaining.range(of: #"^(post changes|post|topic|forum|comment|blip|pool|set|takedown|record|ticket|thumb) #[0-9]+\b"#, options: .regularExpression) {
                let label = String(remaining[match])
                let parts = label.components(separatedBy: " #")
                let routes = [
                    "post": "posts", "topic": "forum_topics", "forum": "forum_posts",
                    "comment": "comments", "blip": "blips", "pool": "pools", "set": "post_sets",
                    "takedown": "takedowns", "record": "user_feedbacks", "ticket": "tickets", "thumb": "posts"
                ]
                let path = parts[0] == "post changes" ? "post_versions?search[post_id]=\(parts[1])" : "\(routes[parts[0]]!)/\(parts[1])"
                var style = attributes
                style[.link] = URL(string: "https://e621.net/\(path)")
                result.append(NSAttributedString(string: label, attributes: style))
                remaining = remaining[match.upperBound...]
                continue
            }
            if remaining.first == "<", let end = remaining.firstIndex(of: ">"),
               let url = safeURL(String(remaining[remaining.index(after: remaining.startIndex)..<end])) {
                var style = attributes
                style[.link] = url
                result.append(NSAttributedString(string: url.absoluteString, attributes: style))
                remaining = remaining[remaining.index(after: end)...]
                continue
            }
            if remaining.hasPrefix("[["), let end = remaining.range(of: "]]") {
                let content = String(remaining.dropFirst(2)[..<end.lowerBound])
                let parts = content.split(separator: "|", maxSplits: 1, omittingEmptySubsequences: false)
                let title = String(parts[0])
                var components = URLComponents(string: "https://e621.net/wiki_pages/show_or_new")!
                let anchorParts = title.split(separator: "#", maxSplits: 1, omittingEmptySubsequences: false)
                components.queryItems = [URLQueryItem(name: "title", value: String(anchorParts[0]))]
                if anchorParts.count == 2 { components.fragment = String(anchorParts[1]) }
                var style = attributes
                style[.link] = components.url
                result.append(inline(parts.count == 2 ? String(parts[1]) : title.replacingOccurrences(of: "_", with: " "), attributes: style, depth: depth + 1))
                remaining = remaining[end.upperBound...]
                continue
            }
            if remaining.first == "\"", let end = remaining.dropFirst().range(of: "\":") {
                let label = String(remaining[remaining.index(after: remaining.startIndex)..<end.lowerBound])
                let tail = remaining[end.upperBound...]
                let bracketEnd = tail.first == "[" ? tail.firstIndex(of: "]") : nil
                let target = bracketEnd.map { String(tail[tail.index(after: tail.startIndex)..<$0]) }
                    ?? String(tail.prefix { !$0.isWhitespace && $0 != "<" && $0 != ">" })
                if let url = safeURL(target) {
                    var style = attributes
                    style[.link] = url
                    result.append(inline(label, attributes: style, depth: depth + 1))
                    let nextIndex = bracketEnd.map { remaining.index(after: $0) } ?? remaining.index(end.upperBound, offsetBy: target.count)
                    remaining = remaining[nextIndex...]
                    continue
                }
            }
            if remaining.hasPrefix("http://") || remaining.hasPrefix("https://") {
                let target = remaining.prefix { !$0.isWhitespace && $0 != "<" && $0 != ">" && $0 != "[" }
                let trimmed = String(target).trimmingCharacters(in: CharacterSet(charactersIn: ".,;!?"))
                if let url = safeURL(trimmed) {
                    var style = attributes
                    style[.link] = url
                    result.append(NSAttributedString(string: trimmed, attributes: style))
                    remaining = remaining.dropFirst(trimmed.count)
                    continue
                }
            }
            if result.length == 0 || result.string.hasSuffix("\n") {
                if let match = remaining.range(of: #"^h([1-6])\. "#, options: .regularExpression) {
                    let marker = String(remaining[match])
                    let level = Int(String(marker.dropFirst().prefix(1))) ?? 1
                    let line = remaining[match.upperBound...].prefix { $0 != "\n" }
                    var style = attributes
                    style[.font] = UIFont.preferredFont(forTextStyle: level <= 2 ? .title2 : .headline)
                    result.append(inline(String(line), attributes: style, depth: depth + 1))
                    remaining = remaining[remaining.index(match.upperBound, offsetBy: line.count)...]
                    continue
                }
                if let match = remaining.range(of: #"^\*+ "#, options: .regularExpression) {
                    let count = remaining[match].count - 1
                    result.append(NSAttributedString(string: String(repeating: "  ", count: count - 1) + "\u{2022} ", attributes: attributes))
                    remaining = remaining[match.upperBound...]
                    continue
                }
            }
            if remaining.first == "[",
               let end = remaining.firstIndex(of: "]") {
                let tag = String(remaining[remaining.index(after: remaining.startIndex)..<end])
                     let parts = tag.split(separator: "=", maxSplits: 1)
                let name = parts.first.map(String.init) ?? ""
                     if ["b", "i", "u", "s", "sup", "sub", "code", "quote", "color"].contains(name),
                         let closing = closingRange(for: name, in: remaining, after: remaining.index(after: end)) {
                    let content = String(remaining[remaining.index(after: end)..<closing.lowerBound])
                    var style = attributes
                    let font = attributes[.font] as? UIFont ?? UIFont.preferredFont(forTextStyle: .body)
                    switch name {
                    case "b", "i":
                        let trait: UIFontDescriptor.SymbolicTraits = name == "b" ? .traitBold : .traitItalic
                        if let descriptor = font.fontDescriptor.withSymbolicTraits(font.fontDescriptor.symbolicTraits.union(trait)) {
                            style[.font] = UIFont(descriptor: descriptor, size: font.pointSize)
                        }
                    case "u": style[.underlineStyle] = NSUnderlineStyle.single.rawValue
                    case "s": style[.strikethroughStyle] = NSUnderlineStyle.single.rawValue
                    case "sup", "sub":
                        style[.font] = font.withSize(font.pointSize * 0.75)
                        style[.baselineOffset] = name == "sup" ? font.pointSize * 0.3 : -font.pointSize * 0.2
                    case "code": style[.font] = UIFont.monospacedSystemFont(ofSize: font.pointSize, weight: .regular)
                    case "color":
                        if parts.count == 2, let color = color(String(parts[1])) { style[.foregroundColor] = color }
                    default: style[.foregroundColor] = UIColor.secondaryLabel
                    }
                    if name == "quote" { result.append(NSAttributedString(string: "\n", attributes: attributes)) }
                    result.append(name == "code" ? NSAttributedString(string: content, attributes: style) : inline(content, attributes: style, depth: depth + 1))
                    if name == "quote" { result.append(NSAttributedString(string: "\n", attributes: attributes)) }
                    remaining = remaining[closing.upperBound...]
                    continue
                }
            }
            result.append(NSAttributedString(string: String(remaining.removeFirst()), attributes: attributes))
        }
        return result
    }

    private static func safeURL(_ text: String) -> URL? {
        let target = text.hasPrefix("/") && !text.hasPrefix("//") ? "https://e621.net" + text : text
        guard let url = URL(string: target),
              ["http", "https"].contains(url.scheme?.lowercased() ?? ""),
              url.host != nil else { return nil }
        return url
    }

    private static func color(_ value: String) -> UIColor? {
        let names: [String: UIColor] = [
            "red": .systemRed, "pink": .systemPink, "blue": .systemBlue,
            "green": .systemGreen, "yellow": .systemYellow, "orange": .systemOrange,
            "purple": .systemPurple, "black": .black, "white": .white, "gray": .gray,
            "grey": .gray, "cyan": .cyan, "magenta": .magenta, "brown": .brown,
            "artist": .systemYellow, "character": .systemGreen, "copyright": .systemPurple,
            "species": .systemRed, "general": .systemBlue, "meta": .gray,
            "invalid": .gray, "lore": .systemGreen
        ]
        if let color = names[value.lowercased()] { return color }
        guard value.hasPrefix("#") else { return nil }
        var hex = String(value.dropFirst())
        if hex.count == 3 { hex = hex.map { "\($0)\($0)" }.joined() }
        guard hex.count == 6, let rgb = UInt32(hex, radix: 16) else { return nil }
        return UIColor(red: CGFloat((rgb >> 16) & 255) / 255, green: CGFloat((rgb >> 8) & 255) / 255, blue: CGFloat(rgb & 255) / 255, alpha: 1)
    }

    private static func tableRows(_ text: String, pipeSeparated: Bool) -> [[String]] {
        if pipeSeparated {
            return text.split(separator: "\n").filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }.map {
                $0.split(separator: "|", omittingEmptySubsequences: false).map { $0.trimmingCharacters(in: .whitespaces) }
            }
        }
        var rows: [[String]] = []
        var remaining = text[...]
        while let opening = remaining.range(of: "[tr]"),
              let closing = remaining.range(of: "[/tr]", range: opening.upperBound..<remaining.endIndex) {
            var cells: [String] = []
            var row = remaining[opening.upperBound..<closing.lowerBound]
            while let cellOpening = row.range(of: #"\[t[dh]\]"#, options: .regularExpression) {
                let tag = String(row[cellOpening].dropFirst().dropLast())
                guard let cellClosing = row.range(of: "[/\(tag)]", range: cellOpening.upperBound..<row.endIndex) else { break }
                let content = String(row[cellOpening.upperBound..<cellClosing.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
                cells.append(tag == "th" ? "[b]\(content)[/b]" : content)
                row = row[cellClosing.upperBound...]
            }
            if !cells.isEmpty { rows.append(cells) }
            remaining = remaining[closing.upperBound...]
        }
        return rows
    }

    private static func closingRange(for tag: String, in text: Substring, after start: String.Index) -> Range<String.Index>? {
        var cursor = start
        var nesting = 1
        while let closing = text.range(of: "[/\(tag)]", range: cursor..<text.endIndex) {
            if tag != "code", let opening = text.range(of: "\\[\(tag)(?:,expanded)?(?:=[^\\]]*)?\\]", options: .regularExpression, range: cursor..<closing.lowerBound) {
                nesting += 1
                cursor = opening.upperBound
            } else {
                nesting -= 1
                if nesting == 0 { return closing }
                cursor = closing.upperBound
            }
        }
        return nil
    }
}