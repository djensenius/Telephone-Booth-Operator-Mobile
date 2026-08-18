//
//  ThermalClientTests.swift
//  TBOperatorMobileTests
//

import XCTest
@testable import TBOperatorMobile

final class ThermalClientTests: XCTestCase {
    func testCurrentComponentsEndpointPath() throws {
        let request = ThermalEndpoint.currentComponents
        let url = try request.url(relativeTo: URL(string: "https://operator.example")!)

        XCTAssertEqual(request.path, "/v1/system/components/current")
        XCTAssertTrue(request.queryItems.isEmpty)
        XCTAssertEqual(url.absoluteString, "https://operator.example/v1/system/components/current")
    }

    func testCurrentWeatherEndpointBuildsExpectedURLAndQuery() throws {
        let request = try ThermalEndpoint.currentWeather(boothId: " booth id/01 ")
        let url = try request.url(relativeTo: URL(string: "https://operator.example")!)
        let queryItems = try XCTUnwrap(
            URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems
        )

        XCTAssertEqual(request.path, "/v1/system/weather/current")
        XCTAssertEqual(queryItems.map(\.name), ["boothId"])
        XCTAssertEqual(queryItems.first?.value, "booth id/01")
        XCTAssertEqual(url.path, "/v1/system/weather/current")
    }

    func testCurrentWeatherEndpointRejectsBlankBooth() {
        XCTAssertThrowsError(try ThermalEndpoint.currentWeather(boothId: "  ")) { error in
            guard case OperatorError.invalidURL = error else {
                return XCTFail("Expected OperatorError.invalidURL, got \(error)")
            }
        }
    }

    func testThermalHistoryEndpointBuildsExpectedURLAndQuery() throws {
        let from = Date(timeIntervalSince1970: 1_786_968_000)
        let end = Date(timeIntervalSince1970: 1_787_054_400)
        let query = ThermalHistoryQuery(
            boothId: "booth id/with spaces",
            componentId: "router/main",
            from: from,
            end: end,
            stepSeconds: 1
        )

        let request = try ThermalEndpoint.history(query: query)
        let url = try request.url(relativeTo: URL(string: "https://operator.example/base")!)
        let queryItems = try XCTUnwrap(
            URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems
        )
        let values = Dictionary(uniqueKeysWithValues: queryItems.map { ($0.name, $0.value) })

        XCTAssertEqual(url.path, "/base/v1/system/thermals/history")
        XCTAssertEqual(values["boothId"], "booth id/with spaces")
        XCTAssertEqual(values["componentId"], "router/main")
        XCTAssertEqual(values["from"], OperatorJSON.iso8601String(from: from))
        XCTAssertEqual(values["to"], OperatorJSON.iso8601String(from: end))
        XCTAssertEqual(values["stepSeconds"], "15")
        XCTAssertTrue(url.absoluteString.contains("booth%20id/with%20spaces"))
    }

    func testThermalHistoryEndpointRejectsBlankBooth() {
        let query = ThermalHistoryQuery(
            boothId: "   ",
            from: Date(timeIntervalSince1970: 1),
            end: Date(timeIntervalSince1970: 2),
            stepSeconds: 15
        )

        XCTAssertThrowsError(try ThermalEndpoint.history(query: query)) { error in
            guard case OperatorError.invalidURL = error else {
                return XCTFail("Expected OperatorError.invalidURL, got \(error)")
            }
        }
    }
}
