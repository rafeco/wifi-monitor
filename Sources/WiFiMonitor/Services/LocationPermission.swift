import CoreLocation

/// Requests Location Services authorization, which macOS 14+ requires before
/// CoreWLAN will report the WiFi SSID/BSSID. Kept as its own NSObject because
/// CLLocationManagerDelegate requires NSObject conformance, whereas the
/// services that consume the SSID are plain @Observable classes.
final class LocationPermission: NSObject, CLLocationManagerDelegate {
    private let manager = CLLocationManager()

    /// Prompt for authorization if the user hasn't decided yet. Safe to call
    /// repeatedly; the system only shows the prompt once.
    func request() {
        manager.delegate = self
        if manager.authorizationStatus == .notDetermined {
            manager.requestWhenInUseAuthorization()
        }
    }

    // The manager needs a delegate to deliver authorization changes; SSID reads
    // simply start succeeding once access is granted, so nothing to do here.
    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {}
}
