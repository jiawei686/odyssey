import Foundation
import Network

final class PeerSession: ObservableObject {
    enum Role {
        case host
        case client
    }

    static let serviceType = "_upperlimb-poc._tcp"

    @Published private(set) var status = "Not started"
    @Published private(set) var isConnected = false
    @Published private(set) var lastSnapshot: OverlaySnapshot?

    private let role: Role
    private let queue = DispatchQueue(label: "com.marcel.upperlimbpoc.peer")
    private var listener: NWListener?
    private var browser: NWBrowser?
    private var connection: NWConnection?
    private var receiveBuffer = Data()
    private var hasStarted = false

    init(role: Role) {
        self.role = role
    }

    func start() {
        guard !hasStarted else { return }
        hasStarted = true

        switch role {
        case .host:
            startHosting()
        case .client:
            startBrowsing()
        }
    }

    func stop() {
        browser?.cancel()
        listener?.cancel()
        connection?.cancel()
        browser = nil
        listener = nil
        connection = nil
        hasStarted = false
        publish(status: "Stopped", connected: false)
    }

    func send(_ snapshot: OverlaySnapshot) {
        guard let connection else { return }

        do {
            var data = try JSONEncoder().encode(snapshot)
            data.append(0x0A)
            connection.send(content: data, completion: .contentProcessed { [weak self] error in
                if let error {
                    self?.publish(status: "Send failed: \(error.localizedDescription)", connected: false)
                }
            })
        } catch {
            publish(status: "Encode failed", connected: isConnected)
        }
    }

    private func startHosting() {
        do {
            let listener = try NWListener(using: .tcp)
            listener.service = NWListener.Service(
                name: "Upper Limb POC",
                type: Self.serviceType
            )
            listener.stateUpdateHandler = { [weak self] state in
                switch state {
                case .ready:
                    self?.publish(status: "Waiting for Vision Pro", connected: false)
                case .failed(let error):
                    self?.publish(status: "Host failed: \(error.localizedDescription)", connected: false)
                case .cancelled:
                    self?.publish(status: "Host stopped", connected: false)
                default:
                    break
                }
            }
            listener.newConnectionHandler = { [weak self] connection in
                self?.start(connection)
            }
            self.listener = listener
            listener.start(queue: queue)
            publish(status: "Starting iPad host…", connected: false)
        } catch {
            publish(status: "Could not start host", connected: false)
        }
    }

    private func startBrowsing() {
        let browser = NWBrowser(
            for: .bonjour(type: Self.serviceType, domain: nil),
            using: .tcp
        )
        browser.stateUpdateHandler = { [weak self] state in
            switch state {
            case .ready:
                self?.publish(status: "Searching for iPad", connected: false)
            case .failed(let error):
                self?.publish(status: "Browse failed: \(error.localizedDescription)", connected: false)
            case .cancelled:
                if self?.isConnected == false {
                    self?.publish(status: "Search stopped", connected: false)
                }
            default:
                break
            }
        }
        browser.browseResultsChangedHandler = { [weak self] results, _ in
            guard let self,
                  self.connection == nil,
                  let endpoint = results.first?.endpoint else { return }
            self.start(NWConnection(to: endpoint, using: .tcp))
        }
        self.browser = browser
        browser.start(queue: queue)
        publish(status: "Starting Vision Pro browser…", connected: false)
    }

    private func start(_ connection: NWConnection) {
        self.connection?.cancel()
        self.connection = connection
        receiveBuffer.removeAll(keepingCapacity: true)

        connection.stateUpdateHandler = { [weak self, weak connection] state in
            guard let self else { return }
            switch state {
            case .ready:
                self.publish(status: "Connected", connected: true)
                if let connection {
                    self.receiveNext(on: connection)
                }
            case .waiting(let error):
                self.publish(status: "Waiting: \(error.localizedDescription)", connected: false)
            case .failed(let error):
                self.publish(status: "Connection failed: \(error.localizedDescription)", connected: false)
                self.connection = nil
            case .cancelled:
                self.publish(status: "Disconnected", connected: false)
                self.connection = nil
            default:
                break
            }
        }
        connection.start(queue: queue)
        publish(status: "Connecting…", connected: false)
    }

    private func receiveNext(on connection: NWConnection) {
        connection.receive(
            minimumIncompleteLength: 1,
            maximumLength: 65_536
        ) { [weak self, weak connection] data, _, isComplete, error in
            guard let self else { return }

            if let data, !data.isEmpty {
                self.consume(data)
            }

            if let error {
                self.publish(status: "Receive failed: \(error.localizedDescription)", connected: false)
                return
            }

            if isComplete {
                self.publish(status: "Peer disconnected", connected: false)
                return
            }

            if let connection {
                self.receiveNext(on: connection)
            }
        }
    }

    private func consume(_ data: Data) {
        receiveBuffer.append(data)

        while let newline = receiveBuffer.firstIndex(of: 0x0A) {
            let packet = Data(receiveBuffer[..<newline])
            receiveBuffer.removeSubrange(...newline)

            guard let snapshot = try? JSONDecoder().decode(
                OverlaySnapshot.self,
                from: packet
            ) else { continue }

            DispatchQueue.main.async { [weak self] in
                self?.lastSnapshot = snapshot
            }
        }
    }

    private func publish(status: String, connected: Bool) {
        DispatchQueue.main.async { [weak self] in
            self?.status = status
            self?.isConnected = connected
        }
    }
}

