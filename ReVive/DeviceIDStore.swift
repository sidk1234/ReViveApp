//
//  DeviceIDStore.swift
//  Recyclability
//

import Foundation

enum DeviceIDStore {
    private static let service = "revive.device"
    private static let account = "id"

    static var current: String {
        if let data = KeychainStore.read(service: service, account: account),
           let value = String(data: data, encoding: .utf8),
           !value.isEmpty {
            return value
        }

        let value = UUID().uuidString
        _ = KeychainStore.save(Data(value.utf8), service: service, account: account)
        return value
    }
}
