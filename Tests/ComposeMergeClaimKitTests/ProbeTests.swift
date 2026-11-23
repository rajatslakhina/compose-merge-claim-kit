import Testing
@testable import ComposeMergeClaimKit

/// Answers written the way an assistant writes them. Correct ones must never be called wrong; wrong ones must be
/// caught with the slip behind them.
@Suite("Probes")
struct ProbeTests {
    static let resetOverride = yaml(
        "docker-compose.override.yml",
        "services:",
        "  web:",
        "    ports: !override",
        "      - \"8081:80\""
    )

    static let correct: [String] = [
        pair + "Compose merges the override into the base: `command` is replaced, while `ports` are appended, so "
            + "`web` publishes both `8080` and `8081`.",
        pair + "The override takes precedence for `image`, so `web` runs `myapp:dev`.",
        "In docker compose, use `!override` in the override file to replace the list instead of appending to it.",
        "In Helm, lists in a values override file replace the defaults rather than merging them.",
        "With Kustomize, a strategic merge patch overrides the container list of the base.",
        "In CSS, later rules override earlier ones.",
        "A subclass method overrides the parent's method.",
        "Your shell environment overrides values from `.env` in docker compose.",
        pair + "Values in the override file win over the base file.",
        "An empty list (`ports: []`) in the override does not remove the base ports; use `ports: !reset []`.",
        "`docker compose up` reads `docker-compose.override.yml` automatically.",
        "If you pass `-f docker-compose.yml`, compose skips the override file.",
        "Relative paths in the override are resolved relative to the base file's directory.",
        pair + "Because lists are appended, `web` still publishes `8080` alongside `8081`.",
        pair + "`LOG_LEVEL` stays `info` because environment variables in the override are merged by key.",
        pair + "The `db` service is unchanged.",
        pair + "In the base file, `web` publishes `8080` and runs `npm start`.",
        pair + "Before the override, `web` ran `npm start`.",
        baseFile + resetOverride + "Now `web` publishes only `8081`.",
        pair + "To publish only `8081`, add `!override` to the `ports` key.",
        pair + "Compose would then publish only `8081` if you used `!override`.",
        pair + "Many people expect `web` to publish only `8081`, but compose publishes both `8080` and `8081`.",
        "Docker Compose merges files in order: each later `-f` file overrides values from earlier ones.",
        "`docker-compose.prod.yml` is not loaded automatically; pass it with `-f`.",
        pair + "With both files, `DEBUG` is `1` and `web` uses `myapp:dev`.",
        pair + "Run `docker compose config` to see the merged result.",
        pair + "The override changes `web`'s image to `myapp:dev` and adds port `8081`.",
        pair + "`docker compose -f docker-compose.yml up` ignores the override, so `web` runs `myapp:1.0` there.",
        pair + "Ports from both files are combined, so `web` is reachable on `localhost:8080` and `localhost:8081`.",
        "Compose replaces `command` from the base file with the one in the override.",
        "The override file's `environment` entries are merged with the base, key by key.",
        "With docker compose, a later file's `ports` are added to the earlier list, not replaced.",
        pair + "If you only want `8081`, write `ports: !override` in the override.",
        pair + "`web` is not published on port `9000`.",
        "With docker compose, a later override file's `ports` are added to the earlier list, not replaced.",
        "In docker compose, the override's `command` replaces the base command; it is not appended.",
        "In docker compose, the override's `environment` does not replace the whole block: keys are merged.",
        "Values in `docker-compose.override.yml` override the same keys in `docker-compose.yml`; lists such as "
            + "`ports` are appended rather than replaced.",
        pair + "Note that `docker compose config` shows the merged file, so you can check that `web` publishes both "
            + "`8080` and `8081`.",
        "In docker compose, `!override` lets an override file replace the ports instead of appending to them.",
        "Docker compose override files don't replace lists; they append to them.",
        "To replace the base ports in docker compose, tag the override's list `!override`.",
    ]

    static let wrong: [(String, MergeFinding.Slip)] = [
        (pair + "The override's ports replace the base ports, so `web` publishes only `8081`.", .listReplaced),
        (pair + "`LOG_LEVEL` is gone because the override's environment block replaces the whole environment.",
         .mappingReplaced),
        (pair + "With both files, `web` runs `npm start npm run dev`.", .commandAppended),
        (pair + "`web` still uses `myapp:1.0`, since the base file comes first.", .earlierFileWins),
        (baseFile + yaml("docker-compose.override.yml", "services:", "  web:", "    ports: []")
            + "This removes the published port.", .emptyListClears),
        ("Compose ignores `docker-compose.override.yml` unless you pass it with `-f`.", .overrideNotLoaded),
        ("With `-f docker-compose.yml`, the override file is still merged in.", .overrideLoadedWithFile),
        ("`docker-compose.prod.yml` is picked up automatically by docker compose, just like the override.",
         .extraFileAutoLoaded),
        ("In docker compose, relative paths in the override file are resolved relative to the override file's "
            + "location.",
         .pathsRelativeToOverride),
        (pair + "With both files, `DEBUG` is `0`.", .earlierFileWins),
        (pair + "`docker compose -f docker-compose.yml up` uses `myapp:dev` for `web`.", .overrideLoadedWithFile),
        ("In docker compose, `ports: []` in the override clears the base ports.", .emptyListClears),
        (pair + "With both files, `web` publishes `8081` instead of `8080`.", .listReplaced),
        (pair + "The first file takes precedence, so `web` keeps `myapp:1.0`.", .earlierFileWins),
        (pair + "Running `docker compose up` uses only `docker-compose.yml`, so `web` runs `myapp:1.0`.",
         .overrideNotLoaded),
        ("In docker compose, the `command` in the override is appended to the base command.", .commandAppended),
        ("In docker compose, `ports` in the override are not appended: they replace the base list.", .listReplaced),
        ("With docker compose, the override's `environment` is not merged with the base.", .mappingReplaced),
        ("Docker compose override files replace the ports of the base file.", .listReplaced),
    ]

    static let realistic = """
    Docker Compose automatically merges `docker-compose.override.yml` on top of `docker-compose.yml` when you run \
    `docker compose up` without `-f`.

    **docker-compose.yml**
    ```yaml
    services:
      web:
        image: myapp:1.0
        ports:
          - "8080:80"
        environment:
          - LOG_LEVEL=info
    ```

    **docker-compose.override.yml**
    ```yaml
    services:
      web:
        build: .
        ports:
          - "9229:9229"
        environment:
          - LOG_LEVEL=debug
        volumes:
          - ./src:/app/src
    ```

    How the merge works:
    - `image` and other single values: the override wins.
    - `ports`: the lists are combined, so `web` publishes `8080` and `9229`.
    - `environment`: merged by variable name, so `LOG_LEVEL` becomes `debug`.
    - `volumes`: added, since the target `/app/src` is new.

    If you want to drop the `8080` mapping in development, use `ports: !override` or `!reset []`.

    For production, skip the override with `docker compose -f docker-compose.yml up -d`; then only `8080` is published.
    """

    static let production = """
    `docker-compose.yml`:
    ```yaml
    services:
      api:
        image: api:latest
        environment:
          NODE_ENV: development
          DB_HOST: db
    ```
    `docker-compose.prod.yml`:
    ```yaml
    services:
      api:
        image: api:1.4.2
        environment:
          NODE_ENV: production
        restart: always
    ```
    Run `docker compose -f docker-compose.yml -f docker-compose.prod.yml up -d`. The second file wins for `image`, \
    so `api` runs `api:1.4.2`, `NODE_ENV` is `production`, and `DB_HOST` stays `db` because environment keys are \
    merged. Plain `docker compose up` would not read `docker-compose.prod.yml`.
    """

    static let replacedLists = realistic.components(separatedBy: "How the merge works:")[0]
        + "Compose override files replace lists entirely. With the override above, `web` will only listen on `9229`, "
        + "and the `8080` mapping from the base file is gone."

    @Test("Realistic answers: the correct ones verify, the wrong one is caught")
    func realisticAnswers() {
        let first = check(Self.realistic)
        #expect(first.verdict == .verified, "\(first.findings.map(\.claim.summary)) \(first.findings.map(\.outcome))")
        #expect(first.findings.count >= 4)
        let second = check(Self.production)
        #expect(second.verdict == .verified, "\(second.findings.map(\.claim.summary)) \(second.findings.map(\.outcome))")
        #expect(second.findings.count >= 5)
        let wrong = check(Self.replacedLists)
        #expect(wrong.verdict == .wrong)
        #expect(Set(slips(wrong)) == [.listReplaced], "\(wrong.findings.map(\.claim.summary))")
    }

    @Test("Correct answers are never called wrong", arguments: correct.indices)
    func quiet(index: Int) {
        let report = check(Self.correct[index])
        #expect(report.verdict != .wrong, "\(Self.correct[index])\n\(report.findings.map(\.explanation))")
    }

    @Test("Wrong answers are caught with their slip", arguments: wrong.indices)
    func caught(index: Int) {
        let (answer, slip) = Self.wrong[index]
        let report = check(answer)
        #expect(report.verdict == .wrong, "\(answer)")
        #expect(slips(report).first == slip, "\(answer)\n\(report.findings.map(\.outcome))")
    }
}
