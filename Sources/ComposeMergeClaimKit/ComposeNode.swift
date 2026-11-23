/// A YAML value as far as a compose file needs one. Scalars stay text, the way compose reads most of them. The two
/// merge tags compose defines are kept: `!reset` (drop what earlier files set) and `!override` (replace it whole).
public indirect enum ComposeNode: Sendable, Hashable {
    case null
    case scalar(String)
    case list([ComposeNode])
    case map([ComposeEntry])
    /// `!reset`: the value written after the tag is ignored.
    case reset
    /// `!override` and the value that replaces what earlier files set.
    case replace(ComposeNode)

    /// The value under a key of a mapping; the last one when a key repeats.
    public subscript(key: String) -> ComposeNode? {
        entries?.last { $0.key == key }?.value
    }

    public var text: String? {
        if case let .scalar(text) = self { return text }
        return nil
    }

    public var items: [ComposeNode]? {
        if case let .list(items) = self { return items }
        return nil
    }

    public var entries: [ComposeEntry]? {
        if case let .map(entries) = self { return entries }
        return nil
    }

    /// The node as a single file means it: `!override` keeps its value, `!reset` drops the key.
    var untagged: ComposeNode? {
        switch self {
        case .reset: nil
        case let .replace(node): node.untagged
        case let .list(items): .list(items.compactMap(\.untagged))
        case let .map(entries): .map(entries.compactMap { entry in
                entry.value.untagged.map { ComposeEntry(key: entry.key, value: $0) }
            })
        default: self
        }
    }
}

public struct ComposeEntry: Sendable, Hashable {
    public let key: String
    public let value: ComposeNode

    public init(key: String, value: ComposeNode) {
        self.key = key
        self.value = value
    }
}
