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
    private var discoveredEndpoint: NWEndpoint?
    private var reconnectWorkItem: DispatchWorkItem?
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
        hasStarted = false
        reconnectWorkItem?.cancel()
        browser?.cancel()
        listener?.cancel()
        connection?.cancel()
        browser = nil
        listener = nil
        connection = nil
        discoveredEndpoint = nil
        reconnectWorkItem = nil
        publish(status: "Stopped", connected: false)
    }

    func send(_ snapshot: OverlaySnapshot) {
        guard let connection else { return }

        do {
            var data = try JSONEncoder().encode(snapshot)
            data.append(0x0A)
            connection.send(content: data, completion: .contentProcessed { [weak self, weak connection] error in
                guard let error, let connection else { return }
                self?.handleConnectionEnded(
                    connection,
                    status: "Send failed: \(error.localizedDescription)"
                )
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
            guard let self else { return }
            let endpoint = results.first?.endpoint
            self.discoveredEndpoint = endpoint
            guard self.connection == nil, let endpoint else { return }
            self.start(NWConnection(to: endpoint, using: .tcp))
        }
        self.browser = browser
        browser.start(queue: queue)
        publish(status: "Starting Vision Pro browser…", connected: false)
    }

    private func start(_ connection: NWConnection) {
        reconnectWorkItem?.cancel()
        reconnectWorkItem = nil
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
                guard let connection else { return }
                self.handleConnectionEnded(
                    connection,
                    status: "Connection failed: \(error.localizedDescription)"
                )
            case .cancelled:
                guard let connection else { return }
                self.handleConnectionEnded(connection, status: "Disconnected")
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
            guard let self, let connection else { return }

            if let data, !data.isEmpty {
                self.consume(data)
            }

            if let error {
                self.handleConnectionEnded(
                    connection,
                    status: "Receive failed: \(error.localizedDescription)"
                )
                return
            }

            if isComplete {
                self.handleConnectionEnded(connection, status: "Peer disconnected")
                return
            }

            self.receiveNext(on: connection)
        }
    }

    private func handleConnectionEnded(
        _ endedConnection: NWConnection,
        status: String
    ) {
        guard let activeConnection = connection,
              activeConnection === endedConnection else { return }

        connection = nil
        endedConnection.cancel()
        receiveBuffer.removeAll(keepingCapacity: true)
        publish(status: status, connected: false)

        guard hasStarted else { return }
        switch role {
        case .host:
            break
        case .client:
            scheduleReconnect()
        }
    }

    private func scheduleReconnect() {
        guard reconnectWorkItem == nil,
              let endpoint = discoveredEndpoint else { return }

        let workItem = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.reconnectWorkItem = nil
            guard self.hasStarted, self.connection == nil else { return }
            self.start(NWConnection(to: endpoint, using: .tcp))
        }
        reconnectWorkItem = workItem
        queue.asyncAfter(deadline: .now() + 1.0, execute: workItem)
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
