import AppKit

if CommandLine.arguments.contains("--self-test") {
    do {try runTests();exit(0)} catch {fputs("FAIL: \(error)\n",stderr);exit(1)}
}
let app=NSApplication.shared
let delegate=AppDelegate()
app.delegate=delegate
app.run()
