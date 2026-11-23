import Testing
@testable import ComposeMergeClaimKit

@Suite("Judging stated results")
struct EvaluatorTests {
    func finding(_ answer: String, policy: MergePolicy = .standard) -> MergeFinding? {
        check(answer, policy: policy).findings.first
    }

    func reason(_ answer: String) -> String? {
        if case let .unchecked(reason)? = finding(answer)?.outcome { return reason }
        return nil
    }

    @Test("What makes a stated result unchecked")
    func unchecked() {
        let variable = yaml("compose.yaml", "services:", "  web:", "    image: myapp:${TAG}", "    command: [\"a\"]")
            + yaml("compose.override.yaml", "services:", "  web:", "    image: myapp:dev", "    command: [\"$X\"]")
        #expect(finding(variable + "With both files, `web` runs `myapp:dev`.")?.outcome == .exact)
        #expect(reason(yaml("compose.yaml", "services:", "  web:", "    image: myapp:${TAG}")
            + yaml("compose.override.yaml", "services:", "  web:", "    image: !reset null")
            + "With both files, `web` runs `myapp:${TAG}`.")?.contains("not set") == true)
        #expect(reason(variable + "With both files, `web` runs `$X`.")?.contains("command") == true)
        let gone = yaml("compose.yaml", "services:", "  web:", "    image: a", "    ports: [\"8080:80\"]",
                        "    environment: {DEBUG: \"1\"}")
            + yaml("compose.override.yaml", "services:", "  web: !reset {}")
        #expect(reason(gone + "With both files, `web` publishes `8080`.")?.contains("no service") == true)
        #expect(reason(gone + "With both files, `web` runs `a`.")?.contains("no service") == true)
        #expect(reason(gone + "With both files, `DEBUG` is `1`.")?.contains("no service") == true)
        let ranged = yaml("compose.yaml", "services:", "  web:", "    image: a", "    ports: [\"8080:80\"]")
            + yaml("compose.override.yaml", "services:", "  web:", "    ports: [\"9000-9001:9000-9001\"]")
        #expect(reason(ranged + "With both files, `web` publishes `8080`.")?.contains("does not read") == true)
        let envFile = yaml("compose.yaml", "services:", "  web:", "    image: a", "    environment: [A=1, B]",
                           "    env_file: [x.env]")
            + yaml("compose.override.yaml", "services:", "  web:", "    environment:", "      A: !reset null",
                   "      C: \"$Y\"")
        #expect(reason(envFile + "With both files, `A` is removed.")?.contains("env_file") == true)
        #expect(reason(envFile + "With both files, `B` is `1`.")?.contains("shell") == true)
        #expect(reason(envFile + "With both files, `C` is `x`.")?.contains("shell") == true)
        #expect(reason(pair + "With both files, `DEBUG` is `7`.")?.contains("no known misreading") == true)
        #expect(finding(pair + "With both files, `web` publishes only `8080`.")?.slip == .overrideNotLoaded)
        #expect(reason(baseFile + "With both files, `web` publishes `8080`.") == nil)
        #expect(reason(yaml("compose.yaml", "services:", "  web:", "    image: a") + "With both files, `web` runs `a`.")
            == nil)
        let unknown = MergeClaim(subject: .image(service: "web", image: "a"), sentence: "s")
        #expect(MergeEvaluator(policy: .standard).judge(unknown).outcome == .unchecked("no base compose file is shown"))
        #expect(MergeEvaluator.check(.statement(.listsAppend, holds: true), MergedProject(.null))
            == .unknown("not a stated result"))
    }

    @Test("Variables: a value, removed, kept")
    func variables() {
        #expect(finding(pair + "With both files, `LOG_LEVEL` is still set.")?.outcome == .exact)
        #expect(finding(pair + "With both files, `DEBUG` is removed.")?.slip == nil)
        let reset = yaml("compose.yaml", "services:", "  web:", "    image: a", "    environment: {DEBUG: \"1\"}")
            + yaml("compose.override.yaml", "services:", "  web:", "    environment:", "      DEBUG: !reset null")
        #expect(finding(reset + "With both files, `DEBUG` is gone.")?.outcome == .exact)
        // Only reading the base file alone gives `1`: `!reset` removes it whichever file is read as winning.
        #expect(finding(reset + "With both files, `DEBUG` is still `1`.")?.slip == .overrideNotLoaded)
        #expect(finding(reset + "With both files, `DEBUG` stays.")?.slip == .overrideNotLoaded)
        #expect(finding(pair + "With both files, `web` has `DEBUG=0`.")?.slip == .earlierFileWins)
    }

    @Test("A result that holds because of !override carries a caveat, unless caveats are off")
    func caveat() {
        let override = baseFile + yaml("docker-compose.override.yml", "services:", "  web: !override", "    image: b",
                                       "    ports: [\"9000:9000\"]")
        #expect(finding(override + "With both files, `web` publishes only `9000`.")?.outcome
            == .caveat(.overrideTagNeedsRecentCompose))
        #expect(finding(override + "With both files, `web` publishes only `9000`.", policy: .lenient)?.outcome == .exact)
        #expect(finding(override + "With both files, `web` runs `b`.")?.severity == .caution)
        #expect(MergeEvaluator.dependsOnOverrideTag(.statement(.listsAppend, holds: true), []) == false)
        let env = baseFile + yaml("docker-compose.override.yml", "services:", "  web:", "    environment: !override",
                                  "      X: \"1\"")
        #expect(finding(env + "With both files, `X` is `1`.")?.severity == .caution)
        let command = baseFile + yaml("docker-compose.override.yml", "services:", "  web:",
                                      "    command: !override [\"a\"]")
        #expect(finding(command + "With both files, `web` runs `a`.")?.severity == .caution)
    }

    @Test("Statements and file lines")
    func statements() {
        let wrong = MergeClaim(subject: .statement(.listsAppend, holds: false), sentence: "s")
        #expect(MergeEvaluator(policy: .standard).judge(wrong).slip == .listReplaced)
        for statement in MergeClaim.Statement.allCases {
            let claim = MergeClaim(subject: .statement(statement, holds: false), sentence: "s")
            #expect(MergeEvaluator(policy: .standard).judge(claim).actual == Wording.rule(statement.slip))
        }
        let line = MergeClaim(subject: .emptyList(service: "web", key: "ports", file: "o.yml"), sentence: "s")
        let finding = MergeEvaluator(policy: .standard).judge(line)
        #expect(finding.slip == .emptyListClears)
        #expect(finding.actual?.contains("!reset []") == true)
        #expect(!line.isExplicit)
    }
}
