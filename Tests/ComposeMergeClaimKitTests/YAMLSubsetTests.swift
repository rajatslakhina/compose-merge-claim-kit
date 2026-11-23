import Testing
@testable import ComposeMergeClaimKit

@Suite("YAML subset")
struct YAMLSubsetTests {
    @Test func mappingsSequencesAndScalars() throws {
        let node = try ComposeYAML.parse("""
        ---
        # leading comment
        services:
          web:
            image: "nginx:1.27"   # trailing comment
            ports:
            - "8080:80"
            - 443
            command: [python, "app.py", 'x y']
            empty: []
            env:
              - KEY=a: b
              -
              - nested:
                  deep: 1
            nothing:
            tilde: ~
            'quoted key': 'it''s # kept'
            "double": "say \\"hi\\"\\n\\tnow \\q"
        """)
        let web = try #require(node["services"]?["web"])
        #expect(web["image"]?.text == "nginx:1.27")
        #expect(web["ports"]?.items == [.scalar("8080:80"), .scalar("443")])
        #expect(web["command"]?.items == [.scalar("python"), .scalar("app.py"), .scalar("x y")])
        #expect(web["empty"]?.items == [])
        let env = try #require(web["env"]?.items)
        #expect(env[0]["KEY=a"]?.text == "b")
        #expect(env[1] == .null)
        #expect(env[2]["nested"]?["deep"]?.text == "1")
        #expect(web["nothing"] == .null)
        #expect(web["tilde"] == .null)
        #expect(web["quoted key"]?.text == "it's # kept")
        #expect(web["double"]?.text == "say \"hi\"\n\tnow q")
        #expect(web["missing"] == nil)
        #expect(node.text == nil && node.items == nil && ComposeNode.scalar("x").entries == nil)
        #expect(try ComposeYAML.parse("\n# only a comment\n") == .null)
        #expect(try ComposeYAML.parse("key:") == .map([ComposeEntry(key: "key", value: .null)]))
        #expect(try ComposeYAML.parse("- a\n- b") == .list([.scalar("a"), .scalar("b")]))
        let blocks = try ComposeYAML.parse("a: |\n  one\n  two\nb: >-\n  one\n  two\nc: {}\nd: {x: 1, 'y': \"2\", z:}")
        #expect(blocks["a"]?.text == "one\ntwo")
        #expect(blocks["b"]?.text == "one two")
        #expect(blocks["c"] == .map([]))
        #expect(blocks["d"] == .map([ComposeEntry(key: "x", value: .scalar("1")), ComposeEntry(key: "y", value: .scalar("2")),
                                     ComposeEntry(key: "z", value: .null)]))
    }

    @Test(arguments: [
        ("a: &x 1", "an anchor"), ("a: *x", "an alias"), ("a: !tag x", "tag"), ("- |\n  text", "a block scalar"),
        ("- >\n  text", "a block scalar"), ("a: {b: {c: 1}}", "nested flow"), ("a: [1,\n  2]", "flow sequence"),
        ("a: {b: 1,\n  c: 2}", "flow mapping over several lines"), ("a: {x}", "flow mapping entry"),
        ("a: |x\n  text", "block scalar header"),
        ("a: [[1]]", "nested flow"), ("a: \"open", "quoted value"), ("a: \"x\" y", "quoted value"),
        ("a: b: c", "mapping inside a plain value"), ("a: plain\n  continued", "continued"),
        ("a:\n\t- b", "tabs"), ("a: 1\n---\nb: 2", "several YAML documents"), ("%YAML 1.2\na: 1", "directive"),
        ("<<: *base", "`<<` merge"), ("a:\n  <<: {}", "`<<` merge"), ("a: 1\n just text", "continued"),
        ("a:\n    b: 1\n  c: 2", "indentation"), ("a: 1\nplain", "not `key: value`"), ("- a\n-- b", "indentation")
    ])
    func unsupported(source: String, reason: String) {
        #expect(throws: ComposeYAML.Unsupported.self) { try ComposeYAML.parse(source) }
        do {
            _ = try ComposeYAML.parse(source)
        } catch {
            #expect(error.reason.contains(reason), "\(error.reason)")
        }
    }

    @Test func keysAndComments() {
        #expect(ComposeYAML.key("\"8080:80\"") == nil)
        #expect(ComposeYAML.key("\"a\"x") == nil)
        #expect(ComposeYAML.key("\"open") == nil)
        #expect(ComposeYAML.key("'k': v")?.1 == "v")
        #expect(ComposeYAML.key("8080:80") == nil)
        #expect(ComposeYAML.key("[a]: b") == nil)
        #expect(ComposeYAML.key("") == nil)
        #expect(ComposeYAML.key("url: http://x:1")?.1 == "http://x:1")
        #expect(ComposeYAML.stripComment("a: b # c") == "a: b ")
        #expect(ComposeYAML.stripComment("a: \"b # c\" # d") == "a: \"b # c\" ")
        #expect(ComposeYAML.stripComment("a: 'it''s # x'") == "a: 'it''s # x'")
        #expect(ComposeYAML.stripComment("a: \"q\\\"# x\"") == "a: \"q\\\"# x\"")
        #expect(ComposeYAML.stripComment("a: x#y") == "a: x#y")
        #expect(ComposeYAML.stripComment("a: don't # c") == "a: don't ")
        #expect(ComposeYAML.stripComment("- [\"a\", 'b # c']") == "- [\"a\", 'b # c']")
        #expect(ComposeYAML.quoted("") == nil)
        #expect(ComposeYAML.quoted("\"a\\") == nil)
    }
}
