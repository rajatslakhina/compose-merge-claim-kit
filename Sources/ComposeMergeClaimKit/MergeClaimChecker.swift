/// Reads what an answer says about merging compose files and checks every claim with compose's merge rules: the one
/// call most callers need.
public struct MergeClaimChecker: Sendable {
    public let policy: MergePolicy
    public let reader: MergeClaimReader

    public init(policy: MergePolicy = .standard) {
        self.policy = policy
        reader = MergeClaimReader(checksLines: policy.checksLines)
    }

    public func claims(in text: String, context: String = "") -> [MergeClaim] {
        reader.claims(in: text, context: context)
    }

    public func judge(_ claim: MergeClaim) -> MergeFinding {
        MergeEvaluator(policy: policy).judge(claim)
    }

    /// Merges two or more compose files the way `docker compose -f a -f b config` does, as far as this kit reads
    /// them, and returns each service; `nil` when a file is one this kit does not read.
    public func merged(_ sources: [String]) -> [MergedService]? {
        var nodes: [ComposeNode] = []
        for source in sources {
            guard let node = try? ComposeYAML.parse(source) else { return nil }
            nodes.append(node)
        }
        return MergedProject(MergeEngine().merge(nodes)).services.values.sorted { $0.name < $1.name }
    }

    /// Every claim's finding. A file line that merges as written makes no finding of its own.
    public func check(_ text: String, context: String = "") -> MergeReport {
        report(claims(in: text, context: context))
    }

    /// One mistake, one finding: a file line whose slip a stated claim already shows is left out, and so is a
    /// second finding with the same slip from the same sentence.
    func report(_ claims: [MergeClaim]) -> MergeReport {
        let findings = claims.map(judge)
        let stated = Set(findings.filter(\.claim.isExplicit).compactMap(\.slip))
        var seen: Set<String> = []
        return MergeReport(findings: findings.filter { finding in
            guard let slip = finding.slip else { return true }
            guard finding.claim.isExplicit else { return !stated.contains(slip) }
            return seen.insert(finding.claim.sentence + "|" + slip.rawValue).inserted
        })
    }
}

/// Checks a conversation's answers one after another and remembers the compose files shown, how compose was run and
/// what it flagged, so a later answer is read against them and a wrong claim stated again after a correction was
/// asked for is marked as repeated rather than new.
public actor MergeLedger {
    public struct Statistics: Sendable, Hashable {
        public var reviews = 0
        public var claims = 0
        public var flagged = 0
        public var repeated = 0
    }

    public nonisolated let checker: MergeClaimChecker
    public private(set) var statistics = Statistics()
    private var flaggedKeys: Set<String> = []
    private var scene = MergeScene()

    public init(checker: MergeClaimChecker = MergeClaimChecker()) {
        self.checker = checker
    }

    /// Checks one answer. `context` is the question it answers. A turn where neither talks about merging compose
    /// files makes no new claims; it keeps only those that repeat a claim flagged earlier in the conversation.
    public func review(_ text: String, context: String = "") -> MergeReport {
        let about = MergeClaimReader.isAboutMerging(text) || MergeClaimReader.isAboutMerging(context)
        let all = checker.reader.allClaims(in: text, context: context, earlier: scene)
        MergeClaimReader.remember(context, into: &scene)
        MergeClaimReader.remember(text, into: &scene)
        let considered = about ? all : all.filter { flaggedKeys.contains($0.key) }
        var findings = checker.report(considered).findings
        for index in findings.indices where findings[index].severity >= .caution {
            findings[index].isRepeated = flaggedKeys.contains(findings[index].key)
        }
        flaggedKeys.formUnion(considered.map(checker.judge).filter { $0.severity >= .caution }.map(\.key))
        let report = MergeReport(findings: findings)
        statistics.reviews += 1
        statistics.claims += findings.count
        statistics.flagged += report.flagged.count
        statistics.repeated += report.repeatedCount
        return report
    }

    /// Starts a new conversation: nothing flagged so far counts as a repeat, and no compose file is remembered.
    public func forget() {
        flaggedKeys.removeAll()
        scene = MergeScene()
    }
}
