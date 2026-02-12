//
//  Secrets+Google.swift
//  Recyclability
//

import Foundation

extension Secrets {
    static var googleIOSClientID: String {
        value(for: "GOOGLE_IOS_CLIENT_ID")
    }

    static var googleWebClientID: String {
        value(for: "GOOGLE_WEB_CLIENT_ID")
    }

    static var googleReversedClientID: String {
        value(for: "GOOGLE_REVERSED_CLIENT_ID")
    }
}
