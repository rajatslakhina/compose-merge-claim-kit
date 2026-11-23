import Foundation

/// A run of an answer's lines: prose, or the inside of one fenced code block.
struct AnswerBlock: Equatable {
    enum Kind: Equatable {
        case prose
        /// A fenced block, its info string's first word lowercased (`yaml`, `env`, or empty), and the whole info
        /// string (```` ```ini title=".env" ````).
        case code(String, info: String)
    }

    let kind: Kind
    let lines: [String]
}

enum AnswerBlocks {
    static func split(_ text: String) -> [AnswerBlock] {
        var blocks: [AnswerBlock] = []
        var prose: [String] = []
        var code: [String] = []
        var fence: String?
        var info = ""
        for line in text.components(separatedBy: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if let open = fence {
                if trimmed.hasPrefix(open), trimmed.trimmingCharacters(in: CharacterSet(charactersIn: "`~")).isEmpty {
                    blocks.append(AnswerBlock(kind: .code(tag(info), info: info), lines: code))
                    code = []
                    fence = nil
                } else {
                    code.append(line)
                }
            } else if let marker = ["```", "~~~"].first(where: { trimmed.hasPrefix($0) }) {
                if !prose.isEmpty { blocks.append(AnswerBlock(kind: .prose, lines: prose)) }
                prose = []
                fence = marker
                info = String(trimmed.drop { "`~".contains($0) }).lowercased()
            } else {
                prose.append(line)
            }
        }
        if fence != nil { blocks.append(AnswerBlock(kind: .code(tag(info), info: info), lines: code)) }
        if !prose.isEmpty { blocks.append(AnswerBlock(kind: .prose, lines: prose)) }
        return blocks
    }

    /// The info string's first word, before any space, colon or brace (```` ```yaml:compose.yaml ````).
    static func tag(_ info: String) -> String {
        String(info.prefix { !" :{".contains($0) })
    }
}
