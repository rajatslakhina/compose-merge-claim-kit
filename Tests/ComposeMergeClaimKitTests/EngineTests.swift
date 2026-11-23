import Testing
@testable import ComposeMergeClaimKit

@Suite("Merging and the slips")
struct EngineTests {
    let base = """
    services:
      web:
        image: one
        command: ["npm", "start"]
        ports: ["8080:80"]
        environment: {A: "1", B: "2"}
        healthcheck:
          test: ["CMD", "a"]
          interval: 5s
        depends_on: [db]
        build: .
        deploy:
          replicas: 1
    """
    let over = """
    services:
      web:
        image: two
        command: npm run dev
        ports: ["8081:80"]
        environment: {A: "9"}
        healthcheck:
          test: ["CMD", "b"]
          interval: 9s
        depends_on:
          cache:
            condition: service_started
        build:
          dockerfile: Dockerfile.dev
        deploy:
          replicas: 2
        dns: []
    """

    func web(_ slip: MergeFinding.Slip? = nil) -> ComposeNode {
        merged([base, over], slip: slip)["services"]?["web"] ?? .null
    }

    @Test("Compose's own merge")
    func actual() {
        let web = web()
        #expect(web["image"]?.text == "two")
        #expect(web["command"] == .list([.scalar("npm"), .scalar("run"), .scalar("dev")]))
        #expect(web["ports"]?.items?.count == 2)
        #expect(web["environment"]?["A"]?.text == "9")
        #expect(web["environment"]?["B"]?.text == "2")
        #expect(web["healthcheck"]?["test"]?.items?.count == 2)
        #expect(web["healthcheck"]?["interval"]?.text == "9s")
        #expect(web["depends_on"]?.entries?.map(\.key) == ["db", "cache"])
        #expect(web["build"]?["context"]?.text == ".")
        #expect(web["build"]?["dockerfile"]?.text == "Dockerfile.dev")
        #expect(web["deploy"]?["replicas"]?.text == "2")
    }

    @Test("Each slip merges the way the mistake expects")
    func slips() {
        #expect(web(.listReplaced)["ports"]?.items?.count == 1)
        #expect(web(.emptyListClears)["ports"]?.items?.count == 2)
        #expect(web(.mappingReplaced)["environment"]?["B"] == nil)
        #expect(web(.commandAppended)["command"]?.items?.count == 5)
        #expect(web(.commandAppended)["healthcheck"]?["test"]?.items?.count == 4)
        let earlier = web(.earlierFileWins)
        #expect(earlier["image"]?.text == "one")
        #expect(earlier["environment"]?["A"]?.text == "1")
        #expect(earlier["deploy"]?["replicas"]?.text == "1")
    }

    @Test("An empty list keeps the earlier items, unless it is read as clearing them")
    func emptyList() {
        let files = ["services:\n  web:\n    image: a\n    dns: [1.1.1.1]", "services:\n  web:\n    dns: []"]
        #expect(merged(files)["services"]?["web"]?["dns"]?.items?.count == 1)
        #expect(merged(files, slip: .emptyListClears)["services"]?["web"]?["dns"]?.items?.isEmpty == true)
    }

    @Test("Keyed items: the later item wins, or the earlier for the first-file-wins slip")
    func keyed() {
        let files = ["services:\n  web:\n    image: a\n    volumes: [\"./a:/app\"]",
                     "services:\n  web:\n    volumes: [\"./b:/app\", !reset x]"]
        let parsed = (try? ComposeYAML.parse(files[1])) == nil
        #expect(parsed)
        let simple = ["services:\n  web:\n    image: a\n    volumes: [\"./a:/app\"]",
                      "services:\n  web:\n    volumes: [\"./b:/app\"]"]
        #expect(merged(simple)["services"]?["web"]?["volumes"] == .list([.scalar("./b:/app")]))
        #expect(merged(simple, slip: .earlierFileWins)["services"]?["web"]?["volumes"] == .list([.scalar("./a:/app")]))
        let engine = MergeEngine()
        #expect(engine.keyed([.scalar("1:1")], [.reset, .scalar("1:1")], by: PortBinding.key) == [.scalar("1:1")])
    }

    @Test("Odd shapes: top-level values, null services, tags on new keys")
    func shapes() {
        let engine = MergeEngine()
        #expect(engine.merge([]) == .null)
        #expect(engine.merge([.reset]) == .null)
        #expect(engine.top(.scalar("a"), .reset) == .scalar("a"))
        #expect(engine.clean(.reset) == .null)
        #expect(engine.top(.scalar("a"), .scalar("b")) == .scalar("b"))
        #expect(engine.top(.map([]), .scalar("b")) == .scalar("b"))
        #expect(engine.services(.null, .map([])) == .map([]))
        #expect(engine.service(.map([]), .null) == .map([]))
        #expect(engine.service(.map([]), .scalar("x")) == .scalar("x"))
        let added = engine.entries([], [ComposeEntry(key: "a", value: .reset),
                                         ComposeEntry(key: "b", value: .replace(.scalar("x")))]) { _, base, _ in base }
        #expect(added == [ComposeEntry(key: "b", value: .scalar("x"))])
        let files = ["services:\n  web:\n    image: a\nvolumes:\n  data: {}\nnetworks: [x]",
                     "services:\n  web:\n    image: b\nvolumes:\n  cache: {}\nnetworks: [y]\nname: demo"]
        let result = merged(files)
        #expect(result["volumes"]?.entries?.map(\.key) == ["data", "cache"])
        #expect(result["networks"]?.items?.count == 2)
        #expect(result["name"]?.text == "demo")
        #expect(Normalize.file(.scalar("x")) == .scalar("x"))
        #expect(Normalize.service(.scalar("x")) == .scalar("x"))
        #expect(Normalize.pair(.list([])) == nil)
        #expect(Normalize.attribute("depends_on", .list([.scalar("db"), .list([])])) == .map([ComposeEntry(key: "db", value: .null)]))
        #expect(Normalize.attribute("command", .scalar("echo 'unbalanced")) == .scalar("echo 'unbalanced"))
    }

    @Test("Shell words: quotes group, a backslash escapes, unbalanced quotes are not read")
    func shellWords() {
        #expect(ShellWords.split("sh -c 'echo \"hi there\"'") == ["sh", "-c", "echo \"hi there\""])
        #expect(ShellWords.split("a\\ b \"c d\"  e") == ["a b", "c d", "e"])
        #expect(ShellWords.split("''") == [""])
        #expect(ShellWords.split("") == [])
        #expect(ShellWords.split("a 'b") == nil)
        #expect(ShellWords.split("a\\") == nil)
    }

    @Test("Ports and mounts")
    func ports() {
        #expect(PortBinding.short("127.0.0.1:8080:80/udp") == PortBinding(hostIP: "127.0.0.1", published: 8080, target: 80,
                                                                         proto: "udp"))
        #expect(PortBinding.short("[::1]:8080:80") == PortBinding(hostIP: "::1", published: 8080, target: 80))
        #expect(PortBinding.short("80") == PortBinding(published: nil, target: 80))
        #expect(PortBinding.short("127.0.0.1::80") == PortBinding(hostIP: "127.0.0.1", published: nil, target: 80))
        #expect(PortBinding.short("8000-8001:80") == nil)
        #expect(PortBinding.short("a:b:c:80") == nil)
        #expect(PortBinding.short("[::1]:1:2:80") == nil)
        #expect(PortBinding.short("${PORT}:80") == nil)
        let long = node("target: 80\npublished: \"8080\"\nhost_ip: 0.0.0.0\nprotocol: udp")
        #expect(PortBinding.read(long) == PortBinding(hostIP: "0.0.0.0", published: 8080, target: 80, proto: "udp"))
        #expect(PortBinding.read(node("target: 80")) == PortBinding(published: nil, target: 80))
        #expect(PortBinding.read(node("target: 80\npublished: 8000-8001")) == nil)
        #expect(PortBinding.read(node("published: 1")) == nil)
        #expect(PortBinding.key(.scalar("x")).hasPrefix("?"))
        #expect(Mount.read(.scalar("/data")) == Mount(source: nil, target: "/data"))
        #expect(Mount.read(node("source: ./a\ntarget: /app")) == Mount(source: "./a", target: "/app"))
        #expect(Mount.read(node("type: tmpfs")) == nil)
        #expect(Mount.key(node("type: tmpfs")).hasPrefix("?"))
    }

    @Test("The public merge returns each service, or nil for a file it does not read")
    func publicMerge() throws {
        let checker = MergeClaimChecker()
        let services = try #require(checker.merged(["services:\n  web:\n    image: a\n    ports: [\"1:1\"]\n  api:\n    image: b",
                                                    "services:\n  web:\n    ports: [\"2:2\"]\n    env_file: x.env"]))
        #expect(services.map(\.name) == ["api", "web"])
        #expect(services.last?.published == [1, 2])
        #expect(services.last?.hasEnvFile == true)
        #expect(checker.merged(["a: &x 1"]) == nil)
        let ranged = try #require(checker.merged(["services:\n  web:\n    image: a\n    ports: [\"1-2:1-2\"]"]))
        #expect(ranged.first?.ports == nil)
    }
}
