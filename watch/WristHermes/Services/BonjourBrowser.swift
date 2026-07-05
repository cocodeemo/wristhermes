import Foundation
import Network
import Combine

/// Bonjour/mDNS browser that discovers WristHermes Bridge on the local network.
/// Call `startBrowsing()` on appear and `stopBrowsing()` on disappear.
class BonjourBrowser: ObservableObject {
    @Published var discoveredURLs: [URL] = []
    @Published var isScanning = false

    private var browser: NWBrowser?

    func startBrowsing() {
        guard !isScanning else { return }
        isScanning = true

        let parameters = NWParameters()
        parameters.includePeerToPeer = true

        browser = NWBrowser(
            for: .bonjour(type: "_http._tcp", domain: "local"),
            using: parameters
        )

        browser?.browseResultsChangedHandler = { [weak self] results, _ in
            let wristhermes = results.filter { result in
                result.endpoint.debugDescription.contains("WristHermes")
            }
            // Resolve each discovered endpoint to a usable URL
            Task {
                var urls: [URL] = []
                for result in wristhermes {
                    if let url = await self?.resolveEndpoint(result) {
                        urls.append(url)
                    }
                }
                await MainActor.run {
                    self?.discoveredURLs = urls
                    if !urls.isEmpty { self?.isScanning = false }
                }
            }
        }

        browser?.start(queue: .main)
    }

    func stopBrowsing() {
        browser?.cancel()
        browser = nil
        isScanning = false
    }

    /// Extract a reachable HTTP URL from a Bonjour result
    private func resolveEndpoint(_ result: NWBrowser.Result) async -> URL? {
        // Extract host and port directly from the browser result's endpoint
        switch result.endpoint {
        case .hostPort(let host, let port):
            let hostStr: String
            switch host {
            case .ipv4(let addr):
                hostStr = addr.debugDescription
            case .ipv6(let addr):
                hostStr = addr.debugDescription
            case .name(let name, _):
                hostStr = name
            @unknown default:
                return nil
            }
            return URL(string: "http://\(hostStr):\(port.rawValue)")
        default:
            return nil
        }
    }
}
