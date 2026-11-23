/// The words a finding uses.
enum Wording {
    static func rule(_ slip: MergeFinding.Slip) -> String {
        switch slip {
        case .listReplaced:
            "A later file's lists are appended to the earlier ones (`ports` and `volumes` merge items with the same "
                + "key); tag the list `!override` to replace it."
        case .mappingReplaced:
            "A later file's `environment` and `labels` are merged key by key: the earlier keys stay unless the later "
                + "file sets them or `!reset`s them."
        case .commandAppended:
            "A later file's `command`, `entrypoint` and healthcheck `test` replace the earlier ones; they are not "
                + "appended."
        case .emptyListClears:
            "An empty list in a later file adds nothing, so the earlier items stay; write `!reset []` to clear them."
        case .earlierFileWins:
            "Where files disagree, the later file wins: compose applies them in order."
        case .overrideNotLoaded:
            "Without `-f`, compose reads `compose.override.yaml` (or `docker-compose.override.yml`) after the base "
                + "file automatically."
        case .overrideLoadedWithFile:
            "With `-f`, compose reads only the files named: the override file is read only when a `-f` names it."
        case .extraFileAutoLoaded:
            "By default compose reads only the base file and its override; any other file needs its own `-f`."
        case .pathsRelativeToOverride:
            "Relative paths in every file are resolved from the first file's directory (the project directory), "
                + "not from the file that writes them."
        }
    }

    static func emptyList(service: String, key: String, file: String) -> String {
        "`\(key): []` in `\(file)` adds nothing, so `\(service)` keeps the earlier `\(key)`; write "
            + "`\(key): !reset []` to clear them."
    }

    static let overrideTag = "This depends on `!override`, which needs Docker Compose 2.24.4 or later; older "
        + "versions refuse the file."

    static func list(_ ports: Set<Int>) -> String {
        let sorted = ports.sorted().map { "`\($0)`" }
        guard let last = sorted.last else { return "no host ports" }
        let ports = sorted.count == 1 ? "port" : "ports"
        return sorted.count == 1 ? "\(ports) \(last)" : "\(ports) " + sorted.dropLast().joined(separator: ", ")
            + " and " + last
    }
}

extension MergeFinding {
    /// One sentence for a person reading the answer.
    public var explanation: String {
        switch outcome {
        case .exact: "This holds."
        case let .unchecked(reason): "Not checked: \(reason)."
        case .caveat, .wrong: detail
        }
    }
}
