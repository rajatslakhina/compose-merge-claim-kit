/// One `ports:` item, as compose keys it when it merges files: host address, published port, container port and
/// protocol.
public struct PortBinding: Sendable, Hashable {
    public let hostIP: String?
    /// The host port; `nil` when Docker picks one.
    public let published: Int?
    public let target: Int
    public let proto: String

    public init(hostIP: String? = nil, published: Int?, target: Int, proto: String = "tcp") {
        self.hostIP = hostIP
        self.published = published
        self.target = target
        self.proto = proto
    }

    /// Reads a short (`"127.0.0.1:8080:80/udp"`) or long (`target:`, `published:`) item. Ranges, variables and
    /// anything else are not read.
    static func read(_ node: ComposeNode) -> PortBinding? {
        if let text = node.text { return short(text) }
        guard let target = node["target"]?.text.flatMap(Int.init) else { return nil }
        let published = node["published"]?.text
        if let published, Int(published) == nil { return nil }
        return PortBinding(hostIP: node["host_ip"]?.text, published: published.flatMap(Int.init), target: target,
                           proto: node["protocol"]?.text ?? "tcp")
    }

    static func short(_ text: String) -> PortBinding? {
        var rest = Substring(text)
        var proto = "tcp"
        if let slash = rest.lastIndex(of: "/") {
            proto = String(rest[rest.index(after: slash)...])
            rest = rest[..<slash]
        }
        var hostIP: String?
        if rest.hasPrefix("["), let close = rest.firstIndex(of: "]") {
            hostIP = String(rest[rest.index(after: rest.startIndex)..<close])
            rest = rest[rest.index(after: close)...].drop { $0 == ":" }
        }
        let parts = rest.split(separator: ":", omittingEmptySubsequences: false).map(String.init)
        guard let last = parts.last, let target = Int(last), parts.count <= 3 else { return nil }
        if parts.count == 3 {
            guard hostIP == nil else { return nil }
            hostIP = parts[0]
        }
        let published = parts.count >= 2 ? parts[parts.count - 2] : ""
        guard published.isEmpty || Int(published) != nil else { return nil }
        return PortBinding(hostIP: hostIP, published: Int(published), target: target, proto: proto)
    }

    /// The key compose merges `ports:` items by; an item this kit does not read keys as its own text.
    static func key(_ node: ComposeNode) -> String {
        guard let port = read(node) else { return "?\(node)" }
        return "\(port.hostIP ?? "")|\(port.published.map(String.init) ?? "")|\(port.target)|\(port.proto)"
    }
}

/// One `volumes:` (or `secrets:`, `configs:`) item: where it comes from and where it is mounted.
public struct Mount: Sendable, Hashable {
    public let source: String?
    public let target: String

    public init(source: String?, target: String) {
        self.source = source
        self.target = target
    }

    static func read(_ node: ComposeNode) -> Mount? {
        if let text = node.text {
            let parts = text.split(separator: ":", omittingEmptySubsequences: false).map(String.init)
            return parts.count == 1 ? Mount(source: nil, target: text) : Mount(source: parts[0], target: parts[1])
        }
        guard let target = node["target"]?.text ?? node["source"]?.text else { return nil }
        return Mount(source: node["source"]?.text, target: target)
    }

    /// The key compose merges these items by: the mount point.
    static func key(_ node: ComposeNode) -> String {
        read(node)?.target ?? "?\(node)"
    }
}

/// One service of a merged project, as far as claims about it are checked.
public struct MergedService: Sendable, Hashable {
    public let name: String
    public let image: String?
    public let command: [String]?
    /// `nil` when an item is one this kit does not read (a range, a variable).
    public let ports: [PortBinding]?
    /// Each variable's value; `nil` for a name given without one (compose takes it from the shell).
    public let environment: [String: String?]
    /// Whether `env_file:` may set more variables, which the conversation does not show.
    public let hasEnvFile: Bool

    init(name: String, node: ComposeNode) {
        self.name = name
        image = node["image"]?.text
        command = node["command"]?.items.map { $0.compactMap(\.text) }
        let items = node["ports"]?.items ?? []
        let read = items.compactMap(PortBinding.read)
        ports = read.count == items.count ? read : nil
        var environment: [String: String?] = [:]
        for entry in node["environment"]?.entries ?? [] {
            environment[entry.key] = entry.value.text
        }
        self.environment = environment
        hasEnvFile = node["env_file"] != nil
    }

    /// The host ports Docker publishes; `nil` when a port is one this kit does not read.
    public var published: Set<Int>? {
        ports.map { Set($0.compactMap(\.published)) }
    }
}

/// The services of merged compose files.
struct MergedProject: Hashable {
    let services: [String: MergedService]

    init(_ node: ComposeNode) {
        var services: [String: MergedService] = [:]
        for entry in node["services"]?.entries ?? [] {
            services[entry.key] = MergedService(name: entry.key, node: entry.value)
        }
        self.services = services
    }
}
