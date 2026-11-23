import Testing
@testable import ComposeMergeClaimKit

@Suite("Reports, wording and the ledger")
struct ReportTests {
    @Test("Verdicts and texts")
    func report() {
        let wrong = check(pair + "With both files, `web` publishes only `8081`. `LOG_LEVEL` is `info` with both files.")
        #expect(wrong.verdict == .wrong)
        #expect(wrong.note?.hasPrefix("Compose merge check: With these files, `web` publishes ports `8080` and `8081`.")
            == true)
        #expect(wrong.feedback?.contains("- With these files") == true)
        #expect(wrong.summary == "2 claims checked, 1 hold, 1 wrong")
        #expect(wrong.corrections.count == 1)
        let none = check("Nothing here.")
        #expect(none.verdict == .noClaims)
        #expect(none.note == nil)
        #expect(none.feedback == nil)
        #expect(none.summary == "no claims about merging compose files")
        let verified = check(pair + "With both files, `web` runs `myapp:dev`.")
        #expect(verified.verdict == .verified)
        #expect(verified.findings.first?.explanation == "This holds.")
        let unchecked = check(pair + "With both files, `DEBUG` is `7`.")
        #expect(unchecked.verdict == .unchecked)
        #expect(unchecked.summary.contains("1 unchecked"))
        #expect(unchecked.findings.first?.explanation.hasPrefix("Not checked:") == true)
        let caution = check(baseFile + yaml("docker-compose.override.yml", "services:", "  web:",
                                            "    ports: !override [\"9000:9000\"]")
            + "With both files, `web` publishes only `9000`.")
        #expect(caution.verdict == .caution)
        #expect(caution.summary.contains("1 to check"))
        #expect(MergeFinding.Severity.holds < .wrong)
    }

    @Test("Wording of results and port lists")
    func wording() {
        #expect(Wording.list([]) == "no host ports")
        #expect(Wording.list([80]) == "port `80`")
        #expect(Wording.list([3, 1, 2]) == "ports `1`, `2` and `3`")
        #expect(check(pair + "With both files, `web` runs `npm start npm run dev`.").findings.first?.actual?
            .hasPrefix("With these files, `web` runs `npm run dev`.") == true)
        #expect(check(pair + "With both files, `LOG_LEVEL` is removed.").findings.first?.actual?
            .hasPrefix("With these files, `LOG_LEVEL` is `info` in `web`.") == true)
        let gone = yaml("compose.yaml", "services:", "  web:", "    image: a", "    environment: {A: \"1\", B: \"2\"}")
            + yaml("compose.override.yaml", "services:", "  web:", "    environment: !override", "      B: \"2\"")
        #expect(check(gone + "With both files, `A` is still set.").findings.first?.actual?
            .hasPrefix("With these files, `A` is not set in `web`.") == true)
        for slip in MergeFinding.Slip.allCases { #expect(!Wording.rule(slip).isEmpty) }
    }

    @Test("One mistake, one finding")
    func oneFinding() {
        let report = check(baseFile + yaml("docker-compose.override.yml", "services:", "  web:", "    ports: []")
            + "With both files, the empty list removes the base ports, so `web` no longer publishes `8080`.")
        #expect(report.findings.filter { $0.slip == .emptyListClears }.count == 1)
        let alone = check(baseFile + yaml("docker-compose.override.yml", "services:", "  web:", "    ports: []"))
        #expect(alone.findings.map(\.slip) == [.emptyListClears])
    }

    @Test("The ledger remembers files, flags repeats and forgets")
    func ledger() async {
        let ledger = MergeLedger()
        let first = await ledger.review(pair + "With both files, `web` publishes only `8081`.")
        #expect(first.verdict == .wrong)
        #expect(first.repeatedCount == 0)
        let again = await ledger.review("As I said, with both files `web` publishes only `8081`.", context: "Thanks.")
        #expect(again.verdict == .wrong)
        #expect(again.repeatedCount == 1)
        #expect(again.note?.contains("stated again") == true)
        #expect(again.summary.contains("1 repeated"))
        let later = await ledger.review("With docker compose override files, `web` runs `myapp:dev`.")
        #expect(later.verdict == .verified)
        let stats = await ledger.statistics
        #expect(stats.reviews == 3)
        #expect(stats.flagged == 2)
        #expect(stats.repeated == 1)
        await ledger.forget()
        let fresh = await ledger.review("With both files, `web` publishes only `8081`.")
        #expect(fresh.verdict == .noClaims)
        let offTopic = await ledger.review("Unrelated: `web` publishes only `8081`.")
        #expect(offTopic.findings.isEmpty)
        #expect(MergeClaimChecker().judge(MergeClaim(subject: .statement(.laterFileWins, holds: true),
                                                     sentence: "s")).outcome == .exact)
    }
}

@Suite("Claim summaries")
struct SummaryTests {
    @Test("Every kind of claim reads as a few words")
    func summaries() {
        let ports = MergeClaim.PortClaim(present: [8081], absent: [8080], exact: true)
        let cases: [(MergeClaim.Subject, String)] = [
            (.statement(.listsAppend, holds: true), "rule: listsAppend"),
            (.statement(.listsAppend, holds: false), "rule broken: listsAppend"),
            (.image(service: "web", image: "a"), "`web` runs `a`"),
            (.command(service: "web", command: "npm start"), "`web` runs `npm start`"),
            (.ports(service: "web", ports), "`web` publishes only port `8081`, not port `8080`"),
            (.ports(service: "web", MergeClaim.PortClaim(present: [1])), "`web` publishes port `1`"),
            (.variable(service: "web", name: "A", .value("1")), "`A` is `1` in `web`"),
            (.variable(service: "web", name: "A", .unset), "`A` is not set in `web`"),
            (.variable(service: "web", name: "A", .kept), "`A` is still set in `web`"),
            (.emptyList(service: "web", key: "dns", file: "o.yml"), "`dns: []` in `o.yml` clears `web`'s `dns`")
        ]
        for (subject, text) in cases {
            #expect(MergeClaim(subject: subject, sentence: "s").summary == text)
        }
    }

    @Test("Two variables in one clause each get their own claim")
    func twoVariables() {
        let subjects = MergeClaimReader().claims(in: pair + "With both files, `DEBUG` is `1` and `LOG_LEVEL` is gone.")
            .map(\.subject)
        #expect(subjects == [.variable(service: "web", name: "DEBUG", .value("1")),
                             .variable(service: "web", name: "LOG_LEVEL", .unset)])
    }
}
