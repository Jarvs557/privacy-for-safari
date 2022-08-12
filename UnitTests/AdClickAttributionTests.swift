//
//  AdClickAttributionTests.swift
//  UnitTests
//
//  Copyright © 2022 DuckDuckGo. All rights reserved.
//
//  Licensed under the Apache License, Version 2.0 (the "License");
//  you may not use this file except in compliance with the License.
//  You may obtain a copy of the License at
//
//  http://www.apache.org/licenses/LICENSE-2.0
//
//  Unless required by applicable law or agreed to in writing, software
//  distributed under the License is distributed on an "AS IS" BASIS,
//  WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
//  See the License for the specific language governing permissions and
//  limitations under the License.
//

import XCTest
@testable import TrackerBlocking

class AdClickAttributionTests: XCTestCase, AdClickAttributionConfig, BlockerListManager, AdClickPixelFiring, AdClickContentBlockerReloading {

    var mockAttributionType = AttributionType.none
    var mockHasExemptionExpired = false
    var mockResourceIsOnAllowlist = false
    var blockerListManagerUpdatedCalled = false
    var pixelvendorDomainFromParameter: String?
    var pixelvendorDomainFromHeuristic: String?
    var adClickAllowListUsed = false
    var contentBlockerReloadCalled = false

    override func setUp() {
        super.setUp()

        AdClickAttributionExemptions.shared.vendorDomains = []
        AdClickAttributionExemptions.shared.allowList = []
    }

    func testWhen_HeuristicTakesTooLong_Then_DetectPixelIsStillFired() async throws {

        mockAttributionType = .heuristic

        let tab = MockTab(activePage: MockPage())
        let subject = AdClickAttribution<MockTab>(config: self,
                                                  pixelFiring: self,
                                                  blockerListManager: self,
                                                  contentBlockerReloader: self,
                                                  heuristicTimeoutInterval: 0.01)

        await subject.handlePageNavigationToURL(URL.any, inTab: tab)

        try await Task.sleep(nanoseconds: 1_000_000_000)

        await subject.pageFinishedLoading(URL.withDomain("test.com"), forTab: tab)

        XCTAssertEqual(nil, pixelvendorDomainFromParameter)
        XCTAssertEqual("test.com", pixelvendorDomainFromHeuristic)

    }

    func testWhen_AllowlistResourceIsObservedOnVendorForFirstTime_Then_PixelIsFired() async {
        mockAttributionType = .vendor(name: "addomain.com")
        mockResourceIsOnAllowlist = true

        let tab = MockTab(activePage: MockPage())
        let subject = AdClickAttribution<MockTab>(config: self, pixelFiring: self, blockerListManager: self, contentBlockerReloader: self)
        await subject.handlePageNavigationToURL(URL.any, inTab: tab)
        await subject.pageFinishedLoading(URL.withDomain("addomain.com"), forTab: tab)

        // First check that an unobserved vendor fires the pixel
        subject.firePixelForResourceIfNeeded(resourceURL: URL(string: "https://bat.bing.com/script.js")!,
                                             onPage: URL(string: "https://addomain.com")!)

        XCTAssertTrue(adClickAllowListUsed)

        // Check that already observed vendor does not fire pixel
        adClickAllowListUsed = false
        subject.firePixelForResourceIfNeeded(resourceURL: URL(string: "https://bat.bing.com/script.js")!,
                                             onPage: URL(string: "https://addomain.com")!)
        XCTAssertFalse(adClickAllowListUsed)

        // Now check that removing vendors clears the observed list
        AdClickAttributionExemptions.shared.vendorDomains = []

        subject.firePixelForResourceIfNeeded(resourceURL: URL(string: "https://bat.bing.com/script.js")!,
                                             onPage: URL(string: "https://addomain.com")!)

        XCTAssertTrue(adClickAllowListUsed)
    }

    func testWhen_AdDomainParameterPresent_And_HeuristicCompletes_Then_PixelFiresForNewVendorWithCorrectvendorDomainParams() async {
        mockAttributionType = .vendor(name: "addomain.com")

        let tab = MockTab(activePage: MockPage())
        let subject = AdClickAttribution<MockTab>(config: self, pixelFiring: self, blockerListManager: self, contentBlockerReloader: self)
        await subject.handlePageNavigationToURL(URL.any, inTab: tab)
        await subject.pageFinishedLoading(URL.withDomain("test.com"), forTab: tab)

        XCTAssertEqual("addomain.com", pixelvendorDomainFromParameter)
        XCTAssertEqual("test.com", pixelvendorDomainFromHeuristic)
    }

    func testWhen_NoAdDomainParameter_And_HeuristicCompletes_Then_PixelFiresForNewVendorWithCorrectvendorDomainParams() async {
        mockAttributionType = .heuristic

        let tab = MockTab(activePage: MockPage())
        let subject = AdClickAttribution<MockTab>(config: self, pixelFiring: self, blockerListManager: self, contentBlockerReloader: self)
        await subject.handlePageNavigationToURL(URL.any, inTab: tab)
        XCTAssertTrue(AdClickAttributionExemptions.shared.vendorDomains.isEmpty)

        await subject.pageFinishedLoading(URL.withDomain("test.com"), forTab: tab)

        XCTAssertNil(pixelvendorDomainFromParameter)
        XCTAssertEqual("test.com", pixelvendorDomainFromHeuristic)
    }

    func testWhen_PageNavigationIsToNonAdClickURL_Then_NoExemptionsApplied() async {
        let subject = AdClickAttribution<MockTab>(config: self, pixelFiring: self, blockerListManager: self, contentBlockerReloader: self)
        await subject.handlePageNavigationToURL(URL.any, inTab: MockTab(activePage: MockPage()))
        XCTAssertTrue(AdClickAttributionExemptions.shared.vendorDomains.isEmpty)
    }

    func testWhen_PageNavigationIsToAdClickURLWithDomain_Then_ExemptionsApplied() async {
        mockAttributionType = .vendor(name: "test.com")
        let subject = AdClickAttribution<MockTab>(config: self, pixelFiring: self, blockerListManager: self, contentBlockerReloader: self)
        await subject.handlePageNavigationToURL(URL.any, inTab: MockTab(activePage: MockPage()))
        XCTAssertTrue(AdClickAttributionExemptions.shared.vendorDomains.contains(where: { $0 == "test.com" }))
    }

    func testWhen_PageNavigationIsToAdClickURLWithNoDomain_Then_ExemptionsAppliedAfterHeuristicsSatisfied() async {
        mockAttributionType = .heuristic

        let tab = MockTab(activePage: MockPage())
        let subject = AdClickAttribution<MockTab>(config: self, pixelFiring: self, blockerListManager: self, contentBlockerReloader: self)
        await subject.handlePageNavigationToURL(URL.any, inTab: tab)
        XCTAssertTrue(AdClickAttributionExemptions.shared.vendorDomains.isEmpty)

        await subject.pageFinishedLoading(URL.withDomain("test.com"), forTab: tab)
        XCTAssertTrue(AdClickAttributionExemptions.shared.vendorDomains.contains(where: { $0 == "test.com" }))
    }

    func testWhen_PageNavigationIsToAdClickURLWithNoDomain_Then_ExemptionsNotAppliedAfterHeuristicsSatisfiedInDifferentTab() async {
        mockAttributionType = .heuristic
        let subject = AdClickAttribution<MockTab>(config: self, pixelFiring: self, blockerListManager: self, contentBlockerReloader: self)
        await subject.handlePageNavigationToURL(URL.any, inTab: MockTab(activePage: MockPage()))
        XCTAssertTrue(AdClickAttributionExemptions.shared.vendorDomains.isEmpty)

        await subject.pageFinishedLoading(URL.withDomain("test.com"), forTab: MockTab(activePage: MockPage()))
        XCTAssertFalse(AdClickAttributionExemptions.shared.vendorDomains.contains(where: { $0 == "test.com" }))
    }

    func testWhen_PageNavigationIsToAdClickURLWithNoDomain_Then_ExemptionsNotAppliedAfterHeuristicsTimeout() async throws {
        mockAttributionType = .heuristic

        let tab = MockTab(activePage: MockPage())
        let subject = AdClickAttribution<MockTab>(config: self, pixelFiring: self, blockerListManager: self, contentBlockerReloader: self)
        await subject.handlePageNavigationToURL(URL.any, inTab: tab)
        XCTAssertTrue(AdClickAttributionExemptions.shared.vendorDomains.isEmpty)

        try await Task.sleep(nanoseconds: 5_000_000_000)

        await subject.pageFinishedLoading(URL.withDomain("test.com"), forTab: tab)
        XCTAssertFalse(AdClickAttributionExemptions.shared.vendorDomains.contains(where: { $0 == "test.com" }))
    }

    func testWhen_ExpiredExemption_ThenOnPageNavigationDomainIsRemoved() async throws {
        AdClickAttributionExemptions.shared.vendorDomains = [ "test.com" ]
        mockAttributionType = .none

        let tab = MockTab(activePage: MockPage())
        let subject = AdClickAttribution<MockTab>(config: self, pixelFiring: self, blockerListManager: self, contentBlockerReloader: self)
        await subject.handlePageNavigationToURL(URL.any, inTab: tab)
        XCTAssertTrue(AdClickAttributionExemptions.shared.vendorDomains.isEmpty)

        await subject.pageFinishedLoading(URL.withDomain("non-matching.com"), forTab: tab)
        XCTAssertTrue(AdClickAttributionExemptions.shared.vendorDomains.isEmpty)
    }

    // MARK: mocks and default values

    var isEnabled: Bool = true
    var isHeuristicDetectionEnabled: Bool = true
    var isDomainDetectionEnabled: Bool = true
    var navigationExpiration: Double = 0.5
    var totalExpiration: Double = 72 * 60 * 60
    var linkFormats = [AdClickAttributionFeature.LinkFormat]()
    var allowlist = [AdClickAttributionFeature.AllowlistEntry]()

    func resourceIsOnAllowlist(_ url: URL) -> Bool {
        return mockResourceIsOnAllowlist
    }

    func attributionTypeForURL(_ url: URL) -> AttributionType {
        return mockAttributionType
    }

    func hasExemptionExpired(_ date: Date) -> Bool {
        return mockHasExemptionExpired
    }

    func update() {
        blockerListManagerUpdatedCalled = true
    }

    func fireAdClickAllowListUsed() {
        adClickAllowListUsed = true
    }

    func fireAdClickDetected(vendorDomainFromParameter: String?, vendorDomainFromHeuristic: String?) {
        pixelvendorDomainFromParameter = vendorDomainFromParameter
        pixelvendorDomainFromHeuristic = vendorDomainFromHeuristic
    }

    func reload() async {
        contentBlockerReloadCalled = true
    }

    class MockPage {
    }

    class MockTab: NSObject, Tabbing {

        let mockActivePage: MockPage

        init(activePage: MockPage) {
            self.mockActivePage = activePage
        }

        func activePage() async -> AdClickAttributionTests.MockPage? {
            return mockActivePage
        }
    }

}

fileprivate extension URL {

    static let any = URL(string: "https://example.com")!

    static func withDomain(_ domain: String) -> URL {
        return URL(string: "https://\(domain)")!
    }

}