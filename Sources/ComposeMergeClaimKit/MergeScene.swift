import Foundation

/// What a conversation has shown so far: the compose files (by name; a later version replaces an earlier one) and
/// how `docker compose` was run.
public struct MergeScene: Sendable, Hashable {
    /// Which files a `docker compose` command reads.
    public enum Selection: Sendable, Hashable {
        /// No `-f`: the base file and its override, if shown.
        case defaults
        /// `-f a -f b`: these files, in this order.
        case files([String])
        /// The conversation runs compose in different ways, or sets `COMPOSE_FILE`.
        case unclear
    }

    public internal(set) var files: [ComposeFile] = []
    public internal(set) var selection: Selection = .defaults

    public init(files: [ComposeFile] = [], selection: Selection = .defaults) {
        self.files = files
        self.selection = selection
    }

    mutating func add(_ file: ComposeFile) {
        if let name = file.basename, let index = files.firstIndex(where: { $0.basename == name }) {
            files[index] = file
        } else {
            files.append(file)
        }
    }

    /// Every service name the shown files mention.
    var services: [String] {
        var names: [String] = []
        for file in files {
            guard let services = file.node?["services"]?.entries else { continue }
            for entry in services where !names.contains(entry.key) { names.append(entry.key) }
        }
        return names
    }

    /// The files compose reads, in order, or why that is not known.
    func applied() -> Result<[ComposeFile], Unknown> {
        switch selection {
        case .unclear:
            return .failure(Unknown("the conversation runs compose with different files"))
        case let .files(names):
            var picked: [ComposeFile] = []
            for name in names {
                let base = ComposeFile.basename(name)
                guard let file = files.first(where: { $0.basename == base }) else {
                    return .failure(Unknown("`\(name)` is not shown"))
                }
                picked.append(file)
            }
            return readable(picked)
        case .defaults:
            let bases = files.filter { $0.role == .base }
            let overrides = files.filter { $0.role == .override }
            guard bases.count == 1, let base = bases.first else {
                return .failure(Unknown(bases.isEmpty ? "no base compose file is shown"
                    : "several base compose files are shown, and compose reads only one"))
            }
            guard overrides.count <= 1 else {
                return .failure(Unknown("several override files are shown, and compose reads only one"))
            }
            return readable([base] + overrides)
        }
    }

    /// The files someone who makes the slip would think compose reads; `nil` when the files are not known or the
    /// slip changes nothing here.
    func applied(_ slip: MergeFinding.Slip) -> Result<[ComposeFile], Unknown>? {
        guard case let .success(chosen) = applied() else { return nil }
        switch (slip, selection) {
        case (.overrideLoadedWithFile, .files):
            let left = files.filter { $0.role == .override && !chosen.contains($0) }
            guard let override = left.first else { return nil }
            return readable(chosen + [override])
        case (.overrideNotLoaded, .defaults):
            return chosen.count == 2 ? .success([chosen[0]]) : nil
        case (.extraFileAutoLoaded, .defaults):
            let others = files.filter { $0.role == .other }
            return others.isEmpty ? nil : readable(chosen + others)
        case (.overrideLoadedWithFile, _), (.overrideNotLoaded, _), (.extraFileAutoLoaded, _):
            return nil
        default:
            return .success(chosen)
        }
    }

    func readable(_ chosen: [ComposeFile]) -> Result<[ComposeFile], Unknown> {
        for file in chosen {
            if case let .unreadable(reason) = file.content {
                let label = file.name.map { "`\($0)`" }
                return .failure(Unknown([label, "uses", reason].compactMap { $0 }.joined(separator: " ")))
            }
        }
        return .success(chosen)
    }
}

/// Why something could not be worked out.
public struct Unknown: Error, Sendable, Hashable {
    public let reason: String

    init(_ reason: String) {
        self.reason = reason
    }
}

/// `docker compose` command lines: which files each one reads.
enum Commands {
    /// The selection of every `docker compose` command in the text, in order.
    static func selections(in text: String) -> [MergeScene.Selection] {
        var found: [MergeScene.Selection] = []
        for line in text.components(separatedBy: "\n") {
            for piece in line.components(separatedBy: "`") {
                found += selections(inLine: piece)
            }
        }
        return found
    }

    static func selections(inLine line: String) -> [MergeScene.Selection] {
        var found: [MergeScene.Selection] = []
        for segment in line.components(separatedBy: CharacterSet(charactersIn: ";|&")) {
            let words = segment.split(whereSeparator: \.isWhitespace).map(String.init)
            guard let start = commandStart(words) else { continue }
            if words[..<start].contains(where: { $0.hasPrefix("COMPOSE_FILE=") }) {
                found.append(.unclear)
                continue
            }
            found.append(selection(words[start...]))
        }
        return found
    }

    /// Compose's own flags that take a value. They come before the subcommand; after it, `-f` can mean
    /// something else (`docker compose logs -f` follows the log).
    static let valued: Set<String> = ["-p", "--project-name", "--env-file", "--profile", "--project-directory",
                                      "--ansi", "--progress", "--parallel"]

    static func selection(_ words: ArraySlice<String>) -> MergeScene.Selection {
        var files: [String] = []
        var index = words.startIndex
        while index < words.endIndex, words[index].hasPrefix("-") {
            let word = words[index]
            if word == "-f" || word == "--file" || valued.contains(word) {
                if word == "-f" || word == "--file", index + 1 < words.endIndex {
                    files.append(clean(words[index + 1]))
                }
                index += 2
                continue
            }
            if word.hasPrefix("--file=") { files.append(clean(String(word.dropFirst(7)))) }
            index += 1
        }
        return files.isEmpty ? .defaults : .files(files)
    }

    /// The index after `docker compose` or `docker-compose`, or `nil` when the words run neither.
    static func commandStart(_ words: [String]) -> Int? {
        for (index, word) in words.enumerated() {
            if word == "docker-compose" { return index + 1 }
            if word == "docker", index + 1 < words.count, words[index + 1] == "compose" { return index + 2 }
        }
        return nil
    }

    static func clean(_ word: String) -> String {
        var name = word.trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
        if name.hasPrefix("./") { name.removeFirst(2) }
        return name
    }

    /// One selection for a conversation: the one every command agrees on, `.defaults` when there is none.
    static func combined(_ selections: [MergeScene.Selection]) -> MergeScene.Selection {
        guard let first = selections.first else { return .defaults }
        return selections.allSatisfy { $0 == first } ? first : .unclear
    }
}
