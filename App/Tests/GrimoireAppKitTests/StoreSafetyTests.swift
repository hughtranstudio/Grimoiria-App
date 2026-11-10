import Foundation
import Testing
@testable import GrimoireAppKit

private func safetyFolder() throws -> URL {
    let url = FileManager.default.temporaryDirectory.appending(path: "store-safety-\(UUID().uuidString)", directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}

@Test func schemaStampLifecycle() throws {
    let folder = try safetyFolder()
    #expect(StoreSchema.check(storeExists: false, folder: folder) == .fresh)
    // A store from before stamps existed is version 1.
    #expect(StoreSchema.check(storeExists: true, folder: folder) == .ok)
    try StoreSchema.stamp(folder: folder, build: "test")
    #expect(StoreSchema.check(storeExists: true, folder: folder) == .ok)
    // A later build knows version 2: the version-1 store is older to it.
    #expect(StoreSchema.check(storeExists: true, folder: folder, current: 2) == .older(1))
    try StoreSchema.stamp(folder: folder, build: "next", current: 2)
    // Back on the version-1 build, the store is newer and must not be written.
    #expect(StoreSchema.check(storeExists: true, folder: folder) == .newer(2))
    // Stamping from the older build never lowers the version.
    try StoreSchema.stamp(folder: folder, build: "test")
    #expect(StoreSchema.check(storeExists: true, folder: folder) == .newer(2))
}

@Test func rescueCopiesEveryStoreFile() throws {
    let folder = try safetyFolder()
    let store = folder.appending(path: "Grimoire.store")
    try Data("main".utf8).write(to: store)
    try Data("wal".utf8).write(to: URL(fileURLWithPath: store.path + "-wal"))
    let now = Date(timeIntervalSince1970: 1_800_000_000)
    let aside = try StoreRescue.copyAside(store, now: now)
    #expect(try Data(contentsOf: aside.appending(path: "Grimoire.store")) == Data("main".utf8))
    #expect(try Data(contentsOf: aside.appending(path: "Grimoire.store-wal")) == Data("wal".utf8))
    // The originals stay where they were.
    #expect(FileManager.default.fileExists(atPath: store.path))
    // A second rescue in the same second gets its own folder.
    #expect(try StoreRescue.copyAside(store, now: now) != aside)
}

@Test func healthBlocksPruningOnUnreadableRows() {
    var health = StoreHealth()
    #expect(health.isHealthy && health.canPrune && health.banner == nil)
    health.saveError = "disk full"
    #expect(health.canPrune)
    #expect(health.banner?.contains("disk full") == true)
    health.unreadable = [.init(kind: "entry", id: "01K", reason: "bad")]
    #expect(!health.canPrune)
    #expect(health.banner?.contains("1 record could not be read") == true)
}
