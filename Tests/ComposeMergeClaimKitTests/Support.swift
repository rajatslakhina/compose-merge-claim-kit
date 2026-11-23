@testable import ComposeMergeClaimKit

let fence = "```"

func yaml(_ name: String?, _ lines: String...) -> String {
    (name.map { "`\($0)`:\n" } ?? "") + "\(fence)yaml\n" + lines.joined(separator: "\n") + "\n\(fence)\n"
}

func node(_ source: String) -> ComposeNode {
    (try? ComposeYAML.parse(source)) ?? .null
}

func merged(_ sources: [String], slip: MergeFinding.Slip? = nil) -> ComposeNode {
    MergeEngine(slip: slip).merge(sources.map(node))
}

/// A merged service in the canonical line `Scripts/parity.py` writes for compose's own output.
func canonical(_ service: ComposeNode) -> String {
    func json(_ items: [ComposeNode]) -> String {
        "[" + items.compactMap(\.text).map { "\"" + $0.replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"") + "\"" }.joined(separator: ",") + "]"
    }
    var parts = ["image=" + (service["image"]?.text ?? "")]
    for key in ["command", "entrypoint"] {
        if let items = service[key]?.items { parts.append(key + "=" + json(items)) }
    }
    let ports = (service["ports"]?.items ?? []).compactMap(PortBinding.read).map {
        "\($0.hostIP ?? "")|\($0.published.map(String.init) ?? "")|\($0.target)|\($0.proto)"
    }
    parts.append("ports=" + ports.sorted().joined(separator: ","))
    let env = (service["environment"]?.entries ?? []).map { entry in
        entry.value.text.map { "\(entry.key)=\($0)" } ?? entry.key
    }
    parts.append("env=" + env.sorted().joined(separator: ","))
    let volumes = (service["volumes"]?.items ?? []).compactMap(Mount.read).map { "\($0.target)<-\($0.source ?? "")" }
    parts.append("volumes=" + volumes.sorted().joined(separator: ","))
    parts.append("expose=" + (service["expose"]?.items ?? []).compactMap(\.text).joined(separator: ","))
    parts.append("dns=" + (service["dns"]?.items ?? []).compactMap(\.text).joined(separator: ","))
    let labels = (service["labels"]?.entries ?? []).map { "\($0.key)=\($0.value.text ?? "")" }
    parts.append("labels=" + labels.sorted().joined(separator: ","))
    parts.append("depends=" + (service["depends_on"]?.entries ?? []).map(\.key).sorted().joined(separator: ","))
    if let healthcheck = service["healthcheck"] { parts.append("test=" + json(healthcheck["test"]?.items ?? [])) }
    return parts.joined(separator: ";")
}

let baseFile = yaml(
    "docker-compose.yml",
    "services:",
    "  web:",
    "    image: myapp:1.0",
    "    command: npm start",
    "    ports:",
    "      - \"8080:80\"",
    "    environment:",
    "      DEBUG: \"0\"",
    "      LOG_LEVEL: info",
    "  db:",
    "    image: postgres:16"
)

let overrideFile = yaml(
    "docker-compose.override.yml",
    "services:",
    "  web:",
    "    image: myapp:dev",
    "    command: npm run dev",
    "    ports:",
    "      - \"8081:80\"",
    "    environment:",
    "      DEBUG: \"1\""
)

let pair = baseFile + overrideFile

func check(_ text: String, context: String = "", policy: MergePolicy = .standard) -> MergeReport {
    MergeClaimChecker(policy: policy).check(text, context: context)
}

func slips(_ report: MergeReport) -> [MergeFinding.Slip] {
    report.findings.compactMap(\.slip)
}
