import ComposeMergeClaimKit

let checker = MergeClaimChecker()
let base = file(
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
let override = file(
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
let both = base + override

print("ComposeMergeClaimKit demo: what an answer says about merged compose files, checked with compose's rules")

heading(1, "A correct answer about the merged result")
show(checker.check(both + "Run `docker compose up`. Compose merges the override into the base: `command` is "
    + "replaced, while `ports` are appended, so `web` publishes both `8080` and `8081` and runs `npm run dev`. "
    + "`LOG_LEVEL` stays `info` because environment variables are merged by key."))

heading(2, "A later file's ports read as replacing the base ones")
show(checker.check(both + "With both files, `web` publishes `8081` instead of `8080`."))

heading(3, "The environment block read as replaced whole")
show(checker.check(both + "With both files, `DEBUG` is `1` and `LOG_LEVEL` is gone."))

heading(4, "An empty list read as clearing (one mistake, one finding)")
let empty = base + file("docker-compose.override.yml", "services:", "  web:", "    ports: []")
show(checker.check(empty + "The empty list removes the published port, so `web` no longer publishes `8080`."))
show(checker.check(empty), label: "files alone")

heading(5, "The override read as still applying with -f")
show(checker.check(both + "`docker compose -f docker-compose.yml up` still uses `myapp:dev` for `web`."))

heading(6, "Rules stated without files")
show(checker.check("With docker compose, the first file takes precedence over the override. "
    + "`docker-compose.prod.yml` is picked up automatically. Relative paths in the override file are "
    + "resolved relative to the override file."))

heading(7, "A result that depends on !override")
let replaced = base + file("docker-compose.override.yml", "services:", "  web:", "    ports: !override",
                           "      - \"8443:443\"")
show(checker.check(replaced + "With both files, `web` publishes only `8443`."))

heading(8, "Other kinds of override stay quiet")
show(checker.check("In Helm, lists in a values override file replace the chart defaults. In CSS, later rules "
    + "override earlier ones."))

heading(9, "A conversation: the same mistake stated again")
let ledger = MergeLedger()
show(await ledger.review(both + "With both files, `web` publishes only `8081`."), label: "turn 1")
show(await ledger.review("As I said, with both files `web` publishes only `8081`."), label: "turn 2")
let stats = await ledger.statistics
print("  ledger: \(stats.reviews) reviews, \(stats.claims) claims, \(stats.flagged) flagged, "
    + "\(stats.repeated) repeated")

heading(10, "The merge itself, as docker compose config gives it")
if let services = checker.merged([
    "services:\n  web:\n    image: myapp:1.0\n    ports: [\"8080:80\"]\n    environment: [DEBUG=0, LOG_LEVEL=info]",
    "services:\n  web:\n    image: myapp:dev\n    ports: [\"8081:80\"]\n    environment: {DEBUG: \"1\"}"
]) {
    for service in services {
        let ports = (service.published ?? []).sorted().map(String.init).joined(separator: ", ")
        let environment = service.environment.keys.sorted().map { key in
            "\(key)=" + (service.environment[key].flatMap { $0 } ?? "")
        }
        print("  \(service.name): image \(service.image ?? "-"), ports \(ports), " + environment.joined(separator: " "))
    }
}

func file(_ name: String, _ lines: String...) -> String {
    "`\(name)`:\n```yaml\n" + lines.joined(separator: "\n") + "\n```\n"
}

func heading(_ number: Int, _ title: String) {
    print("\n\(number). \(title)")
}

func show(_ report: MergeReport, label: String? = nil) {
    print("  " + (label.map { "[\($0)] " } ?? "") + "\(report.verdict.rawValue): \(report.summary)")
    for finding in report.findings {
        let slip = finding.slip.map { " (\($0.rawValue))" } ?? ""
        print("    - \(finding.claim.summary): \(finding.severity)\(slip). \(finding.explanation)")
    }
}
