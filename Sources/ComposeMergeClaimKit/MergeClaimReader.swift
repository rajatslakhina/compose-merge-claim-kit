/// Finds what an answer says about merging compose files: the rules it states, the results it states for the files
/// it shows, and a later file's `key: []` that keeps an earlier file's items.
public struct MergeClaimReader: Sendable {
    /// Also read the files themselves for a `key: []` that keeps an earlier file's items.
    public let checksLines: Bool

    public init(checksLines: Bool = true) {
        self.checksLines = checksLines
    }

    /// The answer's claims. `context` is the question it answers; files and commands shown there count too.
    public func claims(in text: String, context: String = "") -> [MergeClaim] {
        allClaims(in: text, context: context, earlier: MergeScene())
    }

    /// Whether the text is about merging compose files: it shows two compose files, or it talks about compose and
    /// an override, `-f` or merging. Helm values and Kustomize patches are not.
    public static func isAboutMerging(_ text: String) -> Bool {
        let folded = text.folded
        if Words.containsAny(folded, ["helm", "kustomize", "kustomization", "values.yaml", "chart.yaml"]) {
            return false
        }
        var scene = MergeScene()
        remember(text, into: &scene)
        if scene.files.count >= 2 { return true }
        let names = ComposeFile.names(in: folded)
        if names.contains(where: { ComposeFile.role($0) != .base }) { return true }
        let compose = Words.containsAny(folded, ["docker compose", "docker-compose", "compose file", "compose files"])
            || !names.isEmpty
        return compose && Words.containsAny(folded, ["override", "-f", "merge", "merges", "merged", "merging",
                                                     "multiple compose files", "several compose files", "later file",
                                                     "last file", "first file", "base file", "later files",
                                                     "earlier file"])
    }

    /// Each sentence is judged against the files the latest `docker compose` command before it reads (its own command
    /// first); before any command, against the one the answer runs, if it runs only one.
    func allClaims(in text: String, context: String, earlier: MergeScene) -> [MergeClaim] {
        var scene = earlier
        Self.remember(context, into: &scene)
        let before = scene.selection
        Self.remember(text, into: &scene)
        let about = Self.isAboutMerging(text) || Self.isAboutMerging(context)
        let all = Commands.selections(in: text)
        var current = all.isEmpty || Commands.combined(all) == .unclear ? before : Commands.combined(all)
        scene.selection = current
        let first = scene
        var claims: [MergeClaim] = []
        for block in AnswerBlocks.split(text) {
            guard block.kind == .prose else {
                if let last = Commands.selections(in: block.lines.joined(separator: "\n")).last { current = last }
                continue
            }
            for sentence in Sentences.split(block.lines) {
                let own = Commands.selections(in: sentence).last
                var local = scene
                local.selection = own ?? current
                if let own, !Words.containsAny(Clauses.plain(sentence), EffectReader.hypothetical) { current = own }
                claims += self.claims(in: sentence, scene: local, about: about)
            }
        }
        if checksLines { claims += Self.lines(first) }
        return claims
    }

    func claims(in sentence: String, scene: MergeScene, about: Bool) -> [MergeClaim] {
        var claims: [MergeClaim] = []
        if about {
            for clause in Clauses.split(sentence) {
                claims += StatementReader.statements(in: clause).map { statement, holds in
                    MergeClaim(subject: .statement(statement, holds: holds), sentence: sentence, scene: scene)
                }
            }
        }
        return claims + EffectReader(scene: scene).claims(in: sentence).map {
            MergeClaim(subject: $0, sentence: sentence, scene: scene)
        }
    }

    /// A later applied file's `key: []` under a service whose earlier files give that key items.
    static func lines(_ scene: MergeScene) -> [MergeClaim] {
        guard case let .success(files) = scene.applied(), files.count >= 2 else { return [] }
        var claims: [MergeClaim] = []
        for (index, file) in files.enumerated().dropFirst() {
            guard let services = file.node?["services"]?.entries, let name = file.name else { continue }
            for service in services {
                for entry in service.value.entries ?? [] where entry.value == .list([]) {
                    guard !MergeEngine.replaced.contains(entry.key) else { continue }
                    let earlier = files[..<index].contains { earlier in
                        !(earlier.node?["services"]?[service.key]?[entry.key]?.items ?? []).isEmpty
                    }
                    guard earlier else { continue }
                    claims.append(MergeClaim(subject: .emptyList(service: service.key, key: entry.key, file: name),
                                             sentence: "\(entry.key): [] in \(name)", scene: scene))
                }
            }
        }
        return claims
    }

    /// Adds the text's compose files and `docker compose` commands to the scene.
    static func remember(_ text: String, into scene: inout MergeScene) {
        let blocks = AnswerBlocks.split(text)
        var selections: [MergeScene.Selection] = []
        var lastProse: [String] = []
        for block in blocks {
            switch block.kind {
            case .prose:
                lastProse = block.lines
                selections += Commands.selections(in: block.lines.joined(separator: "\n"))
            case let .code(tag, info):
                let named = name(info: info, lines: block.lines, before: lastProse)
                if let file = ComposeFile.read(block.lines, name: named),
                   ["yaml", "yml", "", "docker-compose", "compose"].contains(tag) || file.name != nil {
                    scene.add(file)
                } else {
                    selections += Commands.selections(in: block.lines.joined(separator: "\n"))
                }
                lastProse = []
            }
        }
        if text.contains("COMPOSE_FILE") { selections.append(.unclear) }
        if !selections.isEmpty { scene.selection = Commands.combined(selections) }
    }

    /// A code block's file name: from its info string, its first comment line, or the line just before it.
    static func name(info: String, lines: [String], before: [String]) -> String? {
        if let name = ComposeFile.names(in: info).first { return name }
        if let first = lines.first(where: { !$0.trimmed.isEmpty })?.trimmed, first.hasPrefix("#"),
           let name = ComposeFile.names(in: first).first {
            return name
        }
        guard let line = before.last(where: { !$0.trimmed.isEmpty }) else { return nil }
        let names = ComposeFile.names(in: line)
        return names.count == 1 ? names.first : nil
    }
}
