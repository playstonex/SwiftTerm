//
//  Util.swift
//  mRayon
//
//  Created by Lakr Aream on 2022/3/3.
//

import Foundation
import LocalAuthentication
import RayonModule
import SwiftUI
import UIKit

let preferredPopOverSize = CGSize(width: 700, height: 555)

enum RayonUtil {
    private static func deviceHasPassword() -> Bool {
        LAContext().canEvaluatePolicy(.deviceOwnerAuthentication, error: nil)
    }

    typealias DeviceOwnershipCheckSuccess = Bool
    static func deviceOwnershipAuthenticate(onComplete: @escaping (DeviceOwnershipCheckSuccess) -> Void) {
        Task.detached(priority: .userInitiated) {
            guard deviceHasPassword() else {
                await MainActor.run {
                    onComplete(true)
                }
                return
            }
            let context = LAContext()
            let reason = "Performing privacy sensitive operation requires device ownership authenticated"
            let (success, errorDescription) = await withCheckedContinuation { continuation in
                context.evaluatePolicy(
                    .deviceOwnerAuthentication,
                    localizedReason: reason
                ) { success, error in
                    continuation.resume(returning: (success, error?.localizedDescription ?? "Unknown Error"))
                }
            }

            await MainActor.run {
                if success {
                    debugPrint(#function, "success")
                    onComplete(true)
                } else {
                    debugPrint(#function, "failure", errorDescription)
                    onComplete(false)
                }
            }
        }
    }

    static func selectIdentity() async -> RDIdentity.ID? {
        debugPrint("Picking Identity")

        return await withCheckedContinuation { continuation in
            Task { @MainActor in
                let picker = NavigationStack {
                    PickIdentityView {
                        continuation.resume(returning: $0)
                    }
                }
                .expended()
                let controller = UIHostingController(rootView: picker)
                controller.isModalInPresentation = true
                controller.modalTransitionStyle = .coverVertical
                controller.modalPresentationStyle = .formSheet
                controller.preferredContentSize = preferredPopOverSize
                UIWindow.shutUpKeyWindow?
                    .topMostViewController?
                    .present(controller, animated: true, completion: nil)
            }
        }
    }

    static func selectMachine(canSelectMany: Bool = true) async -> [RDMachine.ID] {
        debugPrint("Picking Machine")

        return await withCheckedContinuation { continuation in
            Task { @MainActor in
                let picker = NavigationStack {
                    PickMachineView(completion: {
                        continuation.resume(returning: $0)
                    }, canSelectMany: canSelectMany)
                }
                .expended()
                let controller = UIHostingController(rootView: picker)
                controller.isModalInPresentation = true
                controller.modalTransitionStyle = .coverVertical
                controller.modalPresentationStyle = .formSheet
                controller.preferredContentSize = preferredPopOverSize
                UIWindow.shutUpKeyWindow?
                    .topMostViewController?
                    .present(controller, animated: true, completion: nil)
            }
        }
    }

    static func selectOneMachine() async -> [RDMachine.ID] {
        await selectMachine(canSelectMany: false)
    }

    static func createExecuteFor(snippet: RDSnippet) {
        Task(priority: .userInitiated) { @MainActor in
            let machineIds = await selectMachine()
            debugPrint(machineIds)
            guard !machineIds.isEmpty else {
                return
            }

            try? await Task.sleep(nanoseconds: 600_000_000)
            let runner = NavigationStack {
                let context = SnippetExecuteContext(snippet: snippet, machineGroup: machineIds.map { machineId in
                    RayonStore.shared.machineGroup[machineId]
                })
                SnippetExecuteView(context: context)
            }
            .expended()
            .navigationBarTitleDisplayMode(.inline)
            let controller = UIHostingController(rootView: runner)
            controller.isModalInPresentation = true
            controller.modalTransitionStyle = .coverVertical
            controller.modalPresentationStyle = .formSheet
            controller.preferredContentSize = preferredPopOverSize
            UIWindow.shutUpKeyWindow?
                .topMostViewController?
                .present(controller, animated: true, completion: nil)
        }
    }
}

extension String {
    var isValidAsFilename: Bool {
        var invalidCharacters = CharacterSet(charactersIn: ":/")
        invalidCharacters.formUnion(.newlines)
        invalidCharacters.formUnion(.illegalCharacters)
        invalidCharacters.formUnion(.controlCharacters)
        return rangeOfCharacter(from: invalidCharacters) == nil && !isEmpty
    }
}
