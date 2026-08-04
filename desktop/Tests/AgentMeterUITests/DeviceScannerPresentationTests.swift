import AgentMeterUI
import Testing

@Test func scannerPresentationDistinguishesScanningFromAnEmptyResult() {
    let scanning = DeviceScannerPresentation(isScanning: true, hasDevices: false)
    #expect(scanning.emptyTitle == "Searching nearby")
    #expect(scanning.emptyDescription == "Keep the AgentMeter powered and close to this Mac.")
    #expect(scanning.scanButtonTitle == "Scanning…")
    #expect(scanning.showsScanProgress)

    let completed = DeviceScannerPresentation(isScanning: false, hasDevices: false)
    #expect(completed.emptyTitle == "No AgentMeters found")
    #expect(completed.emptyDescription == "Make sure the display is powered on and not connected to another Mac, then scan again.")
    #expect(completed.scanButtonTitle == "Scan Again")
    #expect(completed.showsScanProgress == false)
}

@Test func communityBridgeLaunchIncludesItsOwningApplicationProcess() {
    let arguments = BridgeServiceController.communityBridgeArguments(
        configurationPath: "/tmp/config.toml",
        ipcPath: "/tmp/bridge.sock",
        parentPID: 2468
    )

    #expect(arguments == [
        "run",
        "--config", "/tmp/config.toml",
        "--ipc-path", "/tmp/bridge.sock",
        "--parent-pid", "2468",
    ])
}
