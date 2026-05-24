//
//  OperatorJSON.swift
//  TelephoneBoothOperatorMobile
//
//  Shared JSON encoder/decoder configured to handle the operator's
//  ISO-8601-with-fractional-seconds timestamps.
//

import Foundation

public enum OperatorJSON {
    /// ISO-8601 with optional fractional seconds, supporting both
    /// `2025-04-12T14:32:00Z` and `2025-04-12T14:32:00.123Z`.
    nonisolated(unsafe) public static let isoFractional: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    nonisolated(unsafe) public static let isoBasic: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()

    public static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let raw = try container.decode(String.self)
            if let date = isoFractional.date(from: raw) ?? isoBasic.date(from: raw) {
                return date
            }
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Unsupported date format: \(raw)"
            )
        }
        return decoder
    }()

    public static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .custom { date, encoder in
            var container = encoder.singleValueContainer()
            try container.encode(isoFractional.string(from: date))
        }
        return encoder
    }()
}
