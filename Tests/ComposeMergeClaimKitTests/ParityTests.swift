import Testing
@testable import ComposeMergeClaimKit

@Suite("Parity with docker compose config")
struct ParityTests {
    @Test("Every recorded case merges to compose's own result", arguments: parityCases.indices)
    func merge(index: Int) {
        let (name, files, services) = parityCases[index]
        let result = merged(files)
        var actual: [String: String] = [:]
        for entry in result["services"]?.entries ?? [] {
            actual[entry.key] = canonical(entry.value)
        }
        #expect(actual == services, "\(name)")
    }
}
