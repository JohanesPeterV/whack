import Foundation

extension Bundle {
    /// Standard signed .app resource placement, with SwiftPM's accessor for `swift run`.
    static var whackAssets: Bundle {
        if let url = Bundle.main.resourceURL?.appendingPathComponent("Whack_Whack.bundle"),
           let bundle = Bundle(url: url) { return bundle }
        return .module
    }
}
