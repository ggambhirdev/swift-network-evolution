//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift open source project
//
// Copyright (c) 2026 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0
//
// See LICENSE.txt for license information
// See CONTRIBUTORS.txt for the list of Swift project authors
//
// SPDX-License-Identifier: Apache-2.0
//
//===----------------------------------------------------------------------===//

@_spi(ProtocolProvider)
@available(Network 0.1.0, *)
public struct DataTransferSnapshot: Equatable {
    var interfaceIndex: UInt64?

    var receivedIPPacketCount: UInt64 = 0
    var receivedIPEct1PacketCount: UInt64 = 0
    var receivedIPEct0PacketCount: UInt64 = 0
    var receivedIPCEPacketCount: UInt64 = 0
    var sentIPPacketCount: UInt64 = 0

    /// Datagram frames processed by the QUIC connection's receive batch.
    /// Includes frames rejected during parsing; coalesced QUIC packets count as one datagram.
    public internal(set) var receivedTransportDatagramCount: UInt64 = 0
    /// QUIC packet send attempts counted before sealing and lower-layer submission.
    /// A later failure can prevent a counted attempt from being transmitted.
    public internal(set) var sentTransportPacketAttemptCount: UInt64 = 0
    /// QUIC packets declared lost, including declarations later found to be spurious.
    public internal(set) var lostTransportPacketCount: UInt64 = 0

    var receivedTransportByteCount: UInt64 = 0
    var receivedTransportDuplicateByteCount: UInt64 = 0
    var receivedTransportOutOfOrderByteCount: UInt64 = 0
    var sentTransportByteCount: UInt64 = 0
    var sentTransportRetransmittedByteCount: UInt64 = 0
    /// The number of ECN-capable transport packets sent by this connection.
    public internal(set) var sentTransportECNCapablePacketCount: UInt64 = 0
    /// The number of sent ECN-capable transport packets acknowledged by the peer.
    public internal(set) var sentTransportECNCapableAckedPacketCount: UInt64 = 0
    /// The transport's accumulated congestion-experienced feedback count.
    ///
    /// QUIC accumulates validated cumulative CE feedback, so this value can count a
    /// marked packet more than once across acknowledgments.
    public internal(set) var sentTransportECNCapableMarkedPacketCount: UInt64 = 0
    /// The number of sent ECN-capable transport packets declared lost.
    public internal(set) var sentTransportECNCapableLostPacketCount: UInt64 = 0

    /// The transport's smoothed round-trip time. QUIC reports its current path's estimate.
    ///
    /// Before a measurement, QUIC may report its initial estimate.
    public internal(set) var transportSmoothedRTT: NetworkDuration = .milliseconds(0)
    /// The minimum round-trip time for the current QUIC path.
    ///
    /// Before the first sample, QUIC reports an unmeasured sentinel of `UInt32.max` seconds.
    public internal(set) var transportMinimumRTT: NetworkDuration = .milliseconds(0)
    /// The current round-trip time. QUIC reports its latest ACK-delay-adjusted sample.
    public internal(set) var transportCurrentRTT: NetworkDuration = .milliseconds(0)
    /// The transport's round-trip time variance estimate for the current QUIC path.
    public internal(set) var transportRTTVariance: NetworkDuration = .milliseconds(0)

    /// The congestion window in bytes. QUIC reports its current path's window.
    ///
    /// QUIC leaves the RTT and congestion fields at zero when there is no current path.
    public internal(set) var transportCongestionWindow: UInt64 = 0
    var transportSlowStartThreshold: UInt64 = 0

    var receivedApplicationByteCount: UInt64 = 0
    var sentApplicationByteCount: UInt64 = 0

    var migrationToCellCount: UInt64 = 0
    var migrationToWifiCount: UInt64 = 0
    var migrationToWiredCount: UInt64 = 0
    var migrationToOtherCount: UInt64 = 0
    var migrationToFallbackCount: UInt64 = 0
}
