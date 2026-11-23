/// Merge tags and flow collections, the parts of the reader that work on one line.
extension ComposeYAML {
    /// `!reset` (true) or `!override` (false) at the start of a mapping's value, and the text after it; `nil` when the
    /// value has no tag. Any other tag is refused.
    static func tag(_ text: String, line: Int) throws(Unsupported) -> (Bool, String)? {
        guard text.first == "!" else { return nil }
        let name = String(text.prefix { !$0.isWhitespace })
        guard name == "!reset" || name == "!override" else {
            throw Unsupported(reason: "a `\(name)` tag (line \(line))")
        }
        return (name == "!reset", String(text.dropFirst(name.count)).trimmed)
    }

    /// `{}` or `{a: 1, b: "x"}`: a flow mapping of scalars on one line.
    static func flowMap(_ text: String, line: Int) throws(Unsupported) -> ComposeNode {
        guard text.hasSuffix("}"), text.count >= 2 else {
            throw Unsupported(reason: "a flow mapping over several lines (line \(line))")
        }
        var entries: [ComposeEntry] = []
        for item in try items(text.dropFirst().dropLast(), line: line) where !item.isEmpty {
            guard let (key, rest) = ComposeYAML.key(item) else {
                throw Unsupported(reason: "a flow mapping entry this reader does not follow (line \(line))")
            }
            entries.append(ComposeEntry(key: key, value: rest.isEmpty ? .null : try value(rest, line: line)))
        }
        return .map(entries)
    }

    /// `[80, "443", 'x']`: a flow sequence of scalars on one line.
    static func flow(_ text: String, line: Int) throws(Unsupported) -> ComposeNode {
        guard text.hasSuffix("]"), text.count >= 2 else {
            throw Unsupported(reason: "a flow sequence over several lines (line \(line))")
        }
        let trimmed = try items(text.dropFirst().dropLast(), line: line)
        if trimmed == [""] { return .list([]) }
        var nodes: [ComposeNode] = []
        for item in trimmed where !item.isEmpty {
            nodes.append(try value(item, line: line))
        }
        return .list(nodes)
    }

    /// The comma-separated items of a flow collection's inside, trimmed.
    static func items(_ inside: Substring, line: Int) throws(Unsupported) -> [String] {
        var items: [String] = []
        var current = ""
        var quote: Character?
        for character in inside {
            if let open = quote {
                if character == open { quote = nil }
            } else if character == "\"" || character == "'" {
                quote = character
            } else if character == "," {
                items.append(current)
                current = ""
                continue
            } else if "[]{}".contains(character) {
                throw Unsupported(reason: "a nested flow collection (line \(line))")
            }
            current.append(character)
        }
        items.append(current)
        return items.map(\.trimmed)
    }
}
