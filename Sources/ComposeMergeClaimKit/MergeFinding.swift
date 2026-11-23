/// What a claim about merged compose files turned out to be once compose's merge rules were applied.
public struct MergeFinding: Sendable, Hashable {
    public enum Outcome: Sendable, Hashable {
        case exact
        /// Holds, with something a reader should know.
        case caveat(Caveat)
        case wrong(Slip?)
        /// Could not be checked, and why.
        case unchecked(String)
    }

    public enum Caveat: String, Sendable, Hashable, CaseIterable {
        /// The result depends on `!override`, which needs Docker Compose 2.24.4 or later.
        case overrideTagNeedsRecentCompose
    }

    /// A recognisable mistake about how compose merges files.
    public enum Slip: String, Sendable, Hashable, CaseIterable {
        /// A later file's list read as replacing the earlier one: compose appends it (`ports` and `volumes` merge
        /// items with the same key).
        case listReplaced
        /// A later file's `environment` or `labels` read as replacing the earlier one: compose merges them by key.
        case mappingReplaced
        /// A later file's `command` (or `entrypoint`, healthcheck `test`) read as added to the earlier one: it
        /// replaces it.
        case commandAppended
        /// `key: []` read as clearing the earlier items: an empty list adds nothing; `!reset []` clears.
        case emptyListClears
        /// The earlier file read as winning: the later file's value wins.
        case earlierFileWins
        /// The override file read as needing `-f`: without `-f`, compose reads it after the base file.
        case overrideNotLoaded
        /// The override file read as still applying with `-f`: compose then reads only the files named.
        case overrideLoadedWithFile
        /// A file such as `docker-compose.prod.yml` read as loaded by default: only a `-f` loads it.
        case extraFileAutoLoaded
        /// Relative paths in a later file read from that file's directory: compose resolves them from the first
        /// file's directory (the project directory).
        case pathsRelativeToOverride
    }

    public enum Severity: Int, Sendable, Hashable, Comparable {
        case holds
        case unchecked
        case caution
        case wrong

        public static func < (lhs: Severity, rhs: Severity) -> Bool {
            lhs.rawValue < rhs.rawValue
        }
    }

    public let claim: MergeClaim
    public let outcome: Outcome
    /// What compose actually does, in words, where the claim gets it wrong or needs a note.
    public var actual: String? {
        detail.isEmpty ? nil : detail
    }

    let detail: String
    /// Flagged in an earlier review of the same conversation (set by `MergeLedger`).
    public internal(set) var isRepeated = false

    init(claim: MergeClaim, outcome: Outcome, actual: String = "") {
        self.claim = claim
        self.outcome = outcome
        detail = actual
    }

    public var severity: Severity {
        switch outcome {
        case .exact: .holds
        case .unchecked: .unchecked
        case .caveat: .caution
        case .wrong: .wrong
        }
    }

    /// The mistake behind a wrong finding.
    public var slip: Slip? {
        if case let .wrong(slip) = outcome { return slip }
        return nil
    }

    var key: String {
        claim.key
    }
}

/// How strictly claims are judged.
public struct MergePolicy: Sendable, Hashable {
    /// Also report a later file's `key: []` that keeps an earlier file's items.
    public var checksLines: Bool
    /// Report claims that hold with a caveat as cautions; when `false` they count as holding.
    public var reportsCaveats: Bool

    public init(checksLines: Bool = true, reportsCaveats: Bool = true) {
        self.checksLines = checksLines
        self.reportsCaveats = reportsCaveats
    }

    public static let standard = MergePolicy()
    public static let lenient = MergePolicy(checksLines: false, reportsCaveats: false)
}
