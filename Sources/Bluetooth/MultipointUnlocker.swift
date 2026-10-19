import Foundation
@preconcurrency import IOBluetooth

/// Lets the phone keep its link to the buds while the Mac is connected.
///
/// The buds keep a record per connected host, and only let a second host hold
/// its audio link alongside another when that record's `asVer` field is 2 or
/// 3; any other value gets the older link force-released as soon as the second
/// one comes up. Samsung hosts set it with an MDE_VERSION property write on the
/// SMEP channel. A Mac never sends that, which is why connecting Budsy used to
/// kick the phone off. Writing asVer=2 ourselves fixes it: on a Buds4 Pro the
/// buds then report asVer=2, phone and Mac stay connected together, and
/// Samsung's auto switch moves audio between them.
///
/// The record lives in the buds' RAM, so the value is gone after a trip to the
/// charging case and has to be written on every connection.
///
/// The SMEP channel is closed again once the write is done. While a host holds
/// it open, the buds treat that host as a Galaxy device and wait for it to give
/// up the audio itself, so a phone could only take the audio once the Mac's
/// playback was paused by hand. Closing it, though, leaves the control channel
/// dead, so the manager reopens that afterwards (`onSessionEnded`), the same
/// sequence GalaxyBudsClient uses.
///
/// Protocol facts (the property layout and the asVer gate) are from
/// GalaxyBudsClient's MultipointPatcher, reimplemented here.
@MainActor
final class MultipointUnlocker: NSObject {
    enum Result: Equatable, CustomStringConvertible {
        case notAttempted
        case inProgress
        /// The buds publish no SMEP record, or the control channel already uses it.
        case unavailable
        case verified(asVer: UInt8)
        case rejected(asVer: UInt8)
        /// The write went out but the buds sent no record to check it against.
        case unconfirmed
        case failed

        var description: String {
            switch self {
            case .notAttempted: "not attempted"
            case .inProgress: "in progress"
            case .unavailable: "no SMEP channel"
            case .verified(let asVer): "verified (asVer=\(asVer))"
            case .rejected(let asVer): "rejected (asVer=\(asVer))"
            case .unconfirmed: "sent, unconfirmed"
            case .failed: "failed to open the SMEP channel"
            }
        }
    }

    private(set) var lastResult: Result = .notAttempted

    /// True once the buds confirmed the Mac may share them with another host
    /// on the current connection.
    var isVerified: Bool {
        if case .verified = lastResult { return true }
        return false
    }

    /// Fired when the SMEP channel closes while the connection stays up. That
    /// close leaves the control channel dead: every later write fails with
    /// kIOReturnUnderrun and nothing more arrives, though it still reports
    /// open. The manager reopens it.
    var onSessionEnded: (@MainActor () -> Void)?

    /// Every SMEP frame carries msgId 0x01; the first payload byte says what it is.
    nonisolated private static let smepMessageId: UInt8 = 0x01
    nonisolated private static let writeProperty: UInt8 = 0x43
    nonisolated private static let notifyProperty: UInt8 = 0x45
    /// MDE_VERSION property: TLV tag 0x04, type 0x03 (blob), length 4, two
    /// reserved bytes, opcode 0x0B, then asVer. The buds report the stored
    /// record back as a property starting `02 05 4C 0B`, with asVer at byte 6.
    nonisolated private static let mdeVersionWrite: [UInt8] = [0x04, 0x03, 0x04, 0x00, 0x00, 0x0B, 0x02]
    nonisolated private static let mdeVersionRecordPrefix: [UInt8] = [0x02, 0x05, 0x4C, 0x0B]

    /// The buds' SPPSERVICE4 server can be slow to accept right after the
    /// control channel opens, so a failed first attempt is expected.
    private static let maxAttempts = 3
    private static let retryDelay: Duration = .milliseconds(1500)
    private static let openTimeout: Duration = .seconds(10)
    private static let writeTimeout: Duration = .seconds(3)
    /// The longest the buds get to answer a write; they reply with a short
    /// burst of record frames.
    private static let replyWindow: Duration = .seconds(3)

    private var channel: IOBluetoothRFCOMMChannel?
    private var receiveBuffer = Data()
    private var reportedAsVer: UInt8?
    private var task: Task<Void, Never>?
    /// Bumped by every `apply` and `cancel`, so a run that was superseded stops
    /// at its next suspension point instead of touching the newer one's state.
    private var generation = 0

    /// Writes asVer=2 over the SMEP channel in the background. Safe to call
    /// again; a run still in flight is cancelled first.
    func apply(to device: IOBluetoothDevice, controlChannelId: BluetoothRFCOMMChannelID) {
        cancel()
        let run = generation

        guard let channelId = Self.smepChannel(on: device) else {
            DiagnosticsLog.shared.log("multipoint: no SMEP service record, skipping")
            lastResult = .unavailable
            return
        }
        // When the control channel fell back to SPPSERVICE4 it already holds
        // the only SMEP session; a second one on the same channel would fail.
        guard channelId != controlChannelId else {
            DiagnosticsLog.shared.log("multipoint: control channel is the SMEP channel (rfcomm \(channelId)), skipping")
            lastResult = .unavailable
            return
        }

        lastResult = .inProgress
        task = Task { [weak self] in
            await self?.unlock(device: device, channelId: channelId, run: run)
        }
    }

    func cancel() {
        generation &+= 1
        task?.cancel()
        task = nil
        closeChannel()
    }

    // MARK: - Private

    private func unlock(device: IOBluetoothDevice, channelId: BluetoothRFCOMMChannelID, run: Int) async {
        var opened = false
        for attempt in 1...Self.maxAttempts {
            opened = await open(device: device, channelId: channelId, run: run)
            guard run == generation else { return }
            if opened { break }
            DiagnosticsLog.shared.log("multipoint: rfcomm \(channelId) attempt \(attempt)/\(Self.maxAttempts) failed")
            if attempt < Self.maxAttempts {
                try? await Task.sleep(for: Self.retryDelay)
                guard run == generation else { return }
            }
        }
        guard opened, let channel else {
            lastResult = .failed
            return
        }

        reportedAsVer = nil
        receiveBuffer.removeAll()
        let payload = Data([Self.writeProperty] + Self.mdeVersionWrite)
        let frame = SmepFrame.encode(messageId: Self.smepMessageId, payload: payload)
        let written = await write(frame, on: channel)
        guard run == generation else { return }
        guard written == kIOReturnSuccess else {
            DiagnosticsLog.shared.log(String(format: "multipoint: write failed (0x%08x)", UInt32(bitPattern: written)))
            lastResult = .failed
            endSession()
            return
        }
        DiagnosticsLog.shared.log("multipoint: wrote asVer=2 " + frame.map { String(format: "%02x", $0) }.joined())

        // The buds usually confirm within a second or two; stop listening as
        // soon as they report a value that lets the phone stay.
        let deadline = ContinuousClock.now + Self.replyWindow
        while ContinuousClock.now < deadline {
            if let asVer = reportedAsVer, asVer == 2 || asVer == 3 { break }
            try? await Task.sleep(for: .milliseconds(100))
            guard run == generation else { return }
        }
        finish()
    }

    /// Writes on a background thread and stops waiting after `writeTimeout`.
    /// Both of IOBluetooth's writes block until the buds take the data —
    /// `writeAsync` only moves that blocking write onto the main queue — and
    /// the buds can leave the SMEP channel without taking it indefinitely
    /// (seen while reclaiming them from another host, and when they drop the
    /// Mac mid-write). Done on the main thread, that froze the whole app. On a
    /// timeout the caller closes the channel, which ends the stuck write.
    private func write(_ frame: Data, on channel: IOBluetoothRFCOMMChannel) async -> IOReturn {
        let target = WriteTarget(channel: channel)
        let bytes = [UInt8](frame)
        return await withCheckedContinuation { continuation in
            let resume = ResumeOnce(continuation)
            DispatchQueue.global(qos: .userInitiated).async {
                var buffer = bytes
                resume(target.channel.writeSync(&buffer, length: UInt16(buffer.count)))
            }
            Task {
                try? await Task.sleep(for: Self.writeTimeout)
                resume(kIOReturnTimeout)
            }
        }
    }

    /// Opens the channel and waits for it to report open. The open status
    /// IOBluetooth hands back is unreliable on macOS (see `connectViaRFCOMM`),
    /// so this polls `isOpen()` rather than waiting on the delegate.
    private func open(device: IOBluetoothDevice, channelId: BluetoothRFCOMMChannelID, run: Int) async -> Bool {
        var newChannel: IOBluetoothRFCOMMChannel?
        let result = device.openRFCOMMChannelAsync(&newChannel, withChannelID: channelId, delegate: self)
        guard result == kIOReturnSuccess, let newChannel else { return false }
        channel = newChannel

        let deadline = ContinuousClock.now + Self.openTimeout
        while ContinuousClock.now < deadline {
            if newChannel.isOpen() { return true }
            try? await Task.sleep(for: .milliseconds(100))
            guard run == generation, channel === newChannel else { return false }
        }
        closeChannel()
        return false
    }

    private func finish() {
        switch reportedAsVer {
        case let asVer? where asVer == 2 || asVer == 3:
            DiagnosticsLog.shared.log("multipoint: asVer=\(asVer), phone can stay connected")
            lastResult = .verified(asVer: asVer)
        case let asVer?:
            DiagnosticsLog.shared.log("multipoint: buds reported asVer=\(asVer) after the write")
            lastResult = .rejected(asVer: asVer)
        case nil:
            DiagnosticsLog.shared.log("multipoint: write sent, no record frame to confirm it")
            lastResult = .unconfirmed
        }
        endSession()
    }

    /// Closes the SMEP channel while the connection stays up and tells the
    /// manager, which then has to reopen the control channel.
    private func endSession() {
        closeChannel()
        onSessionEnded?()
    }

    /// Detaches the channel before closing it, so its close callback (and any
    /// late data) no longer matches `channel` and is ignored.
    private func closeChannel() {
        guard let channel else { return }
        self.channel = nil
        receiveBuffer.removeAll()
        channel.close()
    }

    private func handleReceived(_ data: Data) {
        receiveBuffer.append(data)
        for message in SmepFrame.extractMessages(from: &receiveBuffer) {
            // The buds report the record before and after the change, so the
            // last value seen is the current one.
            if let asVer = Self.asVer(from: message) {
                reportedAsVer = asVer
            }
        }
    }

    /// asVer from an MDE_VERSION record notification, nil for any other frame.
    nonisolated static func asVer(from message: SmepFrame.Message) -> UInt8? {
        let payload = [UInt8](message.payload)
        let prefix = mdeVersionRecordPrefix
        guard message.messageId == smepMessageId,
              payload.count >= 1 + 10,
              payload[0] == notifyProperty,
              Array(payload[1...prefix.count]) == prefix
        else { return nil }
        return payload[1 + 6]
    }

    /// The RFCOMM channel the buds publish SPPSERVICE4 on, from the SDP
    /// records the control connection has just resolved.
    private static func smepChannel(on device: IOBluetoothDevice) -> BluetoothRFCOMMChannelID? {
        guard let uuid = UUID(uuidString: BudsModel.ServiceUUID.alternative) else { return nil }
        let bytes = withUnsafeBytes(of: uuid.uuid) { Array($0) }
        let sdpUUID = IOBluetoothSDPUUID(bytes: bytes, length: bytes.count)
        guard let record = device.getServiceRecord(for: sdpUUID) else { return nil }
        var channelId: BluetoothRFCOMMChannelID = 0
        guard record.getRFCOMMChannelID(&channelId) == kIOReturnSuccess else { return nil }
        return channelId
    }
}

// MARK: - IOBluetoothRFCOMMChannelDelegate

extension MultipointUnlocker: IOBluetoothRFCOMMChannelDelegate {
    nonisolated func rfcommChannelData(
        _ rfcommChannel: IOBluetoothRFCOMMChannel!,
        data dataPointer: UnsafeMutableRawPointer!,
        length dataLength: Int
    ) {
        let receivedData = Data(bytes: dataPointer, count: dataLength)
        let source = rfcommChannel.map(ObjectIdentifier.init)
        Task { @MainActor in
            guard let channel = self.channel, source == ObjectIdentifier(channel) else { return }
            self.handleReceived(receivedData)
        }
    }

    nonisolated func rfcommChannelClosed(_ rfcommChannel: IOBluetoothRFCOMMChannel!) {
        let source = rfcommChannel.map(ObjectIdentifier.init)
        Task { @MainActor in
            guard let channel = self.channel, source == ObjectIdentifier(channel) else { return }
            DiagnosticsLog.shared.log("multipoint: SMEP channel closed by the buds")
            self.channel = nil
            self.onSessionEnded?()
        }
    }
}

/// Hands the channel to the background write. IOBluetooth objects aren't
/// marked Sendable, but a channel may be written from any thread.
private struct WriteTarget: @unchecked Sendable {
    let channel: IOBluetoothRFCOMMChannel
}

/// Resumes a continuation with whichever result arrives first — the write or
/// its timeout - and ignores the other.
private final class ResumeOnce: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<IOReturn, Never>?

    init(_ continuation: CheckedContinuation<IOReturn, Never>) {
        self.continuation = continuation
    }

    func callAsFunction(_ result: IOReturn) {
        lock.lock()
        let pending = continuation
        continuation = nil
        lock.unlock()
        pending?.resume(returning: result)
    }
}
