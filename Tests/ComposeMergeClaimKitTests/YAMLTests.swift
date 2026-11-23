import Testing
@testable import ComposeMergeClaimKit

@Suite("YAML reading")
struct YAMLTests {
    @Test("compose's merge tags are kept on a mapping's value")
    func tags() throws {
        let parsed = try ComposeYAML.parse("""
        services:
          web:
            ports: !reset []
            image: !reset null
            dns: !override [1.1.1.1]
            environment: !override
              A: "1"
            volumes: !reset
              - ./a:/a
        """)
        let web = try #require(parsed["services"]?["web"])
        #expect(web["ports"] == .reset)
        #expect(web["image"] == .reset)
        #expect(web["dns"] == .replace(.list([.scalar("1.1.1.1")])))
        #expect(web["environment"] == .replace(.map([ComposeEntry(key: "A", value: .scalar("1"))])))
        #expect(web["volumes"] == .reset)
    }

    @Test("Other tags, anchors and aliases are refused", arguments: [
        "a: !!str x", "a: !custom", "a: &anchor x", "a: *alias", "a:\n  - !reset x", "- - a", "<<: x", "a: |x\n  x", "a: !reset x\n  y"
    ])
    func refused(source: String) {
        #expect(throws: ComposeYAML.Unsupported.self) { try ComposeYAML.parse(source) }
    }

    @Test("Untagging keeps what a single file means")
    func untagged() {
        let node = ComposeNode.map([
            ComposeEntry(key: "a", value: .reset),
            ComposeEntry(key: "b", value: .replace(.list([.scalar("x"), .reset]))),
            ComposeEntry(key: "c", value: .scalar("y"))
        ])
        #expect(node.untagged == .map([ComposeEntry(key: "b", value: .list([.scalar("x")])),
                                       ComposeEntry(key: "c", value: .scalar("y"))]))
        #expect(ComposeNode.reset.untagged == nil)
        #expect(ComposeNode.scalar("x").items == nil)
        #expect(ComposeNode.list([]).text == nil)
        #expect(ComposeNode.null.entries == nil)
    }

    @Test("Block scalars, flow mappings and quotes read as before")
    func basics() throws {
        let parsed = try ComposeYAML.parse("""
        ---
        # comment
        x: >
          folded
          text
        y: {a: 1, b: "two"}
        z: 'it''s'
        w: "a\\tb\\n"
        v: ~
        u: []
        """)
        #expect(parsed["x"]?.text == "folded text")
        #expect(parsed["y"]?["b"]?.text == "two")
        #expect(parsed["z"]?.text == "it's")
        #expect(parsed["w"]?.text == "a\tb\n")
        #expect(parsed["v"] == .null)
        #expect(parsed["u"] == .list([]))
        #expect(try ComposeYAML.parse("") == .null)
    }
}
