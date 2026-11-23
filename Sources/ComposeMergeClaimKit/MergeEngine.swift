/// Merges compose files the way `docker compose -f a -f b config` does. With a slip, merges them the way someone who
/// makes that mistake expects, so a stated result can be traced to the mistake behind it.
struct MergeEngine {
    let slip: MergeFinding.Slip?

    init(slip: MergeFinding.Slip? = nil) {
        self.slip = slip
    }

    /// Replaced by a later file, never appended (`healthcheck`'s `test` too).
    static let replaced: Set<String> = ["command", "entrypoint"]
    /// Written as `KEY=value` items or as a mapping; merged by key.
    static let mappings: Set<String> = ["environment", "labels", "annotations", "sysctls"]
    /// Sequences whose items are merged by the mount point.
    static let byTarget: Set<String> = ["volumes", "secrets", "configs"]

    func merge(_ files: [ComposeNode]) -> ComposeNode {
        guard let first = files.first else { return .null }
        var result = clean(Normalize.file(first))
        for file in files.dropFirst() {
            result = top(result, Normalize.file(file))
        }
        return result
    }

    func top(_ base: ComposeNode, _ over: ComposeNode) -> ComposeNode {
        guard let baseEntries = base.entries, let overEntries = over.entries else {
            return over == .reset ? base : clean(over)
        }
        return .map(entries(baseEntries, overEntries) { key, base, over in
            key == "services" ? services(base, over) : generic(base, over)
        })
    }

    func services(_ base: ComposeNode, _ over: ComposeNode) -> ComposeNode {
        guard let baseEntries = base.entries, let overEntries = over.entries else { return over }
        return .map(entries(baseEntries, overEntries) { _, base, over in service(base, over) })
    }

    /// A later file's empty `web:` keeps the earlier service as it is.
    func service(_ base: ComposeNode, _ over: ComposeNode) -> ComposeNode {
        guard let baseEntries = base.entries, let overEntries = over.entries else { return over == .null ? base : over }
        return .map(entries(baseEntries, overEntries, attribute))
    }

    /// Merges two mappings: a later key's value merges with (or replaces) the earlier one in place, a new key is
    /// added at the end, `!reset` drops the key and `!override` sets it without merging.
    func entries(_ base: [ComposeEntry], _ over: [ComposeEntry],
                 _ combine: (String, ComposeNode, ComposeNode) -> ComposeNode) -> [ComposeEntry] {
        var result = base
        for entry in over {
            let index = result.firstIndex { $0.key == entry.key }
            let value: ComposeNode? = switch entry.value {
            case .reset: nil
            case let .replace(node): node.untagged
            default: index.map { combine(entry.key, result[$0].value, entry.value) } ?? entry.value.untagged
            }
            if let index {
                if let value {
                    result[index] = ComposeEntry(key: entry.key, value: value)
                } else {
                    result.remove(at: index)
                }
            } else if let value {
                result.append(ComposeEntry(key: entry.key, value: value))
            }
        }
        return result
    }

    func attribute(_ key: String, _ base: ComposeNode, _ over: ComposeNode) -> ComposeNode {
        if Self.replaced.contains(key) {
            if slip == .commandAppended, let first = base.items, let second = over.items {
                return .list(first + second)
            }
            return scalar(base, over)
        }
        if key == "healthcheck", let baseEntries = base.entries, let overEntries = over.entries {
            return .map(entries(baseEntries, overEntries) { key, base, over in
                key == "test" ? attribute("command", base, over) : generic(base, over)
            })
        }
        if Self.mappings.contains(key), let baseEntries = base.entries, let overEntries = over.entries {
            if slip == .mappingReplaced { return clean(over) }
            return .map(entries(baseEntries, overEntries) { _, base, over in scalar(base, over) })
        }
        if let first = base.items, let second = over.items {
            if second.isEmpty, slip == .emptyListClears { return .list([]) }
            if !second.isEmpty, slip == .listReplaced { return clean(over) }
            if key == "ports" { return .list(keyed(first, second, by: PortBinding.key)) }
            if Self.byTarget.contains(key) { return .list(keyed(first, second, by: Mount.key)) }
        }
        return generic(base, over)
    }

    func generic(_ base: ComposeNode, _ over: ComposeNode) -> ComposeNode {
        if let baseEntries = base.entries, let overEntries = over.entries {
            return .map(entries(baseEntries, overEntries) { _, base, over in generic(base, over) })
        }
        if let first = base.items, let second = over.items { return appended(first, second) }
        return scalar(base, over)
    }

    /// The node without merge tags; `!reset` on its own is no value.
    func clean(_ node: ComposeNode) -> ComposeNode {
        node.untagged ?? .null
    }

    /// The later value, or the earlier one for someone who thinks the first file wins.
    func scalar(_ base: ComposeNode, _ over: ComposeNode) -> ComposeNode {
        slip == .earlierFileWins && base != .null ? base : clean(over)
    }

    /// The earlier items, then the later items that are not already there.
    func appended(_ first: [ComposeNode], _ second: [ComposeNode]) -> ComposeNode {
        var items = first
        for item in second.compactMap(\.untagged) where !items.contains(item) {
            items.append(item)
        }
        return .list(items)
    }

    /// Items with the same key merge into one (the later one, or the earlier for the first-file-wins slip); others
    /// are appended.
    func keyed(_ base: [ComposeNode], _ over: [ComposeNode], by key: (ComposeNode) -> String) -> [ComposeNode] {
        var items = base
        for item in over {
            guard let clean = item.untagged else { continue }
            if let index = items.firstIndex(where: { key($0) == key(clean) }) {
                if slip != .earlierFileWins { items[index] = clean }
            } else {
                items.append(clean)
            }
        }
        return items
    }
}

/// Brings the forms compose accepts for one attribute to one form, so two files can be merged item by item.
enum Normalize {
    static func file(_ node: ComposeNode) -> ComposeNode {
        guard let entries = node.entries else { return node }
        return .map(entries.map { entry in
            guard entry.key == "services", let services = entry.value.entries else { return entry }
            return ComposeEntry(key: "services", value: .map(services.map {
                ComposeEntry(key: $0.key, value: tagged($0.value, service))
            }))
        })
    }

    /// Applies a normalisation under compose's merge tags.
    static func tagged(_ node: ComposeNode, _ body: (ComposeNode) -> ComposeNode) -> ComposeNode {
        switch node {
        case .reset: .reset
        case let .replace(inner): .replace(body(inner))
        default: body(node)
        }
    }

    static func service(_ node: ComposeNode) -> ComposeNode {
        guard let entries = node.entries else { return node }
        return .map(entries.map { entry in
            ComposeEntry(key: entry.key, value: tagged(entry.value) { attribute(entry.key, $0) })
        })
    }

    static func attribute(_ key: String, _ node: ComposeNode) -> ComposeNode {
        if MergeEngine.mappings.contains(key), let items = node.items { return .map(items.compactMap(pair)) }
        if key == "depends_on", let items = node.items {
            return .map(items.compactMap { $0.text.map { ComposeEntry(key: $0, value: .null) } })
        }
        if MergeEngine.replaced.contains(key), let text = node.text {
            return ShellWords.split(text).map { .list($0.map(ComposeNode.scalar)) } ?? node
        }
        if key == "build", let text = node.text { return .map([ComposeEntry(key: "context", value: .scalar(text))]) }
        return node
    }

    /// `KEY=value` as a mapping entry; `KEY` alone has no value (compose takes it from the shell).
    static func pair(_ item: ComposeNode) -> ComposeEntry? {
        guard let text = item.text else { return nil }
        guard let equals = text.firstIndex(of: "=") else { return ComposeEntry(key: text, value: .null) }
        return ComposeEntry(key: String(text[..<equals]), value: .scalar(String(text[text.index(after: equals)...])))
    }
}

/// Splits a command written as one string into words, the way compose does (quotes group, a backslash escapes).
enum ShellWords {
    static func split(_ text: String) -> [String]? {
        var words: [String] = []
        var current = ""
        var inWord = false
        var quote: Character?
        var escaped = false
        for character in text {
            if escaped {
                current.append(character)
                escaped = false
            } else if character == "\\", quote != "'" {
                escaped = true
                inWord = true
            } else if let open = quote {
                if character == open { quote = nil } else { current.append(character) }
            } else if character == "\"" || character == "'" {
                quote = character
                inWord = true
            } else if character.isWhitespace {
                if inWord { words.append(current) }
                current = ""
                inWord = false
            } else {
                current.append(character)
                inWord = true
            }
        }
        guard quote == nil, !escaped else { return nil }
        if inWord { words.append(current) }
        return words
    }
}
