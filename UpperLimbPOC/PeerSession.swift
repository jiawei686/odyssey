import Foundation
import Network
import OSLog

@MainActor
protocol PeerSessionOdysseyClinicalSessionDelegate: AnyObject {
    func peerSession(_ peer: PeerSession, odysseyConnectionChanged isConnected: Bool)
    func peerSession(_ peer: PeerSession, received message: OdysseyClinicalSessionMessage)
}

final class PeerSession: ObservableObject, @unchecked Sendable {
    enum Role {
        case host
        case client
    }

    static let serviceType = "_upperlimb-poc._tcp"
#if ODYSSEY_INTEGRATED_DEMO
    static let serviceName = "Odyssey Clinician Companion"
#else
    static let serviceName = "Upper Limb POC"
#endif

    @Published private(set) var status = "Not started"
    @Published private(set) var isConnected = false
    @Published private(set) var lastSnapshot: OverlaySnapshot?
    @Published private(set) var lastJointFrame: UpperLimbJointFrame?
    @Published private(set) var lastJointFrameReceivedAtMonotonic: TimeInterval?
    @Published private(set) var lastClinicianGuidanceMessage: ClinicianGuidanceMessage?
    @Published private(set) var lastOdysseyClinicalSessionMessage: OdysseyClinicalSessionMessage?

    private let role: Role
    private let queue = DispatchQueue(label: "com.marcel.upperlimbpoc.peer")
    private var listener: NWListener?
    private var browser: NWBrowser?
    private var connection: NWConnection?
    private var discoveredEndpoint: NWEndpoint?
    private var reconnectWorkItem: DispatchWorkItem?
#if ODYSSEY_INTEGRATED_DEMO
    private var endpointFailover = PeerEndpointFailoverState<NWEndpoint>()
    private var verificationWorkItem: DispatchWorkItem?
    private var connectionIsVerified = false
#endif
    private var receiveBuffer = Data()
    private var hasStarted = false
    private weak var clinicianGuidanceDelegate: PeerSessionClinicianGuidanceDelegate?
    private weak var odysseyClinicalSessionDelegate: PeerSessionOdysseyClinicalSessionDelegate?
    private let logger = Logger(
        subsystem: "com.marcel.UpperLimbPOC",
        category: "PeerSession"
    )

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

    @MainActor
    func setOdysseyClinicalSessionDelegate(
        _ delegate: PeerSessionOdysseyClinicalSessionDelegate?
    ) {
        odysseyClinicalSessionDelegate = delegate
        delegate?.peerSession(self, odysseyConnectionChanged: isConnected)
    }

    private func stopOnQueue() {
        hasStarted = false
        reconnectWorkItem?.cancel()
#if ODYSSEY_INTEGRATED_DEMO
        verificationWorkItem?.cancel()
#endif
        browser?.cancel()
        listener?.cancel()
        connection?.cancel()
        browser = nil
        listener = nil
        connection = nil
        discoveredEndpoint = nil
        reconnectWorkItem = nil
#if ODYSSEY_INTEGRATED_DEMO
        endpointFailover.reset()
        verificationWorkItem = nil
        connectionIsVerified = false
#endif
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

    func send(_ message: OdysseyClinicalSessionMessage) {
        do {
            sendPacket(try UpperLimbPeerWireCodec.encode(message))
        } catch {
            publish(status: "Odyssey session encode failed", connected: isConnected)
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
                name: Self.serviceName,
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
#if ODYSSEY_INTEGRATED_DEMO
            let orderedEndpoints = results.map(\.endpoint).sorted {
                self.endpointSortKey($0) < self.endpointSortKey($1)
            }
            let activeWasRemoved = self.endpointFailover.update(
                orderedEndpoints: orderedEndpoints
            )
            self.logger.notice(
                "discovery candidates=\(orderedEndpoints.count) activeRemoved=\(activeWasRemoved)"
            )
            if activeWasRemoved, let activeConnection = self.connection {
                self.connection = nil
                self.verificationWorkItem?.cancel()
                self.verificationWorkItem = nil
                self.connectionIsVerified = false
                activeConnection.cancel()
                self.receiveBuffer.removeAll(keepingCapacity: true)
                self.publish(
                    status: "Clinician companion disappeared; trying another…",
                    connected: false
                )
            }
            guard self.connection == nil else { return }
            self.startNextDiscoveredEndpoint()
#else
            let endpoint = results.first?.endpoint
            self.discoveredEndpoint = endpoint
            guard self.connection == nil, let endpoint else { return }
            self.start(NWConnection(to: endpoint, using: .tcp))
#endif
        }
        self.browser = browser
        browser.start(queue: queue)
        publish(status: "Starting Vision Pro browser…", connected: false)
    }

#if ODYSSEY_INTEGRATED_DEMO
    private func endpointSortKey(_ endpoint: NWEndpoint) -> String {
        let preferredPrefix: String
        if case .service(let name, _, _, _) = endpoint,
           name == Self.serviceName {
            preferredPrefix = "0"
        } else {
            preferredPrefix = "1"
        }
        return preferredPrefix + "|" + String(describing: endpoint)
    }

    private func startNextDiscoveredEndpoint() {
        guard role == .client, hasStarted, connection == nil else { return }
        guard let endpoint = endpointFailover.beginNextAttempt() else {
            publish(
                status: endpointFailover.orderedEndpoints.isEmpty
                    ? "Searching for clinician companion…"
                    : "No verified clinician companion; retrying…",
                connected: false
            )
            scheduleReconnect()
            return
        }
        logger.notice(
            "candidate=start endpoint=\(String(describing: endpoint), privacy: .public)"
        )
        start(NWConnection(to: endpoint, using: .tcp))
    }

    private func scheduleVerificationTimeout(for connection: NWConnection) {
        verificationWorkItem?.cancel()
        let workItem = DispatchWorkItem { [weak self, weak connection] in
            guard let self, let connection,
                  self.connection === connection,
                  !self.connectionIsVerified else { return }
            self.rejectCandidate(
                connection,
                status: "Peer did not identify as clinician companion"
            )
        }
        verificationWorkItem = workItem
        queue.asyncAfter(deadline: .now() + 3, execute: workItem)
    }

    private func rejectCandidate(_ rejected: NWConnection, status: String) {
        guard let active = connection, active === rejected else { return }
        logger.error("candidate=rejected reason=\(status, privacy: .public)")
        verificationWorkItem?.cancel()
        verificationWorkItem = nil
        connection = nil
        connectionIsVerified = false
        rejected.cancel()
        receiveBuffer.removeAll(keepingCapacity: true)
        endpointFailover.failActiveAttempt()
        publish(status: status + "; trying another…", connected: false)
        startNextDiscoveredEndpoint()
    }

    private func isValidClinicianHandshake(
        _ message: OdysseyClinicalSessionMessage
    ) -> Bool {
        guard message.protocolVersion == OdysseyClinicalSessionProtocol.currentVersion,
              message.payload.kind == .handshake,
              let handshake = message.payload.handshake,
              handshake.endpointRole == .clinicianCompanion,
              handshake.isValid,
              handshake.descriptor == .odysseyRightForearmReference,
              handshake.hasRequiredCapabilities(
                supportedBy: OdysseyClinicalSessionCapability.required
              )
        else { return false }
        return true
    }
#endif

    private func start(_ connection: NWConnection) {
        reconnectWorkItem?.cancel()
        reconnectWorkItem = nil
#if ODYSSEY_INTEGRATED_DEMO
        verificationWorkItem?.cancel()
        verificationWorkItem = nil
        connectionIsVerified = false
#endif
        self.connection?.cancel()
        self.connection = connection
        receiveBuffer.removeAll(keepingCapacity: true)

        connection.stateUpdateHandler = { [weak self, weak connection] state in
            guard let self else { return }
            switch state {
            case .ready:
#if ODYSSEY_INTEGRATED_DEMO
                if self.role == .client {
                    self.logger.notice("transport=tcp-ready verification=pending")
                    self.publish(
                        status: "Verifying clinician companion…",
                        connected: false
                    )
                    if let connection {
                        self.scheduleVerificationTimeout(for: connection)
                        self.receiveNext(on: connection)
                    }
                    return
                }
#endif
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
                self.consume(data, from: connection)
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
#if ODYSSEY_INTEGRATED_DEMO
        verificationWorkItem?.cancel()
        verificationWorkItem = nil
        connectionIsVerified = false
#endif
        endedConnection.cancel()
        receiveBuffer.removeAll(keepingCapacity: true)
        publish(status: status, connected: false)

        guard hasStarted else { return }
        switch role {
        case .host:
            break
        case .client:
#if ODYSSEY_INTEGRATED_DEMO
            endpointFailover.failActiveAttempt()
            startNextDiscoveredEndpoint()
#else
            scheduleReconnect()
#endif
        }
    }

    private func scheduleReconnect() {
#if ODYSSEY_INTEGRATED_DEMO
        guard role == .client, reconnectWorkItem == nil else { return }
        let workItem = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.reconnectWorkItem = nil
            guard self.hasStarted, self.connection == nil else { return }
            self.endpointFailover.resetAttempts()
            self.startNextDiscoveredEndpoint()
        }
        reconnectWorkItem = workItem
        queue.asyncAfter(deadline: .now() + 1, execute: workItem)
#else
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
#endif
    }

    private func consume(_ data: Data, from connection: NWConnection) {
        receiveBuffer.append(data)

        while let newline = receiveBuffer.firstIndex(of: 0x0A) {
            let packet = Data(receiveBuffer[..<newline])
            receiveBuffer.removeSubrange(...newline)

            guard let payload = try? UpperLimbPeerWireCodec.decode(packet) else {
                continue
            }

#if ODYSSEY_INTEGRATED_DEMO
            if role == .client, !connectionIsVerified {
                guard case .odysseyClinicalSession(let message) = payload else {
                    continue
                }
                guard isValidClinicianHandshake(message) else {
                    if message.payload.kind == .handshake {
                        rejectCandidate(
                            connection,
                            status: "Peer identity or capabilities rejected"
                        )
                        return
                    }
                    continue
                }
                connectionIsVerified = true
                verificationWorkItem?.cancel()
                verificationWorkItem = nil
                logger.notice("transport=verified role=clinician-companion")
                publish(status: "Connected to clinician companion", connected: true)
            }
#endif

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
                case .odysseyClinicalSession(let message):
                    self?.lastOdysseyClinicalSessionMessage = message
                    if let self {
                        self.odysseyClinicalSessionDelegate?.peerSession(
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
                self.odysseyClinicalSessionDelegate?.peerSession(
                    self,
                    odysseyConnectionChanged: connected
                )
            }
        }
    }
}
