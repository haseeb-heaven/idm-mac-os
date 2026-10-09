import Foundation
import Network
import Security
import Darwin
import IDMCore

@MainActor final class BrowserBridgeServer {
    private let configurationURL: URL
    private let handler: @MainActor (BrowserRequest) async -> BrowserResponse
    private var listener: NWListener?
    private var clients: [UUID: NWConnection] = [:]
    private var token = ""
    init(configurationURL: URL, handler: @escaping @MainActor (BrowserRequest) async -> BrowserResponse) {
        self.configurationURL = configurationURL; self.handler = handler
    }
    func start() throws {
        var bytes = [UInt8](repeating: 0, count: 32)
        guard SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes) == errSecSuccess else { throw BrowserProtocolError.invalid }
        token = Data(bytes).base64EncodedString()
        let parameters = NWParameters.tcp
        parameters.requiredLocalEndpoint = .hostPort(host: "127.0.0.1", port: .any)
        let server = try NWListener(using: parameters)
        listener = server
        server.stateUpdateHandler = { [weak self, weak server] state in
            Task { @MainActor in
                guard let self, let server else { return }
                if case .ready = state, let port = server.port {
                    do {
                        let parent = self.configurationURL.deletingLastPathComponent()
                        try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true)
                        let data = try JSONEncoder().encode(BrowserBridgeConfiguration(port: port.rawValue, token: self.token))
                        let temporary = parent.appendingPathComponent(".bridge-\(UUID().uuidString)")
                        let descriptor = Darwin.open(temporary.path, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW, 0o600)
                        guard descriptor >= 0 else { throw BrowserProtocolError.invalid }
                        let file = FileHandle(fileDescriptor: descriptor, closeOnDealloc: true)
                        defer { try? file.close(); try? FileManager.default.removeItem(at: temporary) }
                        try file.write(contentsOf: data); try file.synchronize(); try file.close()
                        guard Darwin.rename(temporary.path, self.configurationURL.path) == 0 else { throw BrowserProtocolError.invalid }
                    } catch { self.stop() }
                }
            }
        }
        server.newConnectionHandler = { [weak self] connection in
            Task { @MainActor in
                guard let self, self.clients.count < 16 else { connection.cancel(); return }
                let id = UUID(); self.clients[id] = connection
                connection.start(queue: .main)
                self.receive(connection, id: id, buffer: Data())
                Task { @MainActor [weak self] in
                    try? await Task.sleep(for: .seconds(150))
                    self?.close(id)
                }
            }
        }
        server.start(queue: .main)
    }
    private func close(_ id: UUID) { clients.removeValue(forKey: id)?.cancel() }
    private func receive(_ connection: NWConnection, id: UUID, buffer: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] data, _, complete, error in
            Task { @MainActor in
                guard let self, self.clients[id] != nil else { return }
                var received = buffer; if let data { received.append(data) }
                do {
                    guard received.count <= NativeMessageFrame.maximumBytes + 4 else { throw BrowserProtocolError.invalid }
                    if let frame = try NativeMessageFrame.extract(buffer: &received) {
                        guard received.isEmpty else { throw BrowserProtocolError.invalid }
                        let envelope = try JSONDecoder().decode(BrowserEnvelope.self, from: frame)
                        guard self.matchesToken(envelope.token) else { throw BrowserProtocolError.invalid }
                        try envelope.request.validate()
                        let response = await self.handler(envelope.request)
                        let encoded = try NativeMessageFrame.encode(JSONEncoder().encode(response))
                        connection.send(content: encoded, completion: .contentProcessed { _ in
                            Task { @MainActor [weak self] in self?.close(id) }
                        })
                    } else if complete || error != nil { self.close(id) }
                    else { self.receive(connection, id: id, buffer: received) }
                } catch { self.close(id) }
            }
        }
    }
    private func matchesToken(_ candidate: String) -> Bool {
        let a = Array(candidate.utf8), b = Array(token.utf8)
        guard a.count == b.count else { return false }
        var difference: UInt8 = 0
        for (x, y) in zip(a, b) { difference |= x ^ y }
        return difference == 0
    }
    func stop() {
        listener?.cancel(); listener = nil
        for connection in clients.values { connection.cancel() }; clients.removeAll()
        if let data = try? Data(contentsOf: configurationURL), let config = try? JSONDecoder().decode(BrowserBridgeConfiguration.self, from: data), matchesToken(config.token) {
            try? FileManager.default.removeItem(at: configurationURL)
        }
    }
}
