import Foundation

/// One compose file shown in a conversation: its name (when the conversation gives one) and what it says.
public struct ComposeFile: Sendable, Hashable {
    /// What compose does with a file of this name when `docker compose` runs without `-f`.
    public enum Role: String, Sendable, Hashable {
        /// `compose.yaml`, `compose.yml`, `docker-compose.yaml` or `docker-compose.yml`: read by default.
        case base
        /// `compose.override.yaml` (or `.yml`, or the `docker-compose.` names): read after the base by default.
        case override
        /// Any other name (`docker-compose.prod.yml`): read only when a `-f` names it.
        case other
    }

    public enum Content: Sendable, Hashable {
        case node(ComposeNode)
        case unreadable(String)
    }

    /// The name as the conversation writes it (`./docker-compose.override.yml`), or `nil`.
    public let name: String?
    public let content: Content

    public init(name: String?, content: Content) {
        self.name = name
        self.content = content
    }

    public var role: Role? {
        name.map(ComposeFile.role)
    }

    /// The name without a leading directory.
    var basename: String? {
        name.map(ComposeFile.basename)
    }

    var node: ComposeNode? {
        if case let .node(node) = content { return node }
        return nil
    }

    static let baseNames = ["compose.yaml", "compose.yml", "docker-compose.yaml", "docker-compose.yml"]
    static let overrideNames = ["compose.override.yaml", "compose.override.yml", "docker-compose.override.yaml",
                                "docker-compose.override.yml"]

    /// The part after the last `/` (all of it when there is none).
    static func basename(_ name: String) -> String {
        guard let slash = name.lastIndex(of: "/") else { return name }
        return String(name[name.index(after: slash)...])
    }

    static func role(_ name: String) -> Role {
        let base = basename(name).lowercased()
        if baseNames.contains(base) { return .base }
        if overrideNames.contains(base) { return .override }
        return .other
    }

    /// Whether a word names a compose file: it ends in `.yml` or `.yaml` and its last part contains `compose`.
    static func isComposeName(_ word: String) -> Bool {
        let base = basename(word).lowercased()
        return (base.hasSuffix(".yml") || base.hasSuffix(".yaml")) && base.contains("compose")
            && base.allSatisfy { $0.isLetter || $0.isNumber || "._-".contains($0) }
    }

    /// The compose file names written in a text, in order, each once.
    static func names(in text: String) -> [String] {
        var names: [String] = []
        let words = text.components(separatedBy: CharacterSet(charactersIn: " \t`\"'(),;:=*"))
        for word in words {
            var candidate = word
            while let last = candidate.last, ".!?".contains(last), !isComposeName(candidate) {
                candidate.removeLast()
            }
            if candidate.hasPrefix("./") { candidate.removeFirst(2) }
            if isComposeName(candidate), !names.contains(candidate) { names.append(candidate) }
        }
        return names
    }

    /// Reads a code block as a compose file: it must be YAML with a `services:` mapping. A block whose YAML this
    /// kit does not follow is still a compose file when its text has a top-level `services:` line.
    static func read(_ lines: [String], name: String?) -> ComposeFile? {
        let source = lines.joined(separator: "\n")
        let topLevel = lines.contains { $0.hasPrefix("services:") }
        do {
            let node = try ComposeYAML.parse(source)
            guard case .map? = node["services"], topLevel else { return nil }
            return ComposeFile(name: name, content: .node(node))
        } catch {
            guard topLevel else { return nil }
            return ComposeFile(name: name, content: .unreadable(error.reason))
        }
    }
}
