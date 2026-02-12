//
//  LocationManager.swift
//  Recyclability
//

import CoreLocation
import SwiftUI
import Combine
import Foundation

@MainActor
final class LocationManager: NSObject, ObservableObject, CLLocationManagerDelegate {
    @Published var authorizationStatus: CLAuthorizationStatus
    @Published var lastLocation: CLLocation?
    @Published var postalCode: String = ""
    @Published var locality: String = ""
    @Published var administrativeArea: String = ""
    @Published var countryCode: String = ""
    @Published var errorMessage: String?
    @Published var isPreciseLocationAuthorized: Bool

    private let manager = CLLocationManager()
    private let geocoder = CLGeocoder()
    private var locationUpdateTask: Task<Void, Never>?
    private let targetAccuracy: CLLocationAccuracy = 120
    private let maxAcceptableAccuracy: CLLocationAccuracy = 500
    private let maxLocationAge: TimeInterval = 10
    private let maxUsableLocationAge: TimeInterval = 300
    private var isResolvingLocation = false
    private var preciseRequestFailed = false
    override init() {
        authorizationStatus = manager.authorizationStatus
        isPreciseLocationAuthorized = manager.accuracyAuthorization == .fullAccuracy
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyBest
        manager.distanceFilter = 10
    }

    var usableLocation: CLLocation? {
        guard authorizationStatus == .authorizedAlways || authorizationStatus == .authorizedWhenInUse else { return nil }
        guard isPreciseLocationAuthorized else { return nil }
        guard let location = lastLocation else { return nil }
        guard location.horizontalAccuracy <= maxAcceptableAccuracy else { return nil }
        guard abs(location.timestamp.timeIntervalSinceNow) <= maxUsableLocationAge else { return nil }
        return location
    }

    func requestLocation() {
        errorMessage = nil
        isResolvingLocation = true
        preciseRequestFailed = false
        lastLocation = nil
        clearResolvedAddress()
        switch manager.authorizationStatus {
        case .notDetermined:
            manager.requestWhenInUseAuthorization()
        case .authorizedAlways, .authorizedWhenInUse:
            requestPreciseLocationIfNeeded()
            beginUpdatingLocation()
        case .denied, .restricted:
            errorMessage = "Location access is disabled. Enter ZIP manually."
        @unknown default:
            errorMessage = "Location access unavailable."
        }
    }

    func refreshLocationIfAuthorized() {
        switch manager.authorizationStatus {
        case .authorizedAlways, .authorizedWhenInUse:
            errorMessage = nil
            isResolvingLocation = true
            preciseRequestFailed = false
            lastLocation = nil
            clearResolvedAddress()
            requestPreciseLocationIfNeeded()
            beginUpdatingLocation()
        default:
            break
        }
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        authorizationStatus = manager.authorizationStatus
        isPreciseLocationAuthorized = manager.accuracyAuthorization == .fullAccuracy
        if authorizationStatus == .authorizedAlways || authorizationStatus == .authorizedWhenInUse {
            isResolvingLocation = true
            preciseRequestFailed = false
            requestPreciseLocationIfNeeded()
            beginUpdatingLocation()
        } else if authorizationStatus == .denied || authorizationStatus == .restricted {
            lastLocation = nil
            clearResolvedAddress()
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        let fresh = locations
            .filter { $0.horizontalAccuracy >= 0 }
            .filter { abs($0.timestamp.timeIntervalSinceNow) <= maxLocationAge }
            .sorted { $0.horizontalAccuracy < $1.horizontalAccuracy }
            .first

        guard let location = fresh else {
            if !isResolvingLocation {
                errorMessage = "Unable to get location."
            }
            return
        }

        guard manager.accuracyAuthorization == .fullAccuracy else { return }
        guard location.horizontalAccuracy <= maxAcceptableAccuracy else { return }

        lastLocation = location
        reverseGeocodeWithCLGeocoder(location)

        if location.horizontalAccuracy <= targetAccuracy, !postalCode.isEmpty {
            stopUpdatingLocation()
        }
    }

    private func beginUpdatingLocation() {
        manager.startUpdatingLocation()
        locationUpdateTask?.cancel()
        locationUpdateTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 15_000_000_000)
            guard let self else { return }
            if self.isResolvingLocation && self.postalCode.isEmpty {
                if self.manager.accuracyAuthorization == .reducedAccuracy || self.preciseRequestFailed {
                    self.errorMessage = "Enable Precise Location to auto-detect ZIP."
                } else {
                    self.errorMessage = "Couldn't determine ZIP. Enter manually."
                }
            }
            self.isResolvingLocation = false
            self.stopUpdatingLocation()
        }
    }

    private func stopUpdatingLocation() {
        manager.stopUpdatingLocation()
        locationUpdateTask?.cancel()
        locationUpdateTask = nil
    }

    private func requestPreciseLocationIfNeeded() {
        guard manager.accuracyAuthorization == .reducedAccuracy else { return }
        manager.requestTemporaryFullAccuracyAuthorization(withPurposeKey: "PreciseLocation") { [weak self] error in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.isPreciseLocationAuthorized = self.manager.accuracyAuthorization == .fullAccuracy
                if error != nil {
                    self.preciseRequestFailed = true
                }
            }
        }
    }

    private func reverseGeocodeWithCLGeocoder(_ location: CLLocation) {
        geocoder.cancelGeocode()
        geocoder.reverseGeocodeLocation(location) { [weak self] placemarks, error in
            Task { @MainActor [weak self] in
                guard let self else { return }
                if let placemark = placemarks?.first, error == nil {
                    self.postalCode = placemark.postalCode ?? ""
                    self.locality = placemark.locality ?? ""
                    self.administrativeArea = placemark.administrativeArea ?? ""
                    self.countryCode = placemark.isoCountryCode ?? ""
                    if self.postalCode.isEmpty {
                        // keep resolving until timeout; don't flash error
                    } else {
                        self.errorMessage = nil
                        self.isResolvingLocation = false
                        self.preciseRequestFailed = false
                        if (self.lastLocation?.horizontalAccuracy ?? .greatestFiniteMagnitude) <= self.targetAccuracy {
                            self.stopUpdatingLocation()
                        }
                    }
                } else {
                    self.clearResolvedAddress()
                    // keep resolving until timeout; don't flash error
                }
            }
        }
    }

    private func clearResolvedAddress() {
        postalCode = ""
        locality = ""
        administrativeArea = ""
        countryCode = ""
    }


    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        lastLocation = nil
        clearResolvedAddress()
        stopUpdatingLocation()
        errorMessage = "Location error. Enter ZIP manually."
        isResolvingLocation = false
        preciseRequestFailed = false
    }
}
