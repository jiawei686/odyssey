import Foundation
import Network

final class PeerSession: ObservableObject, @unchecked Sendable {
    enum Role {
        case host
        case client
    }

    static let serviceType = "_upperlimb-poc._tcp"

    @Published private(set) var status = "Not started"
    @Published private(set) var isConnected = false
    @Published private(set) var lastSnapshot: OverlaySnapshot?
    @Published private(set) var lastJointFrame: UpperLimbJointFrame?
    @Published private(set) var lastJointFrameReceivedAtMonotonic: TimeInterval?
    @Published private(set) var lastClinicianGuidanceMessage: ClinicianGuidanceMessage?

    private let role: Role
    private let queue = DispatchQueue(label: "com.marcel.upperlimbpoc.peer")
    private var listener: NWListener?
    private var browser: NWBrowser?
    private var connection: NWConnection?
    private var discoveredEndpoint: NWEndpoint?
    private var reconnectWorkItem: DispatchWorkItem?
    private var receiveBuffer = Data()
    private var hasStarted = false
    private weak var clinicianGuidanceDelegate: PeerSessionClinicianGuidanceDelegate?

    init(role: Role) {
        self.role = role
    }

    func start() {
        queue.async { [weak self] in
            self?.startOnQueue()
        }
    }

    private func startOnQueue() {
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
        queue.async { [weak self] in
            self?.stopOnQueue()
        }
    }

    func restart() {
        queue.async { [weak self] in
            guard let self else { return }
            self.stopOnQueue()
            self.startOnQueue()
        }
    }

    @MainActor
    func setClinicianGuidanceDelegate(
        _ delegate: PeerSessionClinicianGuidanceDelegate?
    ) {
        clinicianGuidanceDelegate = delegate
        delegate?.peerSession(self, connectionChanged: isConnected)
    }

    private func stopOnQueue() {
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
        do {
            sendPacket(try UpperLimbPeerWireCodec.encode(snapshot))
        } catch {
            publish(status: "Encode failed", connected: false)
        }
    }

    func send(_ frame: UpperLimbJointFrame) {
        guard frame.isTruthful else {
            publish(status: "Joint frame rejected before send", connected: isConnected)
            return
        }
        do {
            sendPacket(try UpperLimbPeerWireCodec.encode(frame))
        } catch {
            publish(status: "Joint-frame encode failed", connected: false)
        }
    }

    func send(_ message: ClinicianGuidanceMessage) {
        do {
            sendPacket(try UpperLimbPeerWireCodec.encode(message))
        } catch {
            publish(status: "Guidance encode failed", connected: isConnected)
        }
    }

    private func sendPacket(_ packet: Data) {
        let framedData = packet + Data([0x0A])
        queue.async { [weak self] in
            guard let self, let connection = self.connection else { return }
            connection.send(
                content: framedData,
                completion: .contentProcessed { [weak self, weak connection] error in
                    guard let error, let connection else { return }
                    self?.handleConnectionEnded(
                        connection,
                        status: "Send failed: \(error.localizedDescription)"
                    )
                }
            )
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
                self?.publish(status: "Search stopped", connected: false)
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

            guard let payload = try? UpperLimbPeerWireCodec.decode(packet) else {
                continue
            }

            DispatchQueue.main.async { [weak self] in
                switch payload {
                case .overlaySnapshot(let snapshot):
                    self?.lastSnapshot = snapshot
                case .jointFrame(let frame):
                    self?.lastJointFrame = frame
                    self?.lastJointFrameReceivedAtMonotonic = ProcessInfo.processInfo.systemUptime
                case .clinicianGuidance(let message):
                    self?.lastClinicianGuidanceMessage = message
                    if let self {
                        self.clinicianGuidanceDelegate?.peerSession(
                            self,
                            received: message
                        )
                    }
                }
            }
        }
    }

    private func publish(status: String, connected: Bool) {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            let connectionChanged = self.isConnected != connected
            self.status = status
            self.isConnected = connected
            if connectionChanged {
                self.clinicianGuidanceDelegate?.peerSession(
                    self,
                    connectionChanged: connected
                )
            }
        }
    }
}
