import Testing
@testable import ComposeMergeClaimKit

@Suite("Files and commands")
struct FileTests {
    @Test("Roles come from the file name")
    func roles() {
        #expect(ComposeFile.role("compose.yaml") == .base)
        #expect(ComposeFile.role("./docker-compose.yml") == .base)
        #expect(ComposeFile.role("deploy/compose.override.yml") == .override)
        #expect(ComposeFile.role("docker-compose.prod.yml") == .other)
        #expect(ComposeFile(name: nil, content: .node(.null)).role == nil)
        #expect(ComposeFile(name: "a/compose.yaml", content: .node(.null)).basename == "compose.yaml")
        #expect(ComposeFile.basename("compose.yaml/") == "")
        #expect(EffectReader.isInstruction("1 2") == false)
        #expect(EffectReader.isInstruction("then add it"))
        #expect(EffectReader.isInstruction("run the tests"))
        #expect(!EffectReader.isInstruction("run docker compose up -d"))
    }

    @Test("Compose file names are found in prose")
    func names() {
        #expect(ComposeFile.names(in: "Put this in `./docker-compose.override.yml`.") == ["docker-compose.override.yml"])
        #expect(ComposeFile.names(in: "compose.yaml and compose.yaml, values.yaml") == ["compose.yaml"])
        #expect(ComposeFile.names(in: "title=\"compose.dev.yaml\"") == ["compose.dev.yaml"])
        #expect(ComposeFile.names(in: "no files here").isEmpty)
    }

    @Test("A block is a compose file only with a top-level services mapping")
    func read() {
        #expect(ComposeFile.read(["services:", "  web:", "    image: a"], name: nil)?.node != nil)
        #expect(ComposeFile.read(["name: x"], name: nil) == nil)
        #expect(ComposeFile.read(["a: &x 1"], name: nil) == nil)
        let unreadable = ComposeFile.read(["services:", "  web: &x", "    image: a"], name: "compose.yaml")
        #expect(unreadable?.node == nil)
        if case let .unreadable(reason)? = unreadable?.content { #expect(reason.contains("anchor")) }
    }

    @Test("A block's name comes from its info string, a first comment or the line before it")
    func blockNames() {
        #expect(MergeClaimReader.name(info: "yaml title=\"compose.override.yaml\"", lines: [], before: [])
            == "compose.override.yaml")
        #expect(MergeClaimReader.name(info: "yaml", lines: ["", "# docker-compose.yml"], before: [])
            == "docker-compose.yml")
        #expect(MergeClaimReader.name(info: "yaml", lines: ["# a comment"], before: ["In `compose.yaml`:", ""])
            == "compose.yaml")
        #expect(MergeClaimReader.name(info: "yaml", lines: [], before: ["`compose.yaml` and `compose.override.yaml`"])
            == nil)
        #expect(MergeClaimReader.name(info: "", lines: [], before: []) == nil)
    }

    @Test("Commands: -f before the subcommand counts; after it, -f is another flag")
    func commands() {
        #expect(Commands.selections(inLine: "docker compose -f a.yml --file=./b.yml up -d") == [.files(["a.yml", "b.yml"])])
        #expect(Commands.selections(inLine: "docker compose -p demo --file c.yml -f 'd.yml' up") == [.files(["c.yml", "d.yml"])])
        #expect(Commands.selections(inLine: "docker compose logs -f web") == [.defaults])
        #expect(Commands.selections(inLine: "docker-compose up && docker compose -f x.yml ps") == [.defaults, .files(["x.yml"])])
        #expect(Commands.selections(inLine: "COMPOSE_FILE=a.yml:b.yml docker compose up") == [.unclear])
        #expect(Commands.selections(inLine: "docker compose -f") == [.defaults])
        #expect(Commands.selections(inLine: "docker ps").isEmpty)
        #expect(Commands.selections(in: "Run `docker compose up` now.") == [.defaults])
        #expect(Commands.combined([]) == .defaults)
        #expect(Commands.combined([.defaults, .defaults]) == .defaults)
        #expect(Commands.combined([.defaults, .files(["a"])]) == .unclear)
    }
}
