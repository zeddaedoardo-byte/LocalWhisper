import XCTest
@testable import LocalWhisper

@MainActor
final class LockTriggerResolutionTests: XCTestCase {
    private func makeStore(suite: String = UUID().uuidString) -> SettingsStore {
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return SettingsStore(defaults: defaults)
    }

    func testEmptyIDDisablesLock() {
        let store = makeStore()
        store.lockTriggerID = ""
        XCTAssertNil(AppState.resolveLockTrigger(store))
    }

    func testUnknownIDDoesNotFallBackToFn() {
        let store = makeStore()
        // Simulate version-skewed defaults: an ID that no longer matches
        // any known preset. Must NOT silently become fn.
        store.lockTriggerID = "ghost_trigger_from_old_build"
        XCTAssertNil(AppState.resolveLockTrigger(store))
    }

    func testCustomWithoutDataIsTreatedAsDisabled() {
        let store = makeStore()
        store.lockTriggerID = "custom"
        store.customLockTriggerKeycode = -1
        store.customLockTriggerFlags = 0
        XCTAssertNil(AppState.resolveLockTrigger(store))
    }

    func testCustomWithDataResolves() {
        let store = makeStore()
        store.lockTriggerID = "custom"
        store.customLockTriggerKeycode = 63
        store.customLockTriggerFlags = 0x880020 // fn + leftOption
        store.customLockTriggerLabel = "fn + option"
        let trigger = AppState.resolveLockTrigger(store)
        XCTAssertEqual(trigger?.id, "lock_custom")
    }

    func testKnownPresetIDResolves() {
        let store = makeStore()
        store.lockTriggerID = PushToTalkTrigger.cmdShift.id
        XCTAssertEqual(AppState.resolveLockTrigger(store)?.id, PushToTalkTrigger.cmdShift.id)
    }
}
