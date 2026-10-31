//
//  OrientationHelper.swift
//  VoidLink
//
//  Created by True砖家 on 2024/7/12.
//  Copyright © 2024 True砖家 on Bilibili. All rights reserved.
//


import Foundation

import UIKit
  
@objc class OrientationHelper: NSObject {
    /// Navigation always rotates; the old orientation field now controls local
    /// streaming only. Start that separate preference locked to landscape.
    @objc static func configureStreamRotationDefault() {
#if os(tvOS)
        return
#else
        let defaults = UserDefaults.standard
        let migrationKey = "IndependentStreamRotationPreferenceV1"
        guard !defaults.bool(forKey: migrationKey) else { return }
        let dataManager = DataManager()
        guard let settings = dataManager.retrieveSettings() else { return }
        settings.unlockDisplayOrientation = false
        dataManager.saveData()
        defaults.set(true, forKey: migrationKey)
#endif
    }

    @objc(allowedOrientationsFor:)
    static func allowedOrientations(for controller: UIViewController) -> UIInterfaceOrientationMask {
#if os(tvOS)
        return .landscape
#else
        let window = controller.viewIfLoaded?.window ?? controller.presentingViewController?.viewIfLoaded?.window
        func revealController(in root: UIViewController?) -> SWRevealViewController? {
            guard let root else { return nil }
            if let reveal = root as? SWRevealViewController { return reveal }
            return root.children.lazy.compactMap { revealController(in: $0) }.first
        }
        if let root = revealController(in: window?.rootViewController) {
            return root.supportedInterfaceOrientations
        }
        // The widget picker can use a temporary overlay window in the same scene.
        if #available(iOS 13.0, *), let scene = window?.windowScene,
           let root = scene.windows.compactMap({ revealController(in: $0.rootViewController) }).first {
            return root.supportedInterfaceOrientations
        }
        return UIDevice.current.userInterfaceIdiom == .phone ? .allButUpsideDown : .all
#endif
    }

    /// Reevaluate only the window containing the settings UI, never the external
    /// video scene. A child controller invalidation alone doesn't update UIKit's
    /// orientation policy on container and presented controllers.
    @objc(updateSupportedOrientationsFrom:)
    static func updateSupportedOrientations(from controller: UIViewController) {
#if !os(tvOS)
        guard let window = controller.viewIfLoaded?.window,
              let root = window.rootViewController else { return }
        if #available(iOS 16.0, *) {
            func invalidate(_ current: UIViewController) {
                current.setNeedsUpdateOfSupportedInterfaceOrientations()
                current.children.forEach(invalidate)
                if let presented = current.presentedViewController { invalidate(presented) }
            }
            invalidate(root)
            guard let scene = window.windowScene,
                  scene.session.role == .windowApplication else { return }
            var allowed = root.supportedInterfaceOrientations
            let preferred: UIInterfaceOrientationMask
            switch UIDevice.current.orientation {
            case .portrait: preferred = .portrait
            case .portraitUpsideDown: preferred = .portraitUpsideDown
            case .landscapeLeft: preferred = .landscapeRight
            case .landscapeRight: preferred = .landscapeLeft
            default: preferred = []
            }
            if !allowed.intersection(preferred).isEmpty { allowed = preferred }
            scene.requestGeometryUpdate(.iOS(interfaceOrientations: allowed)) { error in
                NSLog("Orientation update deferred: %@", error.localizedDescription)
            }
        } else {
            UIViewController.attemptRotationToDeviceOrientation()
        }
#endif
    }
}
