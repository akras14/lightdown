import AppKit
@testable import LightdownKit

@MainActor
func versionChecks(_ t: Checker) {
    t.group("version") {
        t.expect(AppVersion.build(from: ["CFBundleVersion": "57", "LightdownCommit": "a7e83e9"]), "57 · a7e83e9",
                 "build number and commit")
        t.expect(AppVersion.build(from: ["CFBundleVersion": "57", "LightdownCommit": "a7e83e9-dirty"]), "57 · a7e83e9-dirty",
                 "uncommitted changes show")
        t.expect(AppVersion.build(from: ["CFBundleVersion": "1"]), "1", "no commit outside a build.sh build")
    }

    t.group("about menu") {
        let about = MainMenu.build().items.first?.submenu?.items.first
        t.expect(about?.action, #selector(AppDelegate.showAbout(_:)), "About shows the build")
    }
}
