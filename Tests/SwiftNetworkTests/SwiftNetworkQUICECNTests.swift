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
#if !NETWORK_PRIVATE
@available(Network 0.1.0, *)
final class SwiftNetworkQUICECNTests: NetTestCase {
    private func assertECNSnapshotMatchesStatistics(
        _ connection: QUICConnection,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        guard
            case .dataTransferSnapshot(let snapshot) = connection.getMetrics(
                flow: .allFlows,
                requestedNetworkMetric: .dataTransferSnapshot
            )
        else {
            XCTFail("Missing QUIC transfer snapshot", file: file, line: line)
            return
        }
        XCTAssertEqual(
            snapshot.sentTransportECNCapablePacketCount,
            UInt64(connection.stats[.ecnCapablePacketsSent]),
            file: file,
            line: line
        )
        XCTAssertEqual(
            snapshot.sentTransportECNCapableAckedPacketCount,
            UInt64(connection.stats[.ecnCapablePacketsAcknowledged]),
            file: file,
            line: line
        )
        XCTAssertEqual(
            snapshot.sentTransportECNCapableMarkedPacketCount,
            UInt64(connection.stats[.ecnCapablePacketsMarked]),
            file: file,
            line: line
        )
        XCTAssertEqual(
            snapshot.sentTransportECNCapableLostPacketCount,
            UInt64(connection.stats[.ecnCapablePacketsLost]),
            file: file,
            line: line
        )
    }

    func testECNSnapshotMapsDistinctStatistics() throws {
        QUICTestHarness().runQUICTest(
            dataBlock: Array("ECN snapshot".utf8),
            afterData: { harness in
                let expectation = XCTestExpectation(description: "Validate distinct ECN snapshot values")
                harness.context.async {
                    defer { expectation.fulfill() }
                    guard let connection = harness.state?.clientInstance else {
                        XCTFail("Missing QUIC connection")
                        return
                    }
                    // This tests field mapping, not generation of CE or loss events.
                    let keys: [QUICStatistic] = [
                        .ecnCapablePacketsSent, .ecnCapablePacketsAcknowledged, .ecnCapablePacketsMarked,
                        .ecnCapablePacketsLost,
                    ]
                    let saved = keys.map { connection.stats[$0] }
                    defer {
                        for (key, value) in zip(keys, saved) { connection.stats[key] = value }
                    }
                    for (key, value) in zip(keys, [41, 29, 7, 3]) { connection.stats[key] = value }
                    self.assertECNSnapshotMatchesStatistics(connection)
                }
                self.wait(for: [expectation], timeout: 5.0)
            }
        )
    }

    func testECNSnapshotAfterPacketLoss() throws {
        QUICTestHarness().runQUICTest(
            blockSize: 10240,
            blockCount: 4,
            clientDrops: .init([0...0, 20...21]),
            afterData: { harness in
                let expectation = XCTestExpectation(description: "Validate ECN loss snapshot")
                harness.context.async {
                    defer { expectation.fulfill() }
                    guard let connection = harness.state?.clientInstance,
                        case .dataTransferSnapshot(let snapshot) = connection.getMetrics(
                            flow: .allFlows,
                            requestedNetworkMetric: .dataTransferSnapshot
                        )
                    else {
                        XCTFail("Missing QUIC connection or snapshot")
                        return
                    }
                    XCTAssertGreaterThan(connection.stats[.txLostPackets], 0)
                    XCTAssertGreaterThan(snapshot.sentTransportECNCapableLostPacketCount, 0)
                    self.assertECNSnapshotMatchesStatistics(connection)
                }
                self.wait(for: [expectation], timeout: 5.0)
            }
        )
    }

    func testQUICTestECNMarkedPacketsSentAndACKed() throws {
        QUICTestHarness().runQUICTest(
            dataBlock: Array("Hello World!".utf8),
            afterData: { harness in
                // Verify the pakets with ECN marking reached the other side
                let expectation = XCTestExpectation(description: "Wait to validate ECN")
                harness.context.async {
                    XCTAssertTrue(
                        harness.state?.serverInstance.stats[.ecnCapablePacketsAcknowledged] ?? 0 > 0,
                        "Server should have ACKed ECN marked packets"
                    )
                    XCTAssertTrue(
                        harness.state?.clientInstance.stats[.ecnCapablePacketsSent] ?? 0 > 0,
                        "Clients should have sent ECN marked packets"
                    )
                    if let state = harness.state {
                        self.assertECNSnapshotMatchesStatistics(state.clientInstance)
                        self.assertECNSnapshotMatchesStatistics(state.serverInstance)
                    } else {
                        XCTFail("Missing QUIC connection state")
                    }
                    expectation.fulfill()
                }
                self.wait(for: [expectation], timeout: 5.0)
            }
        )
    }

    func testQUICTestECNMarkedPacketsDisabled() throws {
        let clientOptions = QUICProtocol.options()
        clientOptions.connectionOptions.disableECN = true
        clientOptions.connectionOptions.disableECNEcho = true
        let serverOptions = QUICProtocol.options()
        serverOptions.connectionOptions.disableECN = true
        serverOptions.connectionOptions.disableECNEcho = true
        QUICTestHarness().runQUICTest(
            dataBlock: Array("Hello World!".utf8),
            clientOptions: clientOptions,
            serverOptions: serverOptions,
            afterData: { harness in
                // Verify the packets with ECN marking reached the other side
                let expectation = XCTestExpectation(description: "Wait to validate ECN")
                harness.context.async {
                    XCTAssertTrue(
                        harness.state?.serverInstance.stats[.ecnCapablePacketsAcknowledged] == 0,
                        "Server should NOT have ACKed ECN marked packets"
                    )
                    XCTAssertTrue(
                        harness.state?.clientInstance.stats[.ecnCapablePacketsSent] == 0,
                        "Clients should NOT have sent ECN marked packets"
                    )
                    if let state = harness.state {
                        self.assertECNSnapshotMatchesStatistics(state.clientInstance)
                        self.assertECNSnapshotMatchesStatistics(state.serverInstance)
                    } else {
                        XCTFail("Missing QUIC connection state")
                    }
                    expectation.fulfill()
                }
                self.wait(for: [expectation], timeout: 5.0)
            }
        )
    }
}
#endif
#endif
#endif
#endif
