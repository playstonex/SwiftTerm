//
//  FileTransferContext.swift
//  mRayon
//
//  Created by Lakr Aream on 2022/3/18.
//

import NSRemoteShell
import RayonModule
import SwiftUI

class FileTransferContext: ObservableObject, Identifiable, Equatable {
    var id: UUID = .init()

    var navigationTitle: String {
        machine.name
    }

    @Published var navigationSubtitle: String = ""

    let machine: RDMachine
    let identity: RDIdentity?
    var shell: NSRemoteShell = .init()
    var firstConnect: Bool = true
    var destroyedSession: Bool = false {
        didSet {
            shell.destroyPermanently()
        }
    }

    // not really represents the connection status in real time
    // but we check and tag this each time we operate
    @Published var connected: Bool = false
    @Published var processConnection: Bool = false

    @Published var currentDir: String = "/" {
        didSet {
            navigationSubtitle = currentDir
            // let the ui call us
        }
    }

    @Published var currentFileList: [RemoteFile] = []
    var currentUrl: URL {
        URL(fileURLWithPath: currentDir)
    }

    @Published var isProgressRunning: Bool = true { // bootstrap set
        didSet {
            debugPrint("sftp session progress setting \(isProgressRunning)")
        }
    }

    @Published var totalProgress: Progress = .init()
    @Published var currentProcessingFile: String = ""
    @Published var currentProgress: Progress = .init()
    @Published var currentHint: String = ""
    @Published var currentSpeed: Int = 0
    @Published var currentProgressCancelable = false
    var continueCurrentProgress: Bool = false
    @Published var pendingTransferCount: Int = 0

    enum ConflictPolicy: String {
        case rename
        case overwrite
        case skip
    }

    struct TransferTask: Identifiable, Hashable {
        enum Kind: Hashable {
            case upload(local: URL, remoteDirectory: URL)
            case download(remote: URL, localDirectory: URL)
        }

        let id: UUID
        let kind: Kind
        let createdAt: Date

        init(id: UUID = UUID(), kind: Kind, createdAt: Date = Date()) {
            self.id = id
            self.kind = kind
            self.createdAt = createdAt
        }
    }

    private var failedTransferQueue: [TransferTask] = [] {
        didSet {
            mainActor {
                self.pendingTransferCount = self.failedTransferQueue.count
            }
        }
    }

    struct RemoteFile: Identifiable, Equatable, Hashable {
        var id: RemoteFile { self }
        let base: URL
        let name: String
        let fstat: NSRemoteFile
    }

    // MARK: SHELL CONTEXT -

    init(machine: RDMachine, identity: RDIdentity? = nil) {
        self.machine = machine
        self.identity = identity
        currentDir = machine.fileTransferLoginPath
        DispatchQueue.global(qos: .userInitiated).async {
            self.processBootstrap()
        }
    }

    static func == (lhs: FileTransferContext, rhs: FileTransferContext) -> Bool {
        lhs.id == rhs.id
    }

    func setupShellData() {
        shell
            .setupConnectionHost(machine.remoteAddress)
            .setupConnectionPort(NSNumber(value: Int(machine.remotePort) ?? 0))
            .setupConnectionTimeout(RayonStore.shared.timeoutNumber)
    }

    func putInformation(_ str: String) {
        mainActor {
            self.currentHint = str
        }
    }

    func processBootstrap() {
        DispatchQueue.global(qos: .userInitiated).async {
            self.callConnect()
        }
    }

    func callConnect() {
        putInformation("Connecting...")
        mainActor { self.processConnection = true }
        defer { mainActor { self.processConnection = false } }
        setupShellData()

        debugPrint("\(self) \(#function) \(machine.id)")
        shell.requestConnectAndWait()
        guard shell.isConnected else {
            putInformation("Unable to connect for \(machine.remoteAddress):\(machine.remotePort)")
            mainActor { self.processShutdown() }
            return
        }

        if let idd = identity {
            idd.callAuthenticationWith(remote: shell)
        } else {
            var previousUsername: String?
            for identity in RayonStore.shared.identityGroupForAutoAuth {
                putInformation("[i] trying to authenticate with \(identity.shortDescription())")
                if let prev = previousUsername, prev != identity.username {
                    shell.requestDisconnectAndWait()
                    shell.requestConnectAndWait()
                }
                previousUsername = identity.username
                identity.callAuthenticationWith(remote: shell)
                if shell.isConnected, shell.isAuthenticated {
                    break
                }
            }
        }

        guard shell.isConnected, shell.isAuthenticated else {
            putInformation("Failed to authenticate connection, did you forget to add identity or enable auto authentication?")
            mainActor { self.processShutdown() }
            return
        }

        shell.requestConnectFileTransferAndWait()
        guard shell.isConnectedFileTransfer else {
            putInformation("Failed to setup file transfer protocol")
            mainActor { self.processShutdown() }
            return
        }

        debugPrint("sftp session for \(machine.name) is now connected")
        // don't tag progress because we will tag it at loadCurrentFileList
        mainActor { self.connected = true }
        loadCurrentFileList()
    }

    func processShutdown() {
        putInformation("Connection Closed")
        // you are in charge to cancel sftp operation at interface level
        // because sftp operations are in control blocks which are not canceled during fly
        // I may add a control later tho
        mainActor {
            self.connected = false
            self.currentFileList = []
            self.processConnection = false
            self.isProgressRunning = false
        }
        DispatchQueue.global().async { [weak shell] in
            shell?.requestDisconnectAndWait()
        }
    }

    func connectionAvailableCheckPassed() -> Bool {
        guard shell.isConnected,
              shell.isAuthenticated,
              shell.isConnectedFileTransfer
        else {
            processShutdown()
            return false
        }
        resetCurrentProgress()
        return true
    }

    func resetCurrentProgress() {
        mainActor { [self] in
            totalProgress = .init()
            currentProcessingFile = ""
            currentProgress = .init()
            currentHint = ""
            currentSpeed = 0
            currentProgressCancelable = false
        }
    }

    func loadCurrentFileList() {
        guard connectionAvailableCheckPassed() else { return }
        let currentDir = currentDir
        let currentUrl = currentUrl
        DispatchQueue.global().async { [self] in
            putInformation("Loading... \(currentDir)")
            mainActor { self.isProgressRunning = true }
            let files = shell.requestFileList(at: self.currentDir)
            var builder = [RemoteFile]()
            for file in files ?? [] {
                builder.append(.init(base: currentUrl, name: file.name, fstat: file))
            }
            putInformation("Load Complete")
            mainActor {
                self.isProgressRunning = false
                self.currentFileList = builder
            }
        }
    }

    func createFolder(with name: String) {
        guard connectionAvailableCheckPassed() else { return }
        let url = currentUrl.appendingPathComponent(name)
        DispatchQueue.global().async { [self] in
            putInformation("Creating Folder \(url.path)...")
            mainActor { self.isProgressRunning = true }
            let done = shell.requestCreateDirAndWait(url.path)
            if done {
                putInformation("Folder Created")
            } else {
                let error = shell.getLastFileTransferError()
                UIBridge.presentError(with: "Failed to Create")
                print("SFTP \(machine.name) Error: \(error ?? "Unknown")")
            }
            loadCurrentFileList()
        }
    }

    func navigate(path: String) {
        guard connectionAvailableCheckPassed() else { return }
        currentDir = path
        loadCurrentFileList()
    }

    private var conflictPolicy: ConflictPolicy {
        ConflictPolicy(rawValue: RayonStore.shared.fileTransferConflictPolicy) ?? .rename
    }

    private var rateLimitKBps: Int {
        RayonStore.shared.fileTransferRateLimitKBps
    }

    private func throttleIfNeeded(speed: Int) {
        guard rateLimitKBps > 0 else { return }
        let limit = rateLimitKBps * 1024
        guard speed > limit else { return }
        let ratio = min(Double(speed) / Double(limit), 4.0)
        let delay = UInt32(max(20_000, Int(200_000 * (ratio - 1))))
        usleep(delay)
    }

    private func buildUniqueLocalPath(initial: String) -> String {
        var target = initial
        let base = URL(fileURLWithPath: target)
        let ext = base.pathExtension
        var duplicate = 1
        while FileManager.default.fileExists(atPath: target) {
            duplicate += 1
            target = base.deletingPathExtension().path + ".\(duplicate)"
            if !ext.isEmpty { target += ".\(ext)" }
        }
        return target
    }

    private func resolveRemoteUploadPath(for localURL: URL, base: URL) -> String? {
        let filename = localURL.lastPathComponent
        let exists = (shell.requestFileList(at: base.path) ?? []).contains { $0.name == filename }

        if !exists {
            return base.appendingPathComponent(filename).path
        }

        switch conflictPolicy {
        case .skip:
            return nil
        case .overwrite:
            let path = base.appendingPathComponent(filename).path
            _ = shell.requestDelete(forFileAndWait: path, withProgressBlock: { _ in }, withContinuationHandler: { true })
            return path
        case .rename:
            var candidate = base.appendingPathComponent(filename).path
            let url = URL(fileURLWithPath: candidate)
            let ext = url.pathExtension
            var duplicate = 1
            let names = Set((shell.requestFileList(at: base.path) ?? []).map(\.name))
            while names.contains(URL(fileURLWithPath: candidate).lastPathComponent) {
                duplicate += 1
                candidate = url.deletingPathExtension().path + ".\(duplicate)"
                if !ext.isEmpty { candidate += ".\(ext)" }
            }
            return candidate
        }
    }

    private func enqueueFailedTransfer(_ task: TransferTask) {
        failedTransferQueue.append(task)
    }

    func resumeFailedTransfers() {
        guard !failedTransferQueue.isEmpty else { return }
        let pending = failedTransferQueue
        failedTransferQueue.removeAll()

        for task in pending {
            switch task.kind {
            case .upload(let local, let remoteDir):
                navigate(path: remoteDir.path)
                upload(urls: [local])
            case .download(let remote, let localDir):
                download(from: remote, toDir: localDir)
            }
        }
    }

    func syncLocalDirectoryToRemote(localDirectory: URL, remoteDirectory: String? = nil) {
        guard connectionAvailableCheckPassed() else { return }
        let base = remoteDirectory.map { URL(fileURLWithPath: $0) } ?? currentUrl
        let fm = FileManager.default
        guard let enumerator = fm.enumerator(at: localDirectory, includingPropertiesForKeys: [.isRegularFileKey]) else {
            return
        }
        let files: [URL] = enumerator.compactMap { item in
            guard let url = item as? URL else { return nil }
            let values = try? url.resourceValues(forKeys: [.isRegularFileKey])
            return values?.isRegularFile == true ? url : nil
        }

        if files.isEmpty { return }
        let maxConcurrent = max(1, RayonStore.shared.fileTransferMaxConcurrent)
        let semaphore = DispatchSemaphore(value: maxConcurrent)
        let group = DispatchGroup()

        for file in files {
            semaphore.wait()
            group.enter()
            DispatchQueue.global(qos: .userInitiated).async {
                self.upload(urls: [file])
                semaphore.signal()
                group.leave()
            }
        }
        group.wait()
        navigate(path: base.path)
    }

    func syncRemoteDirectoryToLocal(remoteDirectory: String? = nil, localDirectory: URL) {
        guard connectionAvailableCheckPassed() else { return }
        let path = remoteDirectory ?? currentDir
        let files = shell.requestFileList(at: path) ?? []
        for file in files {
            if file.isDirectory {
                continue
            }
            let remoteURL = URL(fileURLWithPath: path).appendingPathComponent(file.name)
            download(from: remoteURL, toDir: localDirectory)
        }
    }

    func upload(urls: [URL]) {
        guard connectionAvailableCheckPassed() else { return }
        let base = currentUrl
        continueCurrentProgress = true
        DispatchQueue.global().async { [self] in
            mainActor {
                self.isProgressRunning = true
                self.currentProgressCancelable = true
            }
            let total = urls.count
            var current = 0
            putInformation("Uploading...")
            for url in urls {
                defer { current += 1 }
                mainActor {
                    let progress = Progress(totalUnitCount: Int64(total))
                    progress.completedUnitCount = Int64(current)
                    self.totalProgress = progress
                }
                guard let targetPath = resolveRemoteUploadPath(for: url, base: base) else {
                    continue
                }
                let done = shell.requestUpload(
                    forFileAndWait: url.path,
                    toDirectory: URL(fileURLWithPath: targetPath).deletingLastPathComponent().path
                ) { file, progress, speed in
                    self.currentProcessingFile = file
                    self.currentProgress = progress
                    self.currentSpeed = speed
                    self.throttleIfNeeded(speed: speed)
                } withContinuationHandler: {
                    self.continueCurrentProgress
                }
                guard done else {
                    let error = shell.getLastFileTransferError()
                    UIBridge.presentError(with: "Error Occurred")
                    print("SFTP \(machine.name) Error: \(error ?? "Unknown")")
                    if RayonStore.shared.fileTransferResumeEnabled {
                        enqueueFailedTransfer(.init(kind: .upload(local: url, remoteDirectory: base)))
                    }
                    break
                }
                let uploadedName = url.lastPathComponent
                let desiredName = URL(fileURLWithPath: targetPath).lastPathComponent
                if desiredName != uploadedName {
                    let source = base.appendingPathComponent(uploadedName).path
                    let destination = base.appendingPathComponent(desiredName).path
                    _ = shell.requestRenameFileAndWait(source, withNewPath: destination)
                }
            }
            putInformation("Uploade Completed")
            loadCurrentFileList()
        }
    }

    func rename(from: URL, to: URL) {
        guard connectionAvailableCheckPassed() else { return }
        DispatchQueue.global().async { [self] in
            putInformation("Renameing...")
            mainActor { self.isProgressRunning = true }
            let done = shell.requestRenameFileAndWait(from.path, withNewPath: to.path)
            if done {
                putInformation("Renamed Successfully")
            } else {
                let error = shell.getLastFileTransferError()
                UIBridge.presentError(with: "Failed to Rename")
                print("SFTP \(machine.name) Error: \(error ?? "Unknown")")
            }
            loadCurrentFileList()
        }
    }

    func delete(item: URL) {
        guard connectionAvailableCheckPassed() else { return }
        continueCurrentProgress = true
        DispatchQueue.global().async { [self] in
            mainActor {
                self.isProgressRunning = true
                self.currentProgressCancelable = true
                self.currentProcessingFile = item.path
            }
            putInformation("Deleting...")
            let done = shell.requestDelete(
                forFileAndWait: item.path
            ) { file in
                self.currentProcessingFile = file
            } withContinuationHandler: {
                self.continueCurrentProgress
            }
            if done {
                putInformation("Uploade Completed")
            } else {
                let error = shell.getLastFileTransferError()
                UIBridge.presentError(with: "Error Occurred")
                print("SFTP \(machine.name) Error: \(error ?? "Unknown")")
            }
            loadCurrentFileList()
        }
    }

    func download(from: URL, toDir: URL) {
        let fromPath = from.path
        var to = toDir.path
        if !to.hasSuffix("/") { to += "/" }
        // now let's put that file name into to
        to += from.lastPathComponent
        if FileManager.default.fileExists(atPath: to) {
            switch conflictPolicy {
            case .skip:
                putInformation("Skipped \(from.lastPathComponent)")
                return
            case .overwrite:
                try? FileManager.default.removeItem(atPath: to)
            case .rename:
                to = buildUniqueLocalPath(initial: to)
            }
        }
        guard connectionAvailableCheckPassed() else { return }
        continueCurrentProgress = true
        DispatchQueue.global().async { [self] in
            mainActor {
                self.isProgressRunning = true
                self.currentProgressCancelable = true
            }
            putInformation("Downloading...")
            let done = shell.requestDownload(
                fromFileAndWait: fromPath,
                toLocalPath: to
            ) { file, progress, speed in
                self.currentProcessingFile = file
                self.currentProgress = progress
                self.currentSpeed = speed
                self.throttleIfNeeded(speed: speed)
            } withContinuationHandler: {
                self.continueCurrentProgress
            }
            if done {
                putInformation("Download Completed")
                mainActor {
                    // TODO: after download
                }
            } else {
                let error = shell.getLastFileTransferError()
                UIBridge.presentError(with: "Error Occurred")
                print("SFTP \(machine.name) Error: \(error ?? "Unknown")")
                if RayonStore.shared.fileTransferResumeEnabled {
                    enqueueFailedTransfer(.init(kind: .download(remote: from, localDirectory: toDir)))
                }
            }
            loadCurrentFileList()
        }
    }
}
