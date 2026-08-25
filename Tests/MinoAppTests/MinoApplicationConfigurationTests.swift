import Foundation
import Testing
@testable import MinoApp

@Test func standardExecutableWithoutInfoPlistRequiresMinoCloud() {
    #expect(MinoApplication.requiresLiveConfiguration(info: [:], environment: [:]))
}

@Test func explicitOfflineStandardRunMayUseTheLocalBackend() {
    #expect(!MinoApplication.requiresLiveConfiguration(
        info: [:],
        environment: ["MINO_BACKEND_MODE": "offline"]
    ))
}

@Test func debugProfilesNeverSilentlyCollapseIntoTheStandardOfflineIdentity() {
    #expect(MinoApplication.requiresLiveConfiguration(
        info: ["MinoBackendMode": "offline"],
        environment: ["MINO_CLIENT_PROFILE": "alice"]
    ))
}

@Test func executableScopedAgentMemoryKeepsTheEncryptedFilePairedWithItsKey() {
    let fingerprint = Data((0..<20).map(UInt8.init))

    #expect(ServiceContainer.agentMemoryFileName(executableFingerprint: nil) ==
        "agent-memory.json.enc")
    #expect(ServiceContainer.agentMemoryFileName(executableFingerprint: fingerprint) ==
        "agent-memory.executable.000102030405060708090a0b0c0d0e0f10111213.json.enc")
    #expect(ServiceContainer.localSecurityDirectoryName(executableFingerprint: fingerprint) ==
        "local-security.executable.000102030405060708090a0b0c0d0e0f10111213")
}
