import Foundation

@main struct QueryTests {
    static func main() {
        do {try runTests()} catch {fputs("FAIL: \(error)\n",stderr);exit(1)}
    }
}
