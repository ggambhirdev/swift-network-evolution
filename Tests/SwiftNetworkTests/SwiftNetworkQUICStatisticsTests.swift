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

import XCTest

#if !targetEnvironment(simulator) && (os(iOS) || os(macOS) || os(Linux))

#if canImport(SwiftNetwork)
@_spi(Essentials) @_spi(ProtocolProvider) @testable import SwiftNetwork
#elseif canImport(Network)
@_spi(Essentials) @_spi(ProtocolProvider) @testable import Network
#endif

#if IMPORT_SWIFTTLS
#if EXPORT_SWIFTTLS
@_spi(SwiftTLSOptions) @_spi(SwiftTLSProtocol) import SwiftTLS
#else
@_spi(SwiftTLSOptions) @_spi(SwiftTLSProtocol) @_weakLinked internal import SwiftTLS
#endif
#endif

#if canImport(CryptoKit)
import CryptoKit
#elseif canImport(Crypto)
import Crypto
#endif

#if canImport(Glibc)
import Glibc
internal import Logging
#elseif canImport(Musl)
import Musl
internal import Logging
#elseif canImport(os)
internal import os
#endif

#if IMPORT_SWIFTTLS
#if canImport(SwiftTLS)

@available(Network 0.1.0, *)
final class SwiftNetworkQUICStatisticsTests: NetTestCase {
    func testQUICSnapshotStatisticsAreIsolated() throws {
        QUICTestHarness().runQUICTest(
            dataBlock: Array("isolation".utf8),
            afterData: { harness in
                let expectation = XCTestExpectation(description: "Validate snapshot isolation")
                harness.context.async {
                    defer { expectation.fulfill() }
                    guard let state = harness.state else {
                        XCTFail("Missing connection state")
                        return
                    }
                    let first = state.clientInstance
                    let second = state.serverInstance
                    // Seed independent connection storage on its context. This tests
                    // ownership and snapshot copies, not packet accounting.
                    let firstPackets = (first.stats[.rxPackets], first.stats[.txPackets], first.stats[.txLostPackets])
                    let secondPackets = (
                        second.stats[.rxPackets], second.stats[.txPackets], second.stats[.txLostPackets]
                    )
                    defer {
                        (first.stats[.rxPackets], first.stats[.txPackets], first.stats[.txLostPackets]) = firstPackets
                        (second.stats[.rxPackets], second.stats[.txPackets], second.stats[.txLostPackets]) =
                            secondPackets
                    }
                    first.stats[.rxPackets] = 11
                    first.stats[.txPackets] = 22
                    first.stats[.txLostPackets] = 3
                    second.stats[.rxPackets] = 44
                    second.stats[.txPackets] = 55
                    second.stats[.txLostPackets] = 6
                    let firstSaved = first.stats[.ecnCapablePacketsSent]
                    let secondSaved = second.stats[.ecnCapablePacketsSent]
                    defer {
                        first.stats[.ecnCapablePacketsSent] = firstSaved
                        second.stats[.ecnCapablePacketsSent] = secondSaved
                    }
                    first.stats[.ecnCapablePacketsSent] = 17
                    second.stats[.ecnCapablePacketsSent] = 31
                    guard
                        case .dataTransferSnapshot(let firstBefore) = first.getMetrics(
                            flow: .allFlows,
                            requestedNetworkMetric: .dataTransferSnapshot
                        ),
                        case .dataTransferSnapshot(let secondBefore) = second.getMetrics(
                            flow: .allFlows,
                            requestedNetworkMetric: .dataTransferSnapshot
                        )
                    else {
                        XCTFail("Missing snapshots")
                        return
                    }
                    first.stats[.rxPackets] = 77
                    first.stats[.txPackets] = 88
                    first.stats[.txLostPackets] = 9
                    first.stats[.ecnCapablePacketsSent] = 43
                    guard
                        case .dataTransferSnapshot(let firstAfter) = first.getMetrics(
                            flow: .allFlows,
                            requestedNetworkMetric: .dataTransferSnapshot
                        ),
                        case .dataTransferSnapshot(let secondAfter) = second.getMetrics(
                            flow: .allFlows,
                            requestedNetworkMetric: .dataTransferSnapshot
                        )
                    else {
                        XCTFail("Missing updated snapshots")
                        return
                    }
                    XCTAssertEqual(firstBefore.sentTransportECNCapablePacketCount, 17)
                    XCTAssertEqual(firstAfter.sentTransportECNCapablePacketCount, 43)
                    XCTAssertEqual(secondBefore.sentTransportECNCapablePacketCount, 31)
                    XCTAssertEqual(secondAfter, secondBefore)
                    XCTAssertEqual(firstBefore.receivedTransportPacketCount, 11)
                    XCTAssertEqual(firstBefore.sentTransportPacketAttemptCount, 22)
                    XCTAssertEqual(firstBefore.lostTransportPacketCount, 3)
                    XCTAssertEqual(firstAfter.receivedTransportPacketCount, 77)
                    XCTAssertEqual(firstAfter.sentTransportPacketAttemptCount, 88)
                    XCTAssertEqual(firstAfter.lostTransportPacketCount, 9)
                    XCTAssertEqual(secondBefore.receivedTransportPacketCount, 44)
                    XCTAssertEqual(secondBefore.sentTransportPacketAttemptCount, 55)
                    XCTAssertEqual(secondBefore.lostTransportPacketCount, 6)
                    // Replacing the current path must not replace connection statistics.
                    let savedPath = first.currentPath
                    defer { first.currentPath = savedPath }
                    first.currentPath = QUICPath(parent: first)
                    var replaced = DataTransferSnapshot()
                    first.updateDataTransferSnapshot(flow: .allFlows, &replaced)
                    XCTAssertEqual(replaced.receivedTransportPacketCount, firstAfter.receivedTransportPacketCount)
                    XCTAssertEqual(replaced.sentTransportPacketAttemptCount, firstAfter.sentTransportPacketAttemptCount)
                    XCTAssertEqual(replaced.lostTransportPacketCount, firstAfter.lostTransportPacketCount)
                }
                self.wait(for: [expectation], timeout: 5.0)
            }
        )
    }

    func testQUICTransportSnapshotMatchesCurrentPath() throws {
        QUICTestHarness().runQUICTest(
            blockSize: 10240,
            blockCount: 4,
            afterData: { harness in
                let expectation = XCTestExpectation(description: "Validate QUIC transport snapshot")
                harness.context.async {
                    defer { expectation.fulfill() }
                    guard let state = harness.state,
                        let path = state.clientInstance.currentPath,
                        case .dataTransferSnapshot(let snapshot) = state.clientHarness.getMetrics(
                            requestedNetworkMetric: .dataTransferSnapshot
                        )
                    else {
                        XCTFail("Established QUIC connection has no path or transfer snapshot")
                        return
                    }
                    XCTAssertEqual(
                        snapshot.receivedTransportPacketCount,
                        UInt64(state.clientInstance.stats[.rxPackets])
                    )
                    XCTAssertEqual(
                        snapshot.sentTransportPacketAttemptCount,
                        UInt64(state.clientInstance.stats[.txPackets])
                    )
                    XCTAssertEqual(
                        snapshot.lostTransportPacketCount,
                        UInt64(state.clientInstance.stats[.txLostPackets])
                    )
                    XCTAssertGreaterThan(snapshot.receivedTransportPacketCount, 0)
                    XCTAssertGreaterThan(snapshot.sentTransportPacketAttemptCount, 0)
                    XCTAssertTrue(path.rtt.hasInitialMeasurement)
                    XCTAssertEqual(snapshot.transportCurrentRTT, path.rtt.adjustedRTT)
                    XCTAssertEqual(snapshot.transportMinimumRTT, path.rtt.minRTT)
                    XCTAssertEqual(snapshot.transportSmoothedRTT, path.rtt.smoothedRTT)
                    XCTAssertEqual(snapshot.transportRTTVariance, path.rtt.RTTVariance)
                    XCTAssertGreaterThan(snapshot.transportCongestionWindow, 0)
                }
                self.wait(for: [expectation], timeout: 5.0)
            }
        )
    }

    func testQUICEstablishmentReportMatchesConnection() throws {
        QUICTestHarness().runQUICTest(
            blockSize: 10240,
            blockCount: 4,
            afterData: { harness in
                let expectation = XCTestExpectation(description: "Validate QUIC establishment timing")
                harness.context.async {
                    defer { expectation.fulfill() }
                    guard let state = harness.state,
                        case .protocolEstablishmentReports(let reports) = state.clientHarness.getMetrics(
                            requestedNetworkMetric: .protocolEstablishmentReports
                        ),
                        let report = reports.first(where: { $0.protocolIdentifier == QUICConnectionProtocol.identifier }
                        )
                    else {
                        XCTFail("Established connection has no QUIC establishment report")
                        return
                    }
                    XCTAssertEqual(report.handshakeMilliseconds, state.clientInstance.handshakeDuration)
                    XCTAssertEqual(report.handshakeRTTMilliseconds, state.clientInstance.handshakeRTT)
                    XCTAssertGreaterThan(report.handshakeMilliseconds, .zero)
                    XCTAssertGreaterThanOrEqual(report.handshakeRTTMilliseconds, .zero)
                }
                self.wait(for: [expectation], timeout: 5.0)
            }
        )
    }

    func testQUICStatisticsForOneStream() throws {
        QUICTestHarness().runQUICTest(
            blockSize: 10240,
            blockCount: 4,
            afterData: { harness in
                let expectation = XCTestExpectation(description: "Wait to validate stats")
                harness.context.async {
                    defer { expectation.fulfill() }

                    let clientConnectionStats = harness.state?.clientInstance.stats.connectionStatistics
                    XCTAssertNotNil(clientConnectionStats)
                    guard let clientConnectionStats else {
                        return
                    }
                    let totalSentBytes = 10240 * 4
                    XCTAssertTrue(clientConnectionStats[.rxBytes]! > 0)
                    XCTAssertTrue(clientConnectionStats[.txBytes]! > 0)
                    XCTAssertTrue(clientConnectionStats[.rxPackets]! > 0)
                    XCTAssertTrue(clientConnectionStats[.txPackets]! > 0)
                    XCTAssertTrue(clientConnectionStats[.txStreamBytes]! > 0)
                    XCTAssertTrue(clientConnectionStats[.rxStreamBytes]! > 0)
                    XCTAssertEqual(clientConnectionStats[.txStreamBytes]!, totalSentBytes)
                    XCTAssertEqual(clientConnectionStats[.rxStreamBytes]!, totalSentBytes)
                    XCTAssertEqual(clientConnectionStats[.outboundBidirectionalStreams], 1)
                }
                self.wait(for: [expectation], timeout: 5.0)
            }
        )
    }

    func testQUICStatisticsForMultipleStreams() throws {
        QUICTestHarness().runQUICTest(
            streamCount: 6,
            blockSize: 10240,
            blockCount: 4,
            afterData: { harness in
                let expectation = XCTestExpectation(description: "Wait to validate stats")
                harness.context.async {
                    defer { expectation.fulfill() }

                    let clientConnectionStats = harness.state?.clientInstance.stats.connectionStatistics
                    XCTAssertNotNil(clientConnectionStats)
                    guard let clientConnectionStats else {
                        return
                    }
                    XCTAssertTrue(clientConnectionStats[.rxBytes]! > 0)
                    XCTAssertTrue(clientConnectionStats[.txBytes]! > 0)
                    XCTAssertTrue(clientConnectionStats[.rxPackets]! > 0)
                    XCTAssertTrue(clientConnectionStats[.txPackets]! > 0)
                    XCTAssertEqual(clientConnectionStats[.outboundBidirectionalStreams], 6)
                    XCTAssertEqual(clientConnectionStats[.txInitialCryptoFrames], 1)
                    XCTAssertEqual(clientConnectionStats[.rxInitialCryptoFrames], 1)
                    XCTAssertEqual(clientConnectionStats[.txHandshakeCryptoFrames], 1)
                    XCTAssertEqual(clientConnectionStats[.rxHandshakeCryptoFrames], 1)
                    XCTAssertEqual(clientConnectionStats[.connectionAttempts], 1)
                    XCTAssertTrue(clientConnectionStats[.rxStreamFrames]! > 0)
                    XCTAssertTrue(clientConnectionStats[.txStreamFrames]! > 0)
                    XCTAssertTrue(clientConnectionStats[.txStreamBytes]! > 0)
                    XCTAssertTrue(clientConnectionStats[.rxStreamBytes]! > 0)
                }
                self.wait(for: [expectation], timeout: 5.0)
            }
        )
    }
}

#endif
#endif
#endif
