import Testing
@testable import ComposeMergeClaimKit

@Suite("Reading claims")
struct ReaderTests {
    func subjects(_ text: String, context: String = "") -> [MergeClaim.Subject] {
        MergeClaimReader().claims(in: text, context: context).map(\.subject)
    }

    @Test("Statements, both ways", arguments: [
        ("With docker compose, ports in the override are appended.", MergeClaim.Statement.listsAppend, true),
        ("With docker compose, the environment in the override replaces the entire environment.", .mappingsMergeByKey, false),
        ("With docker compose, the override's environment variables are merged.", .mappingsMergeByKey, true),
        ("With docker compose, the override's command replaces the base command.", .commandReplaced, true),
        ("With docker compose, an empty list in the override keeps the base ports.", .emptyListKeeps, true),
        ("With docker compose, the last file wins.", .laterFileWins, true),
        ("With docker compose, the override file wins.", .laterFileWins, true),
        ("With docker compose, the first file wins over the override.", .laterFileWins, false),
        ("Docker compose reads the override file automatically.", .overrideReadByDefault, true),
        ("Docker compose doesn't read the override file automatically.", .overrideReadByDefault, false),
        ("You must pass `-f docker-compose.override.yml` to docker compose.", .overrideReadByDefault, false),
        ("With `-f`, docker compose reads only the files named, never the override.", .fileListExcludesOverride, true),
        ("With `-f`, docker compose doesn't read the override file.", .fileListExcludesOverride, true),
        ("With `-f`, docker compose always applies the override too.", .fileListExcludesOverride, false),
        ("`docker-compose.prod.yml` only applies with `-f` in docker compose.", .otherFilesNeedFile, true),
        ("Docker compose reads `docker-compose.prod.yml` by default.", .otherFilesNeedFile, false),
        ("With docker compose, relative paths in the override are relative to the project directory.",
         .pathsFromProjectDirectory, true),
        ("With docker compose, relative paths in the override are relative to that file.", .pathsFromProjectDirectory,
         false)
    ])
    func statements(text: String, statement: MergeClaim.Statement, holds: Bool) {
        #expect(subjects(text).contains(.statement(statement, holds: holds)), "\(subjects(text))")
    }

    @Test("Clauses that make no statement", arguments: [
        "With docker compose, are ports in the override appended?",
        "With docker compose, the override doesn't not replace ports.",
        "With docker compose, relative paths in the override are relative.",
        "With docker compose, relative paths in the override are relative to somewhere else.",
        "With docker compose, an empty list in the override is fine.",
        "With docker compose, the first file is nice.",
        "With docker compose, the override's environment variables replace the base ones.",
        "With `-f`, docker compose applies the override.",
        "Docker compose mentions `docker-compose.prod.yml` sometimes.",
        "The override file is read automatically by docker compose when you use `-f` for it.",
        "With docker compose, the override's ports are mapped with the same port numbers.",
        "With docker compose, paths in the override file are resolved next to the override file."
    ])
    func noStatement(text: String) {
        #expect(subjects(text).isEmpty, "\(subjects(text))")
    }

    @Test("Stated results: ports in their forms")
    func ports() {
        func ports(_ text: String) -> MergeClaim.PortClaim? {
            for case let .ports(_, claim) in subjects(pair + text) { return claim }
            return nil
        }
        #expect(ports("With both files, `web` publishes `8081` instead of `8080`.")
            == MergeClaim.PortClaim(present: [8081], absent: [8080]))
        #expect(ports("With both files, port `8080` is replaced by `8081` for the web service.")
            == MergeClaim.PortClaim(present: [8081], absent: [8080]))
        #expect(ports("With both files, the override replaces `8080:80` with `8081:80` for `web`.")
            == MergeClaim.PortClaim(present: [8081], absent: [8080]))
        #expect(ports("With both files, `web` no longer publishes `8080`.") == MergeClaim.PortClaim(absent: [8080]))
        #expect(ports("With both files, `web` is only available on `http://localhost:8081/`.")
            == MergeClaim.PortClaim(present: [8081], exact: true))
        #expect(ports("With both files, `web` publishes `127.0.0.1:8081:80`.") == MergeClaim.PortClaim(present: [8081]))
        #expect(ports("With both files, `web` publishes not only `8080`.") == nil)
        #expect(ports("With both files, `web` publishes `9999`.") == nil)
        #expect(ports("With both files, `web` uses `8080`.") == nil)
        #expect(ports("With both files, `web` publishes `8081` instead of `8081`.") == nil)
        #expect(EffectReader.numbers(in: "ports 70000 and v1.2 and :8080: and 8081.").map(\.value) == [8081])
    }

    @Test("Stated results: images, commands, variables, and where the service comes from")
    func others() {
        #expect(subjects(pair + "With both files, the web service uses `myapp:dev`.")
            == [.image(service: "web", image: "myapp:dev")])
        #expect(subjects(pair + "With both files, `myapp:dev` is what runs.") == [.image(service: "web", image: "myapp:dev")])
        #expect(subjects(pair + "With both files, web doesn't use `myapp:dev`.").isEmpty)
        #expect(subjects(pair + "With both files, `web` uses `myapp:dev` rather than a tag.").isEmpty)
        #expect(subjects(pair + "With both files, the service web starts with `npm start npm run dev`.")
            == [.command(service: "web", command: "npm start npm run dev")])
        #expect(subjects(pair + "With both files, `web` has `npm start`.").isEmpty)
        #expect(subjects(pair + "With both files, `web` runs `npm build`.").isEmpty)
        #expect(subjects(pair + "With both files, `web` runs `npm 'unbalanced`.").isEmpty)
        #expect(subjects(pair + "With both files, `DEBUG` in `web` is `1`.")
            == [.variable(service: "web", name: "DEBUG", .value("1"))])
        #expect(subjects(pair + "With both files, `LOG_LEVEL` survives.") == [.variable(service: "web", name: "LOG_LEVEL", .kept)])
        #expect(subjects(pair + "With both files, `LOG_LEVEL` is not `debug`.").isEmpty)
        #expect(subjects(pair + "With both files, `LOG_LEVEL` appears.").isEmpty)
        #expect(subjects(pair + "With both files, `OTHER` is `1`.").isEmpty)
        #expect(subjects(pair + "What does `web` publish with both files?").isEmpty)
        #expect(subjects("With both files, `web` publishes `8080`.").isEmpty)
        #expect(subjects(pair + "The db's container listens on `5432`.").isEmpty)
    }

    @Test("Clauses about one file, a change to make or an expectation make no claim", arguments: [
        "In `docker-compose.override.yml`, `web` publishes `8081`.",
        "Then add `!override` so `web` publishes only `8081`.",
        "You might think `web` publishes only `8081`.",
        "To get only `8081`, tag the list.",
        "Originally `web` published `8080`."
    ])
    func skipped(text: String) {
        #expect(subjects(pair + text).isEmpty, "\(subjects(pair + text))")
    }

    @Test("A sentence's own command picks the files")
    func ownCommand() throws {
        let claims = MergeClaimReader().claims(in: pair + "`docker compose -f docker-compose.yml up` runs `myapp:1.0` for `web`.")
        let claim = try #require(claims.first)
        #expect(claim.scene.selection == .files(["docker-compose.yml"]))
    }

    @Test("Files and commands in the question count")
    func context() {
        let claims = MergeClaimReader().claims(in: "With both files, `web` publishes `8080` and `8081`.", context: pair)
        #expect(claims.map(\.subject) == [.ports(service: "web", MergeClaim.PortClaim(present: [8080, 8081]))])
        var scene = MergeScene()
        MergeClaimReader.remember("```bash\ndocker compose -f a.yml up\n```\nCOMPOSE_FILE is set.", into: &scene)
        #expect(scene.selection == .unclear)
        MergeClaimReader.remember("```bash\ndocker compose -f a.yml up\n```", into: &scene)
        #expect(scene.selection == .files(["a.yml"]))
        MergeClaimReader.remember("```json\nservices:\n  web:\n    image: a\n```", into: &scene)
        #expect(scene.files.isEmpty)
        MergeClaimReader.remember("```json title=\"compose.yaml\"\nservices:\n  web:\n    image: a\n```", into: &scene)
        #expect(scene.files.count == 1)
    }

    @Test("What a text is about")
    func about() {
        #expect(MergeClaimReader.isAboutMerging(pair))
        #expect(MergeClaimReader.isAboutMerging("How do docker compose override files work?"))
        #expect(MergeClaimReader.isAboutMerging("Run `docker compose -f compose.yaml up`."))
        #expect(!MergeClaimReader.isAboutMerging("Follow it with `docker compose logs -f web`."))
        #expect(!MergeClaimReader.isAboutMerging("Helm values override the chart defaults in docker compose."))
        #expect(!MergeClaimReader.isAboutMerging("docker compose up starts the stack."))
        #expect(!MergeClaimReader.isAboutMerging("The override keyword in Swift."))
    }

    @Test("A later file's empty list under a service that has items")
    func lines() {
        let empty = baseFile + yaml("docker-compose.override.yml", "services:", "  web:", "    ports: []",
                                    "    command: []", "  db:", "    ports: []")
        #expect(subjects(empty) == [.emptyList(service: "web", key: "ports", file: "docker-compose.override.yml")])
        #expect(MergeClaimReader(checksLines: false).claims(in: empty).isEmpty)
        #expect(subjects(baseFile).isEmpty)
        let named = MergeScene(files: [ComposeFile(name: "compose.yaml", content: .node(node(
            "services:\n  web:\n    image: a\n    dns: [1.1.1.1]"))),
                                       ComposeFile(name: "compose.override.yaml", content: .node(node(
            "services:\n  web:\n    dns: []")))])
        #expect(MergeClaimReader.lines(named).count == 1)
        let unnamed = MergeScene(files: named.files, selection: .files(["compose.yaml", "compose.override.yaml"]))
        #expect(MergeClaimReader.lines(unnamed).first?.sentence == "dns: [] in compose.override.yaml")
    }
}

@Suite("Commands in order")
struct CommandOrderTests {
    @Test("A command in a code block sets the files for the sentences after it")
    func codeBlockCommand() {
        let answer = pair + "```bash\ndocker compose -f docker-compose.yml up\n```\nHere `web` runs `myapp:1.0`.\n"
            + "```bash\ndocker compose up\n```\nNow `web` runs `myapp:dev`."
        let report = check(answer)
        #expect(report.verdict == .verified, "\(report.findings.map(\.outcome))")
        #expect(report.findings.count == 2)
    }

    @Test("A command in a hypothetical sentence does not change the files")
    func hypotheticalCommand() {
        let answer = pair + "Run `docker compose up`. If you ran `docker compose -f docker-compose.yml up`, the "
            + "override would be skipped. With both files, `web` runs `myapp:dev`."
        #expect(check(answer).verdict == .verified)
    }
}
