//
//  UpdateChecker.swift
//  ProfessorNotch
//
//  A dependency-free, user-initiated update check. It queries GitHub's public
//  Releases API only when the user taps "Check for Updates" (no background
//  polling, no telemetry — nothing is sent, we just read the public release
//  list), compares the latest release tag to this build's version, and offers
//  a link to the download page. This is the only place besides optional album
//  art that touches the network, and it never runs on its own.
//

import Foundation

@MainActor
@Observable
final class UpdateChecker {
    static let shared = UpdateChecker()
    private init() {}

    enum State: Equatable {
        case idle
        case checking
        case upToDate
        case available(version: String, url: URL)
        case failed
    }

    private(set) var state: State = .idle

    private static let owner = "yunusemrekoyun"
    private static let repo = "ProfessorNotch"
    private static let apiURL = URL(string: "https://api.github.com/repos/\(owner)/\(repo)/releases/latest")!
    static let releasesPage = URL(string: "https://github.com/\(owner)/\(repo)/releases/latest")!

    var currentVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
    }

    func check() async {
        state = .checking
        var request = URLRequest(url: Self.apiURL)
        request.timeoutInterval = 12
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        do {
            let (data, response) = try await URLSession(configuration: .ephemeral).data(for: request)
            guard let http = response as? HTTPURLResponse else { state = .failed; return }
            if http.statusCode == 404 { state = .upToDate; return }   // no releases published yet
            guard http.statusCode == 200 else { state = .failed; return }
            let release = try JSONDecoder().decode(GitHubRelease.self, from: data)
            let latest = release.tagName.trimmingCharacters(in: CharacterSet(charactersIn: "vV "))
            if Self.isNewer(latest, than: currentVersion) {
                state = .available(version: latest,
                                   url: URL(string: release.htmlURL) ?? Self.releasesPage)
            } else {
                state = .upToDate
            }
        } catch {
            state = .failed
        }
    }

    private struct GitHubRelease: Decodable {
        let tagName: String
        let htmlURL: String
        enum CodingKeys: String, CodingKey {
            case tagName = "tag_name"
            case htmlURL = "html_url"
        }
    }

    /// Compares dotted numeric versions (e.g. "1.2" vs "1.10"); true if a > b.
    private static func isNewer(_ a: String, than b: String) -> Bool {
        let pa = a.split(separator: ".").map { Int($0) ?? 0 }
        let pb = b.split(separator: ".").map { Int($0) ?? 0 }
        for i in 0..<max(pa.count, pb.count) {
            let x = i < pa.count ? pa[i] : 0
            let y = i < pb.count ? pb[i] : 0
            if x != y { return x > y }
        }
        return false
    }
}
