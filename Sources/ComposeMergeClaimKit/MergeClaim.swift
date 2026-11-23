/// Something an answer says about how compose merges files, or about the project the merged files make.
public struct MergeClaim: Sendable, Hashable {
    public enum Subject: Sendable, Hashable {
        /// A rule of compose's merge, stated as holding (`holds: true`) or as its opposite.
        case statement(Statement, holds: Bool)
        /// `web` runs the image `myapp:dev`.
        case image(service: String, image: String)
        /// `web` runs `npm run dev`.
        case command(service: String, command: String)
        /// `web` publishes (or no longer publishes) host ports.
        case ports(service: String, PortClaim)
        /// `DEBUG` is `1` in `web`, or is gone, or is still set.
        case variable(service: String, name: String, VariableClaim)
        /// A later file's `key: []` under a service an earlier file gives items for: compose keeps those items.
        case emptyList(service: String, key: String, file: String)
    }

    /// A rule of compose's merge. Each one is the opposite of a slip.
    public enum Statement: String, Sendable, Hashable, CaseIterable {
        /// A later file's `ports`, `volumes`, `expose`, `dns` (and other lists) are added to the earlier ones.
        case listsAppend
        /// A later file's `environment` and `labels` are merged key by key.
        case mappingsMergeByKey
        /// A later file's `command`, `entrypoint` and healthcheck `test` replace the earlier ones.
        case commandReplaced
        /// `key: []` in a later file keeps the earlier items; `!reset []` clears them.
        case emptyListKeeps
        /// Where files disagree, the later file wins.
        case laterFileWins
        /// `compose.override.yaml` is read automatically when no `-f` is given.
        case overrideReadByDefault
        /// With `-f`, only the files named are read: the override is not.
        case fileListExcludesOverride
        /// Any other file (`docker-compose.prod.yml`) is read only when a `-f` names it.
        case otherFilesNeedFile
        /// Relative paths in every file are resolved from the first file's directory.
        case pathsFromProjectDirectory

        /// The mistake the opposite of this rule is.
        public var slip: MergeFinding.Slip {
            switch self {
            case .listsAppend: .listReplaced
            case .mappingsMergeByKey: .mappingReplaced
            case .commandReplaced: .commandAppended
            case .emptyListKeeps: .emptyListClears
            case .laterFileWins: .earlierFileWins
            case .overrideReadByDefault: .overrideNotLoaded
            case .fileListExcludesOverride: .overrideLoadedWithFile
            case .otherFilesNeedFile: .extraFileAutoLoaded
            case .pathsFromProjectDirectory: .pathsRelativeToOverride
            }
        }
    }

    /// Host ports said to be published, said not to be, and whether the answer says these are the only ones.
    public struct PortClaim: Sendable, Hashable {
        public var present: Set<Int>
        public var absent: Set<Int>
        public var exact: Bool

        public init(present: Set<Int> = [], absent: Set<Int> = [], exact: Bool = false) {
            self.present = present
            self.absent = absent
            self.exact = exact
        }

        func holds(_ published: Set<Int>) -> Bool {
            present.isSubset(of: published) && absent.isDisjoint(with: published) && (!exact || published == present)
        }
    }

    public enum VariableClaim: Sendable, Hashable {
        case value(String)
        /// Removed, no longer set.
        case unset
        /// Still set.
        case kept
    }

    public let subject: Subject
    /// The sentence (or file) the claim was read from.
    public let sentence: String
    /// The files and the command the claim is judged against.
    public let scene: MergeScene

    public init(subject: Subject, sentence: String, scene: MergeScene = MergeScene()) {
        self.subject = subject
        self.sentence = sentence
        self.scene = scene
    }

    /// Whether the answer states the claim (rather than its compose file showing it).
    public var isExplicit: Bool {
        if case .emptyList = subject { return false }
        return true
    }

    /// The claim in a few words, for a log or a demo.
    public var summary: String {
        switch subject {
        case let .statement(statement, holds): (holds ? "rule: " : "rule broken: ") + statement.rawValue
        case let .image(service, image): "`\(service)` runs `\(image)`"
        case let .command(service, command): "`\(service)` runs `\(command)`"
        case let .ports(service, claim):
            "`\(service)` publishes" + (claim.exact ? " only" : "") + " " + Wording.list(claim.present)
                + (claim.absent.isEmpty ? "" : ", not " + Wording.list(claim.absent))
        case let .variable(service, name, claim):
            switch claim {
            case let .value(value): "`\(name)` is `\(value)` in `\(service)`"
            case .unset: "`\(name)` is not set in `\(service)`"
            case .kept: "`\(name)` is still set in `\(service)`"
            }
        case let .emptyList(service, key, file): "`\(key): []` in `\(file)` clears `\(service)`'s `\(key)`"
        }
    }

    /// What two claims share when they say the same thing.
    var key: String {
        switch subject {
        case let .statement(statement, holds): "statement|\(statement.rawValue)|\(holds)"
        case let .image(service, image): "image|\(service)|\(image)"
        case let .command(service, command): "command|\(service)|\(command)"
        case let .ports(service, claim):
            "ports|\(service)|\(claim.present.sorted())|\(claim.absent.sorted())|\(claim.exact)"
        case let .variable(service, name, claim): "variable|\(service)|\(name)|\(claim)"
        case let .emptyList(service, key, _): "empty|\(service)|\(key)"
        }
    }
}
