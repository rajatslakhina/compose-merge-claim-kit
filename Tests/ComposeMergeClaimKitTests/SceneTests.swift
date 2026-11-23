import Testing
@testable import ComposeMergeClaimKit

@Suite("Which files compose reads")
struct SceneTests {
    func file(_ name: String, readable: Bool = true) -> ComposeFile {
        ComposeFile(name: name, content: readable ? .node(node("services:\n  web:\n    image: a")) : .unreadable("tabs"))
    }

    func names(_ result: Result<[ComposeFile], Unknown>?) -> [String]? {
        if case let .success(files)? = result { return files.compactMap(\.name) }
        return nil
    }

    func reason(_ result: Result<[ComposeFile], Unknown>) -> String? {
        if case let .failure(unknown) = result { return unknown.reason }
        return nil
    }

    @Test("Without -f: the base file and its override")
    func defaults() {
        let scene = MergeScene(files: [file("compose.yaml"), file("compose.override.yaml"), file("compose.prod.yaml")])
        #expect(names(scene.applied()) == ["compose.yaml", "compose.override.yaml"])
        #expect(names(scene.applied(.overrideNotLoaded)) == ["compose.yaml"])
        #expect(names(scene.applied(.extraFileAutoLoaded)) == ["compose.yaml", "compose.override.yaml", "compose.prod.yaml"])
        #expect(scene.applied(.overrideLoadedWithFile) == nil)
        #expect(names(scene.applied(.listReplaced)) == ["compose.yaml", "compose.override.yaml"])
        let alone = MergeScene(files: [file("compose.yaml")])
        #expect(alone.applied(.overrideNotLoaded) == nil)
        #expect(alone.applied(.extraFileAutoLoaded) == nil)
    }

    @Test("With -f: the files named, in order")
    func explicit() {
        let files = [file("compose.yaml"), file("compose.override.yaml"), file("compose.prod.yaml")]
        let scene = MergeScene(files: files, selection: .files(["compose.yaml", "./compose.prod.yaml"]))
        #expect(names(scene.applied()) == ["compose.yaml", "compose.prod.yaml"])
        #expect(names(scene.applied(.overrideLoadedWithFile)) == ["compose.yaml", "compose.prod.yaml", "compose.override.yaml"])
        #expect(scene.applied(.overrideNotLoaded) == nil)
        #expect(scene.applied(.extraFileAutoLoaded) == nil)
        let named = MergeScene(files: files, selection: .files(["compose.yaml", "compose.override.yaml"]))
        #expect(named.applied(.overrideLoadedWithFile) == nil)
        #expect(reason(MergeScene(files: files, selection: .files(["x.yml"])).applied()) == "`x.yml` is not shown")
    }

    @Test("What makes the files unknown")
    func unknown() {
        #expect(reason(MergeScene().applied()) == "no base compose file is shown")
        #expect(MergeScene().applied(.listReplaced) == nil)
        let prod = MergeScene(files: [file("compose.yaml"), file("compose.prod.yaml", readable: false)])
        #expect(prod.applied(.extraFileAutoLoaded).map(reason) == "`compose.prod.yaml` uses tabs")
        #expect(reason(MergeScene(files: [file("compose.yaml"), file("docker-compose.yml")]).applied())?
            .contains("several base") == true)
        #expect(reason(MergeScene(files: [file("compose.yaml"), file("compose.override.yaml"),
                                          file("docker-compose.override.yml")]).applied())?
            .contains("several override") == true)
        #expect(reason(MergeScene(files: [file("compose.yaml")], selection: .unclear).applied())?
            .contains("different files") == true)
        #expect(reason(MergeScene(files: [file("compose.yaml", readable: false)]).applied()) == "`compose.yaml` uses tabs")
    }

    @Test("A later file with the same name replaces the earlier one; services come from every file")
    func add() {
        var scene = MergeScene()
        scene.add(file("compose.yaml"))
        scene.add(ComposeFile(name: "./compose.yaml", content: .node(node("services:\n  api:\n    image: b"))))
        scene.add(ComposeFile(name: nil, content: .node(node("services:\n  db:\n    image: c"))))
        scene.add(ComposeFile(name: "compose.override.yaml", content: .unreadable("tabs")))
        #expect(scene.files.count == 3)
        #expect(scene.services == ["api", "db"])
    }
}
