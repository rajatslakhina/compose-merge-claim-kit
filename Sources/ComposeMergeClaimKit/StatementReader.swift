/// Reads the merge rules an answer states, true or not: "ports in the override are appended", "an empty list removes
/// the ports", "the first file wins". A clause makes a statement only when its topic comes before its verb and it
/// has at most one negation, which flips what it says.
enum StatementReader {
    static let appendVerbs = ["appended", "append", "appends", "added", "adds", "add", "combined", "combines",
                              "concatenated", "merged", "merge", "merges", "extended", "extends", "accumulate"]
    static let replaceVerbs = ["replace", "replaces", "replaced", "overwrite", "overwrites", "overwritten",
                               "override", "overrides", "overridden", "discard", "discards", "discarded", "wipe",
                               "wipes", "supersede", "supersedes"]
    static let clearVerbs = ["remove", "removes", "removed", "clear", "clears", "cleared", "drop", "drops", "delete",
                             "deletes", "wipe", "wipes", "unset", "unsets", "disable", "disables", "get rid of"]
    static let winVerbs = ["wins", "win", "takes precedence", "take precedence", "has priority", "have priority",
                           "has the final say", "overrides", "override", "beats"]
    static let loadVerbs = ["loaded", "read", "applied", "picked up", "merged", "included", "used"]

    static func statements(in clause: String) -> [(MergeClaim.Statement, Bool)] {
        let text = Clauses.plain(clause)
        let negations = Clauses.negationCount(text)
        guard negations <= 1, !text.hasSuffix("?") else { return [] }
        let flip = negations == 1
        var found: [(MergeClaim.Statement, Bool)] = []
        let stripped = nouns(text)
        // These place their own negation: only one between the topic and the verb counts.
        let placed: [(MergeClaim.Statement, (String, String) -> Bool?)] = [
            (.listsAppend, lists), (.mappingsMergeByKey, mappings), (.commandReplaced, commands)
        ]
        let whole: [(MergeClaim.Statement, (String, String) -> Bool?)] = [
            (.emptyListKeeps, emptyList), (.laterFileWins, precedence), (.overrideReadByDefault, autoLoad),
            (.fileListExcludesOverride, fileList), (.otherFilesNeedFile, otherFiles),
            (.pathsFromProjectDirectory, paths)
        ]
        for (statement, read) in placed {
            if let says = read(text, stripped) { found.append((statement, says)) }
        }
        for (statement, read) in whole {
            if let says = read(text, stripped) { found.append((statement, says != flip)) }
        }
        return found
    }

    /// The text with the nouns that look like verbs taken out: "the override file", compose file names.
    static func nouns(_ text: String) -> String {
        var result = text
        for name in ComposeFile.names(in: text) { result = result.replacingOccurrences(of: name, with: "file") }
        for phrase in ["override files", "override file", "overrides file", "the override", "an override",
                       "this override", "that override", "your override", "!override", "!reset"] {
            result = result.replacingOccurrences(of: phrase, with: "file")
        }
        return result
    }

    static func mentionsFiles(_ text: String) -> Bool {
        Words.containsAny(text, ["override", "later file", "second file", "last file", "-f", "both files",
                                 "multiple compose files", "several compose files", "base file", "later files",
                                 "subsequent file", "subsequent files", "additional file", "each file", "merge",
                                 "merged", "merges", "merging"])
    }

    /// Whether the clause's first verb after its topic is one of `yes` (true) or `no` (false).
    static func verb(after topics: [String], in text: String, yes: [String], no: [String],
                     negates: Bool = true) -> Bool? {
        guard let topic = Clauses.position(text, topics) else { return nil }
        let rest = String(text[topic...])
        let first = Clauses.position(rest, yes)
        let second = Clauses.position(rest, no)
        let says: Bool
        let verb: String.Index
        switch (first, second) {
        case let (yes?, no?): (says, verb) = (yes < no, min(yes, no))
        case let (yes?, nil): (says, verb) = (true, yes)
        case let (nil, no?): (says, verb) = (false, no)
        default: return nil
        }
        return negates && Clauses.negationCount(String(rest[..<verb])) == 1 ? !says : says
    }

    static func lists(_ text: String, _ stripped: String) -> Bool? {
        guard mentionsFiles(text), !text.contains("!override"), !text.contains("!reset"),
              !Words.containsAny(text, ["same target", "same mount", "same path", "same container path", "same key",
                                        "same port", "same mapping", "same entry", "matching", "same item"]),
              !text.contains("[]"), !Words.containsAny(text, ["empty list", "empty array"]) else { return nil }
        let topics = ["ports", "volumes", "lists", "sequences", "arrays", "expose", "dns", "port mappings"]
        // "override files replace lists": the verb before its object.
        for verb in ["replace", "replaces", "overwrite", "overwrites", "wipe out", "wipes out", "discard", "discards"] {
            for object in topics where Words.containsAny(stripped, ["\(verb) \(object)", "\(verb) the \(object)",
                                                                    "\(verb) the base \(object)",
                                                                    "\(verb) any \(object)"]) {
                return Clauses.negationCount(stripped) == 1
            }
        }
        return verb(after: topics, in: stripped, yes: appendVerbs, no: replaceVerbs)
    }

    static func mappings(_ text: String, _ stripped: String) -> Bool? {
        guard mentionsFiles(text) else { return nil }
        let topics = ["environment", "environment variables", "env vars", "labels"]
        let merges = appendVerbs + ["kept", "preserved"]
        guard let raw = verb(after: topics, in: stripped, yes: merges, no: replaceVerbs, negates: false),
              let says = verb(after: topics, in: stripped, yes: merges, no: replaceVerbs) else { return nil }
        // "is merged", "is not merged", "does not replace the block": clear either way.
        if raw || says { return says }
        let whole = Words.containsAny(text, ["entire", "whole", "completely", "all of", "block", "section",
                                             "all the", "list", "mapping"])
        return whole && !Words.containsAny(text, ["same key", "same name", "same variable", "matching"]) ? false : nil
    }

    static func commands(_ text: String, _ stripped: String) -> Bool? {
        guard mentionsFiles(text) else { return nil }
        return verb(after: ["command", "entrypoint", "healthcheck test", "test command"], in: stripped,
                    yes: replaceVerbs, no: appendVerbs)
    }

    static func emptyList(_ text: String, _: String) -> Bool? {
        guard text.contains("[]") || Words.containsAny(text, ["empty list", "empty array", "empty sequence"]),
              !text.contains("!reset"), Words.containsAny(text, ["ports", "volumes", "list", "override", "base",
                                                                 "expose", "dns", "environment"]) else { return nil }
        if Words.containsAny(text, clearVerbs) { return false }
        if Words.containsAny(text, ["keeps", "kept", "adds nothing", "has no effect", "no effect", "is ignored",
                                    "still", "stay", "stays", "remain", "remains"]) {
            return true
        }
        return nil
    }

    static func precedence(_ text: String, _: String) -> Bool? {
        let earlier = ["the first file", "the base file", "the earlier file", "earlier files", "the first -f",
                       "the first one", "the original file", "the main file"]
        let later = ["the last file", "the later file", "later files", "the second file", "the last -f",
                     "subsequent files", "each later file", "the override file", "the last one", "later -f"]
        guard let subject = Clauses.position(text, earlier + later),
              let phrase = (earlier + later).first(where: { text[subject...].hasPrefix($0) }) else { return nil }
        // "the override file" later in the clause is a noun, not the verb "override".
        let rest = nouns(String(text[text.index(subject, offsetBy: phrase.count)...]))
        guard Words.containsAny(rest, winVerbs) else { return nil }
        return later.contains(phrase)
    }

    /// Ways to say the override needs a `-f` to be read.
    static let needsFile = ["must pass", "have to pass", "need to pass", "needs to be passed", "must be passed",
                            "you must specify", "you have to specify", "unless you pass", "only if you pass",
                            "only when you pass", "unless you add", "unless you specify", "unless it is passed",
                            "unless you include", "unless you name"]

    static func autoLoad(_ text: String, _: String) -> Bool? {
        guard Words.containsAny(text, ["override"]),
              !Words.containsAny(text, ["-f", "--file", "explicitly", "specify", "specified", "name the files",
                                        "COMPOSE_FILE".folded]) else {
            if Words.containsAny(text, needsFile),
               Words.containsAny(text, ["-f", "--file"]), Words.contains(text, "override") {
                return false
            }
            return nil
        }
        guard Words.containsAny(text, ["automatically", "by default", "on its own", "without being asked"]),
              Words.containsAny(text, loadVerbs + ["picks up", "reads", "loads", "applies", "merges"]) else {
            return nil
        }
        return true
    }

    static func fileList(_ text: String, _: String) -> Bool? {
        guard Words.containsAny(text, ["-f", "--file"]), Words.contains(text, "override"),
              Words.containsAny(text, loadVerbs + ["reads", "loads", "applies", "merges", "picks up"]) else {
            return nil
        }
        // "only the files named" holds with or without "never the override"; the caller flips a negation.
        if Words.containsAny(text, ["only", "just"]) { return Clauses.negationCount(text) == 0 }
        if Words.containsAny(text, ["still", "also", "even", "always"]) { return false }
        return Clauses.negationCount(text) == 1 ? false : nil
    }

    static func otherFiles(_ text: String, _: String) -> Bool? {
        let others = ComposeFile.names(in: text).filter { ComposeFile.role($0) == .other }
        guard !others.isEmpty else { return nil }
        if Words.containsAny(text, ["-f", "--file"]),
           Words.containsAny(text, ["only", "must", "need", "needs", "have to", "has to", "requires"]) {
            return true
        }
        guard Words.containsAny(text, ["automatically", "by default", "on its own"]),
              Words.containsAny(text, loadVerbs + ["picks up", "reads", "loads", "applies"]) else { return nil }
        return false
    }

    static func paths(_ text: String, _: String) -> Bool? {
        guard Words.containsAny(text, ["relative"]), Words.containsAny(text, ["path", "paths"]),
              let relative = text.range(of: "relative to") else { return nil }
        let target = String(text[relative.upperBound...])
        if Words.containsAny(target, ["the first file", "the base file", "the project directory", "the first compose",
                                      "the main compose", "the primary", "the first -f", "the project's"]) {
            return true
        }
        if Words.containsAny(target, ["the override file", "the override", "that file", "the file that",
                                      "its own directory",
                                      "the override's", "each file", "the file it", "the file they", "where it lives",
                                      "the file's own", "its own location", "the location of the override"]) {
            return false
        }
        return nil
    }
}
