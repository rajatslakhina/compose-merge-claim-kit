/// Reads what an answer says the merged files do: "with both files, `web` publishes `8080` and `8081`", "`DEBUG`
/// is `1`", "`web` now runs `npm run dev`". A clause about one file, about a change still to make, or about what
/// someone might expect makes no claim.
struct EffectReader {
    let scene: MergeScene

    static let hypothetical = ["if", "would", "could", "should", "might", "want", "wanted", "need", "needs",
                               "unless", "suppose", "imagine", "try", "you can", "to make", "so that", "in order to",
                               "expect", "expected", "expecting", "think", "thought", "assume", "assumed", "seems",
                               "seemed", "hope", "intend", "intended", "meant to", "supposed to", "otherwise"]
    static let imperatives = ["add", "set", "change", "use", "put", "create", "remove", "replace", "run", "write",
                              "define", "move", "delete", "rename", "keep", "make", "drop", "tag", "list", "pass",
                              "copy", "edit", "update", "declare"]
    static let fileScope = ["base file", "override file", "first file", "second file", "in the override",
                            "in the base", "the original", "originally", "before", "previously", "by itself",
                            "on its own", "alone", "the override sets", "the override has", "the base has",
                            "the base sets", "the override says", "the base says", "the override defines",
                            "the base defines", "earlier", "the override", "the base", "by default", "normally",
                            "default"]
    /// Cues that say a clause is about the merged files even when it names one file.
    static let strongCue = ["with both", "both files", "with the override", "with this override", "with that override",
                            "together", "merged", "merging", "combined", "the result", "ends up", "end up",
                            "effective", "final", "in the end", "after the merge", "when compose merges",
                            "once merged", "after merging", "these files"]
    /// Cues that let a sentence be called wrong for a slip one file alone reproduces. "Still" and "now" say a
    /// value is current, not which file it comes from, so they do not lift a clause that names one file.
    static let mergedCue = strongCue + ["now", "still", "keeps", "no longer", "instead of", "anymore", "both"]

    func claims(in sentence: String) -> [MergeClaim.Subject] {
        let services = scene.services
        guard !services.isEmpty, !sentence.trimmed.hasSuffix("?") else { return [] }
        let whole = Clauses.plain(sentence)
        guard !Words.containsAny(whole, Self.hypothetical) else { return [] }
        if whole.hasPrefix("to ") || Clauses.split(whole).contains(where: Self.isInstruction) { return [] }
        var subjects: [MergeClaim.Subject] = []
        var current = service(in: sentence, services)
        for clause in Clauses.split(sentence) {
            let text = Clauses.plain(clause)
            if let named = service(in: clause, services) { current = named }
            // A file a `docker compose -f` command names is not what the clause is about.
            let scope = Sentences.pieces(clause).filter { !$0.isCode || Commands.selections(inLine: $0.text).isEmpty }
                .map(\.text).joined(separator: " ").folded
            if Words.containsAny(text, Self.fileScope), !Words.containsAny(text, Self.strongCue) { continue }
            if !ComposeFile.names(in: scope).isEmpty, !Words.containsAny(text, Self.strongCue) { continue }
            subjects += read(clause, text, current)
        }
        return subjects
    }

    /// Whether a clause starts with an instruction ("add `!override`", "then set ..."): it says what to do, not
    /// what the files do. "Run `docker compose ...`" is not one: the rest of the sentence says what that run does.
    static func isInstruction(_ clause: String) -> Bool {
        let words = clause.split(whereSeparator: { !$0.isLetter }).map(String.init)
        guard let first = words.first else { return false }
        let start = ["then", "just", "simply", "instead", "also", "now", "first"].contains(first) ? 1 : 0
        guard words.count > start, imperatives.contains(words[start]) else { return false }
        return !(words[start] == "run" && !Commands.selections(inLine: clause).isEmpty)
    }

    func read(_ clause: String, _ text: String, _ named: String?) -> [MergeClaim.Subject] {
        let code = Sentences.pieces(clause).filter(\.isCode).map { $0.text.trimmed }
        var found: [MergeClaim.Subject] = []
        found += variables(clause, named)
        if let service = named ?? only(in: { !$0.images.isDisjoint(with: code) }),
           let image = image(text, code, service) {
            found.append(image)
        }
        let prose = Sentences.pieces(clause).filter { !$0.isCode }.map(\.text).joined(separator: " ").folded
        if let service = named ?? only(in: { !$0.commands.isEmpty }), let command = command(prose, code, service) {
            found.append(command)
        }
        if let service = named ?? only(in: { !$0.published.isEmpty }), let ports = ports(text, code, service) {
            found.append(ports)
        }
        return found
    }

    /// A service named in backticks, or as "`web` service", "the web service", "service web".
    func service(in clause: String, _ services: [String]) -> String? {
        let code = Sentences.pieces(clause).filter(\.isCode).map { $0.text.trimmed }
        if let named = code.first(where: services.contains) { return named }
        let text = clause.folded
        return services.first { name in
            let lower = name.lowercased()
            return Words.containsAny(text, ["\(lower) service", "service \(lower)", "\(lower) container",
                                            "\(lower)'s"])
        }
    }

    /// What the shown files write for each service, across every file.
    struct Written {
        var images: Set<String> = []
        var commands: [[String]] = []
        var published: Set<Int> = []
        var variables: Set<String> = []
    }

    func written(_ service: String) -> Written {
        var written = Written()
        for file in scene.files {
            guard let node = file.node?["services"]?[service].flatMap({ Normalize.service($0).untagged }) else {
                continue
            }
            if let image = node["image"]?.text { written.images.insert(image) }
            if let command = node["command"]?.items { written.commands.append(command.compactMap(\.text)) }
            for item in node["ports"]?.items ?? [] {
                if let published = PortBinding.read(item)?.published { written.published.insert(published) }
            }
            for entry in node["environment"]?.entries ?? [] { written.variables.insert(entry.key) }
        }
        return written
    }

    /// The one service whose files write something, when exactly one does.
    func only(in test: (Written) -> Bool) -> String? {
        let matching = scene.services.filter { test(written($0)) }
        return matching.count == 1 ? matching.first : nil
    }

    func image(_ text: String, _ code: [String], _ service: String) -> MergeClaim.Subject? {
        guard Clauses.negationCount(text) == 0, !Words.containsAny(text, ["instead of", "rather than"]) else {
            return nil
        }
        let images = written(service).images
        guard let image = code.first(where: images.contains) else { return nil }
        return .image(service: service, image: image)
    }

    /// `prose` is the clause without its inline code, so a cue inside the command (`npm start`) does not count.
    func command(_ prose: String, _ code: [String], _ service: String) -> MergeClaim.Subject? {
        guard Clauses.negationCount(prose) == 0,
              Words.containsAny(prose, ["run", "runs", "command", "start", "starts", "execute", "executes",
                                        "launch", "launches"]) else { return nil }
        let commands = written(service).commands
        let known = Set(commands.map { $0.joined(separator: " ") } + [commands.flatMap { $0 }.joined(separator: " ")])
        guard let command = code.first(where: { word in
            ShellWords.split(word).map { known.contains($0.joined(separator: " ")) } ?? false
        }) else { return nil }
        return .command(service: service, command: command)
    }

    static let portCues = ["port", "ports", "publish", "publishes", "published", "expose", "exposes", "exposed",
                           "listen", "listens", "available", "reachable", "bind", "binds", "bound", "mapped", "maps",
                           "mapping", "mappings", "localhost", "serves", "served", "open", "opens"]
    static let absentCues = ["removes", "removed", "drops", "dropped", "gone", "disappears", "disappear",
                             "replaces", "replaced"]

    /// A port word, or a `HOST:CONTAINER` mapping in inline code, makes the clause about ports.
    func ports(_ text: String, _ code: [String], _ service: String) -> MergeClaim.Subject? {
        let mapping = code.contains { $0.contains(":") && PortBinding.short($0) != nil }
        guard mapping || Words.containsAny(text, Self.portCues), !Words.contains(text, "not only") else { return nil }
        let known = written(service).published
        let numbers = Self.numbers(in: text).filter { known.contains($0.value) }
        guard !numbers.isEmpty else { return nil }
        var claim = MergeClaim.PortClaim()
        let swap = Clauses.position(text, ["instead of", "rather than", "replaced by", "replaced with"])
        let replaces = Clauses.position(text, ["replaces"])
        let withWord = replaces.flatMap { start in text[start...].range(of: " with ")?.lowerBound }
        for (position, value) in numbers {
            let absent: Bool
            if let swap {
                // "8081 instead of 8080": after the cue is gone; "8080 is replaced by 8081": before it is gone.
                absent = text[swap...].hasPrefix("replaced") ? position < swap : position > swap
            } else if let replaces, let withWord {
                absent = position > replaces && position < withWord
            } else {
                absent = Clauses.negationCount(text) > 0 || Words.containsAny(text, Self.absentCues)
            }
            if absent { claim.absent.insert(value) } else { claim.present.insert(value) }
        }
        claim.exact = Words.containsAny(text, ["only", "just"]) && !claim.present.isEmpty
        guard claim.present.isDisjoint(with: claim.absent) else { return nil }
        return .ports(service: service, claim)
    }

    /// Port numbers in the text and where each starts: a bare number, the host side of `8081:80`, the port of
    /// `localhost:8081`.
    static func numbers(in text: String) -> [(position: String.Index, value: Int)] {
        var found: [(String.Index, Int)] = []
        var index = text.startIndex
        while index < text.endIndex {
            guard isTokenCharacter(text[index]) else {
                index = text.index(after: index)
                continue
            }
            let start = index
            while index < text.endIndex, isTokenCharacter(text[index]) { index = text.index(after: index) }
            var token = String(text[start..<index])
            while let last = token.last, ".:/".contains(last) { token.removeLast() }
            if let value = port(in: token) { found.append((start, value)) }
        }
        return found
    }

    static func isTokenCharacter(_ character: Character) -> Bool {
        character.isLetter || character.isNumber || ".:/[]-_".contains(character)
    }

    static func port(in token: String) -> Int? {
        if let host = ["localhost:", "127.0.0.1:", "0.0.0.0:"].compactMap({ token.range(of: $0) }).first {
            return Int(token[host.upperBound...].prefix { $0.isNumber })
        }
        if token.contains(":"), let binding = PortBinding.short(token) { return binding.published }
        guard let value = Int(token), (1...65535).contains(value) else { return nil }
        return value
    }

    /// Each variable the clause names, read from its own part of the clause (up to the next variable), so "`DEBUG`
    /// is `1` and `LOG_LEVEL` is gone" says two things.
    func variables(_ clause: String, _ named: String?) -> [MergeClaim.Subject] {
        let pieces = Sentences.pieces(clause)
        struct Start {
            let index: Int
            let name: String
            let value: String?
            let service: String
        }
        var starts: [Start] = []
        for (index, piece) in pieces.enumerated() where piece.isCode {
            let word = piece.text.trimmed
            let pair = word.split(separator: "=", maxSplits: 1).map(String.init)
            let name = pair.count == 2 ? pair[0] : word
            guard let service = named.flatMap({ written($0).variables.contains(name) ? $0 : nil })
                ?? only(in: { $0.variables.contains(name) }) else { continue }
            starts.append(Start(index: index, name: name, value: pair.count == 2 ? pair[1] : nil, service: service))
        }
        var found: [MergeClaim.Subject] = []
        for (number, start) in starts.enumerated() {
            let end = number + 1 < starts.count ? starts[number + 1].index : pieces.count
            let part = pieces[(start.index + 1)..<end]
            let text = part.filter { !$0.isCode }.map(\.text).joined(separator: " ").folded
            let code = part.filter(\.isCode).map { $0.text.trimmed }.filter { !scene.services.contains($0) }
            if let claim = variable(text, code, start.value) {
                found.append(.variable(service: start.service, name: start.name, claim))
            }
        }
        return found
    }

    /// What one part of a clause says about its variable: `text` is the part's prose, `code` its inline code after
    /// the name, `value` the value written as `NAME=value`.
    func variable(_ text: String, _ code: [String], _ value: String?) -> MergeClaim.VariableClaim? {
        let negated = Clauses.negationCount(text) > 0
        if let value, !negated { return .value(value) }
        if Words.containsAny(text, ["removed", "gone", "unset", "no longer set", "not set", "dropped", "disappears",
                                    "is cleared"]) {
            return .unset
        }
        guard !negated else { return nil }
        if let value = code.first, Words.containsAny(text, ["is", "becomes", "stays", "remains", "set to", "equals",
                                                            "will be", "keeps"]) {
            return .value(value)
        }
        if Words.containsAny(text, ["still set", "is kept", "stays", "remains", "survives", "still there"]) {
            return .kept
        }
        return nil
    }
}
