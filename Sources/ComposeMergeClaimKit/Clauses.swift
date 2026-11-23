/// Cuts a sentence where it turns to another point (`;`, `, but`, `, while`, `, whereas`, `, and`), so a contrast
/// ("`command` is replaced, while `ports` are appended") reads as two claims.
enum Clauses {
    static let joints = ["; ", ", but ", ", while ", ", whereas ", ", and ", " but ", " whereas ", ", so ", ", since ",
                         " because ", ", which ", " - ", " \u{2014} "]

    static func split(_ sentence: String) -> [String] {
        var clauses = [sentence]
        for joint in joints {
            clauses = clauses.flatMap { clause in
                clause.components(separatedBy: joint).filter { !$0.trimmed.isEmpty }
            }
        }
        return clauses
    }

    /// The clause without its inline-code marks and with its words folded.
    static func plain(_ clause: String) -> String {
        clause.replacingOccurrences(of: "`", with: "").folded
    }

    static func negationCount(_ text: String) -> Int {
        var count = 0
        for word in ["not", "never", "no longer", "neither", "nor", "cannot"] where Words.contains(text, word) {
            count += 1
        }
        count += text.components(separatedBy: "n't").count - 1
        return count
    }

    /// The position of the first of the phrases in the text, as words.
    static func position(_ text: String, _ phrases: [String]) -> String.Index? {
        var best: String.Index?
        for phrase in phrases {
            var start = text.startIndex
            while let range = text.range(of: phrase, range: start..<text.endIndex) {
                if Words.bounded(text, range, phrase) {
                    if best.map({ range.lowerBound < $0 }) ?? true { best = range.lowerBound }
                    break
                }
                start = text.index(after: range.lowerBound)
            }
        }
        return best
    }
}
