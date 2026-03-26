// Context Pressure — AI Context Window Monitor
// Copyright (c) 2026 Jason Nichols
// Licensed under the MIT License. See LICENSE file for details.

import Foundation

/// Checks GitHub Releases API for newer versions of the app.
@MainActor
final class UpdateChecker: ObservableObject {
    @Published var latestVersion: String?
    @Published var downloadURL: URL?
    @Published var isChecking: Bool = false
    @Published var errorMessage: String?

    func checkForUpdates() {
        guard !isChecking else { return }
        isChecking = true
        errorMessage = nil
        latestVersion = nil
        downloadURL = nil

        guard let url = URL(string: AppVersion.githubReleasesURL) else {
            errorMessage = "Invalid update URL"
            isChecking = false
            return
        }

        var request = URLRequest(url: url)
        request.setValue("application/vnd.github.v3+json", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 10

        URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
            Task { @MainActor [weak self] in
                guard let self = self else { return }
                self.isChecking = false

                if let error = error {
                    self.errorMessage = "Network error: \(error.localizedDescription)"
                    return
                }

                guard let httpResponse = response as? HTTPURLResponse else {
                    self.errorMessage = "Invalid response"
                    return
                }

                if httpResponse.statusCode == 404 {
                    self.errorMessage = "No releases found — push your first release to GitHub"
                    return
                }

                guard httpResponse.statusCode == 200, let data = data else {
                    self.errorMessage = "HTTP \(httpResponse.statusCode)"
                    return
                }

                guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                    self.errorMessage = "Failed to parse response"
                    return
                }

                // Extract version from tag_name (e.g., "v1.0.1" -> "1.0.1")
                guard let tagName = json["tag_name"] as? String else {
                    self.errorMessage = "No version tag found"
                    return
                }

                let version = tagName.hasPrefix("v") ? String(tagName.dropFirst()) : tagName
                self.latestVersion = version

                // Find the .zip or .app asset download URL
                if let assets = json["assets"] as? [[String: Any]] {
                    for asset in assets {
                        let name = asset["name"] as? String ?? ""
                        if name.hasSuffix(".zip") || name.hasSuffix(".app") {
                            if let dlURL = asset["browser_download_url"] as? String {
                                self.downloadURL = URL(string: dlURL)
                                break
                            }
                        }
                    }
                }

                // Fallback to the release page if no binary asset
                if self.downloadURL == nil {
                    if let htmlURL = json["html_url"] as? String {
                        self.downloadURL = URL(string: htmlURL)
                    }
                }
            }
        }.resume()
    }
}
