//
//  DeepLinkIdentifier.swift
//  TelephoneBoothOperatorMobile
//

import Foundation

enum DeepLinkIdentifier {
    static func normalized(_ value: String) -> String? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard isValid(trimmed) else { return nil }
        return trimmed
    }

    static func isValid(_ value: String) -> Bool {
        guard !value.isEmpty,
              value == value.trimmingCharacters(in: .whitespacesAndNewlines),
              value != ".",
              value != "..",
              !value.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains) else {
            return false
        }
        return !value.contains("/") && !value.contains("\\")
            && !value.contains("?") && !value.contains("#")
    }
}
