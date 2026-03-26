// Context Pressure — AI Context Window Monitor
// Copyright (c) 2026 Jason Nichols
// Licensed under the MIT License. See LICENSE file for details.

import Foundation

enum AppVersion {
    static let current = "1.0.0"
    static let build = "100"
    static let displayString = "v\(current)"

    // GitHub repo for update checks — set this once the repo is created
    static let githubOwner = "JNSec1199"
    static let githubRepo = "context-pressure"
    static let githubReleasesURL = "https://api.github.com/repos/\(githubOwner)/\(githubRepo)/releases/latest"
}
