//
//  Secrets+Supabase.swift
//  Recyclability
//

import Foundation

extension Secrets {
    static var supabaseURL: String {
        value(for: "SUPABASE_URL")
    }

    static var supabaseAnonKey: String {
        value(for: "SUPABASE_ANON_KEY")
    }

    static var supabaseRedirectScheme: String {
        "recai"
    }
}
