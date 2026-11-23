/// Judges claims with compose's merge rules. A stated result that does not match the merged files is wrong only when
/// one of the known misreadings gives exactly what the answer says; any other mismatch is unchecked.
struct MergeEvaluator {
    let policy: MergePolicy

    /// The slips tried for a stated result, in order.
    static let tried: [MergeFinding.Slip] = [.listReplaced, .emptyListClears, .mappingReplaced, .commandAppended,
                                             .earlierFileWins, .overrideNotLoaded, .overrideLoadedWithFile,
                                             .extraFileAutoLoaded]

    /// Words that tell two slips apart when both give what the answer says.
    static let cues: [MergeFinding.Slip: [String]] = [
        .overrideNotLoaded: ["only", "ignores", "ignored", "not loaded", "not read", "skips", "skipped", "alone"],
        .earlierFileWins: ["first", "precedence", "wins", "priority", "earlier"]
    ]

    enum Check: Equatable {
        case holds
        /// What the merged files give instead, as one sentence.
        case fails(String)
        case unknown(String)
    }

    func judge(_ claim: MergeClaim) -> MergeFinding {
        switch claim.subject {
        case let .statement(statement, holds):
            return holds ? MergeFinding(claim: claim, outcome: .exact)
                : MergeFinding(claim: claim, outcome: .wrong(statement.slip), actual: Wording.rule(statement.slip))
        case let .emptyList(service, key, file):
            return MergeFinding(claim: claim, outcome: .wrong(.emptyListClears),
                                actual: Wording.emptyList(service: service, key: key, file: file))
        default:
            return effect(claim)
        }
    }

    func effect(_ claim: MergeClaim) -> MergeFinding {
        let files: [ComposeFile]
        switch claim.scene.applied() {
        case let .success(chosen): files = chosen
        case let .failure(unknown): return MergeFinding(claim: claim, outcome: .unchecked(unknown.reason))
        }
        let project = Self.project(files, MergeEngine())
        switch Self.check(claim.subject, project) {
        case let .unknown(reason):
            return MergeFinding(claim: claim, outcome: .unchecked(reason))
        case .holds:
            if policy.reportsCaveats, Self.dependsOnOverrideTag(claim.subject, files) {
                return MergeFinding(claim: claim, outcome: .caveat(.overrideTagNeedsRecentCompose),
                                    actual: Wording.overrideTag)
            }
            return MergeFinding(claim: claim, outcome: .exact)
        case let .fails(actual):
            let fitting = Self.tried.filter { slip in
                guard case let .success(variant)? = claim.scene.applied(slip) else { return false }
                return Self.check(claim.subject, Self.project(variant, MergeEngine(slip: slip))) == .holds
            }
            let text = claim.sentence.folded
            if let slip = fitting.first(where: { Words.containsAny(text, Self.cues[$0] ?? []) }) ?? fitting.first {
                return MergeFinding(claim: claim, outcome: .wrong(slip), actual: actual + " " + Wording.rule(slip))
            }
            return MergeFinding(claim: claim, outcome: .unchecked(
                "the merged files give something else (" + String(actual.dropLast())
                    + "), and no known misreading of the merge gives what the answer says"))
        }
    }

    static func project(_ files: [ComposeFile], _ engine: MergeEngine) -> MergedProject {
        MergedProject(engine.merge(files.compactMap(\.node)))
    }

    static func check(_ subject: MergeClaim.Subject, _ project: MergedProject) -> Check {
        let name: String
        let judge: (MergedService) -> Check
        switch subject {
        case let .image(service, image): (name, judge) = (service, { check(image: image, $0) })
        case let .command(service, command): (name, judge) = (service, { check(command: command, $0) })
        case let .ports(service, claim): (name, judge) = (service, { check(ports: claim, $0) })
        case let .variable(service, variable, claim): (name, judge) = (service, { check(variable, claim, $0) })
        default: return .unknown("not a stated result")
        }
        guard let service = project.services[name] else { return .unknown("no service `\(name)` is left") }
        return judge(service)
    }

    static func check(image: String, _ service: MergedService) -> Check {
        guard let actual = service.image, !actual.contains("$") else {
            return .unknown("`\(service.name)`'s image is not set in the files, or uses a variable")
        }
        return actual == image ? .holds : .fails("With these files, `\(service.name)` runs `\(actual)`.")
    }

    static func check(command: String, _ service: MergedService) -> Check {
        guard let actual = service.command, !actual.joined().contains("$") else {
            return .unknown("`\(service.name)`'s command comes from its image, or uses a variable")
        }
        return ShellWords.split(command) == actual ? .holds
            : .fails("With these files, `\(service.name)` runs `\(actual.joined(separator: " "))`.")
    }

    static func check(ports claim: MergeClaim.PortClaim, _ service: MergedService) -> Check {
        guard let published = service.published else {
            return .unknown("`\(service.name)` has a port this kit does not read")
        }
        return claim.holds(published) ? .holds
            : .fails("With these files, `\(service.name)` publishes " + Wording.list(published) + ".")
    }

    static func check(_ name: String, _ claim: MergeClaim.VariableClaim, _ service: MergedService) -> Check {
        guard let entry = service.environment[name] else {
            if service.hasEnvFile { return .unknown("`\(name)` may come from an `env_file:` the answer does not show") }
            return claim == .unset ? .holds : .fails("With these files, `\(name)` is not set in `\(service.name)`.")
        }
        guard let value = entry, !value.contains("$") else {
            return .unknown("`\(name)`'s value comes from the shell, or uses a variable")
        }
        let actual = Check.fails("With these files, `\(name)` is `\(value)` in `\(service.name)`.")
        switch claim {
        case let .value(stated): return stated == value ? .holds : actual
        case .kept: return .holds
        case .unset: return actual
        }
    }

    /// Whether a later file tags the service, or the attribute the claim is about, `!override`.
    static func dependsOnOverrideTag(_ subject: MergeClaim.Subject, _ files: [ComposeFile]) -> Bool {
        let (name, key): (String, String)
        switch subject {
        case let .image(service, _): (name, key) = (service, "image")
        case let .command(service, _): (name, key) = (service, "command")
        case let .ports(service, _): (name, key) = (service, "ports")
        case let .variable(service, _, _): (name, key) = (service, "environment")
        default: return false
        }
        return files.dropFirst().contains { file in
            guard let service = file.node?["services"]?[name] else { return false }
            if case .replace = service { return true }
            if case .replace? = service[key] { return true }
            return false
        }
    }
}
