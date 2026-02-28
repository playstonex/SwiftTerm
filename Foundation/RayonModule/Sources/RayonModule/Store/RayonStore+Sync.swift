import DataSync
import Foundation

public extension RayonStore {
    @MainActor
    func configureAutoSync() {
        AutoSyncManager.shared.registerAutoSyncHandler { [weak self] in
            guard let self = self else { return }
            await self.syncAllDataToCloud(reason: "auto")
        }
    }

    @MainActor
    func syncAllDataToCloud(reason: String = "manual") async {
        createSyncSnapshot(reason: reason)

        let machines = machineGroup.machines
        let identities = identityGroup.identities
        let snippets = snippetGroup.snippets
        let settings = [buildSettingsSyncPayload()]

        if #available(macOS 12.0, iOS 15.0, *) {
            await AutoSyncManager.shared.sync(items: machines)
            await AutoSyncManager.shared.sync(items: identities)
            await AutoSyncManager.shared.sync(items: snippets)
            await AutoSyncManager.shared.sync(items: settings)
        }
    }
}
