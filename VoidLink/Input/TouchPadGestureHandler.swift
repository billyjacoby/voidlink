//
//  TouchPadGestureHandler.swift
//  VoidLink
//
//  Created by True砖家 on 2025/11/5.
//  Copyright © 2025 True砖家 on Bilibili. All rights reserved.
//

import UIKit

@objc class TouchPadGestureHandler: NSObject {
    
    @objc public static var ctrlDown:Bool = false
    @objc public static var enablePinch:Bool = true
    @objc public static var ctrlDownForPinch:Bool = true
    @objc public static var enableHorizontalScroll:Bool = true
    @objc public static var scrollSensitivity:CGFloat = 1.0
    @objc public static var pinchSensitivity:CGFloat = 1.0
    @objc public static var displayLinkRate:CGFloat = 60

    private static var inertialScroller: InertialScroller = InertialScroller(decelerationRate: displayLinkRate > 110 ? 0.96 : 0.9, displayLinkRate: displayLinkRate) {
        if ctrlDown {return}
        LiSendHighResScrollEvent(Int16(inertialScroller.vector.dy*7*scrollSensitivity))
        if TouchPadGestureHandler.enableHorizontalScroll {LiSendHighResHScrollEvent(Int16(-inertialScroller.vector.dx*7*scrollSensitivity))}
    }
    
    @objc public static func startInertialScroll(){
        inertialScroller.timer?.restart()
    }

    @objc public static func releasePinchModifier() {
        if ctrlDown {
            LiSendKeyboardEvent(CommandManager.keyboardButtonMappings["CTRL"]!, CChar(KEY_ACTION_UP), 0)
            ctrlDown = false
        }
    }

    @objc public static func resetGesture() {
        pauseInertialScroll()
        inertialScroller.vector = .zero
        releasePinchModifier()
    }

    private static func pauseInertialScroll() {
        inertialScroller.timer?.pause()
        // SafeTimer.pause() is asynchronous. Drain its serial queue before
        // changing the vector so an in-flight tick cannot send stale inertia.
        _ = inertialScroller.timer?.isRunning()
    }
    
    @objc public static func handleGesture(in view: UIView, with event: UIEvent) {
        handleGesture(in: view, coordinateView: view, with: event)
    }

    // Capture remains in the interactive view even when coordinates belong to
    // a rotated, noninteractive trackpad overlay.
    @objc(handleGestureIn:coordinateView:with:)
    public static func handleGesture(in view: UIView, coordinateView: UIView, with event: UIEvent) {
        pauseInertialScroll()
        
        let currentTouches = UITouchUtil.touches(in: view, from: event)
        guard currentTouches.count == 2 else { return }
        
        LiSendMouseButtonEvent(CChar(BUTTON_ACTION_RELEASE), BUTTON_LEFT)
        LiSendMouseButtonEvent(CChar(BUTTON_ACTION_RELEASE), BUTTON_RIGHT)
        
        guard let touch1 = currentTouches.first else { return }
        var mutable = Array(currentTouches)
        mutable.removeAll { $0 == touch1 }
        guard let touch2 = mutable.first else { return }
        
        let currentDistance = UITouchUtil.distance(between: touch1, and: touch2, in: coordinateView)
        let previousDistance = UITouchUtil.previousDistance(between: touch1, and: touch2, in: coordinateView)
        
        let midPointVector = UITouchUtil.midPointVector(between: touch1, and: touch2, in: coordinateView)
        let midPointDeltaX = midPointVector.dx
        let midPointDeltaY = midPointVector.dy
        
        let sendHorizontalScroll = abs(midPointDeltaX) > 1.2*abs(midPointDeltaY)
        
        inertialScroller.vector = CGVector(dx: sendHorizontalScroll ? midPointDeltaX : 0, dy: midPointDeltaY)
        
        let originalPinchDelta = currentDistance-previousDistance;
        let pinchDelta = enablePinch ? originalPinchDelta*7*pinchSensitivity : 0;
        LiSendHighResScrollEvent(Int16(pinchDelta + midPointDeltaY*7*scrollSensitivity))
        if enableHorizontalScroll, sendHorizontalScroll {LiSendHighResHScrollEvent(Int16(-midPointDeltaX*7*scrollSensitivity))}
        
        if enablePinch, ctrlDownForPinch {
            let midPointDelta = hypot(midPointDeltaX, midPointDeltaY)
            if abs(originalPinchDelta) > midPointDelta*1.3, midPointDelta < 2 {
                LiSendKeyboardEvent(CommandManager.keyboardButtonMappings["CTRL"]!, CChar(KEY_ACTION_DOWN), 0)
                ctrlDown = true
            } else {
                LiSendKeyboardEvent(CommandManager.keyboardButtonMappings["CTRL"]!, CChar(KEY_ACTION_UP), 0)
                ctrlDown = false
            }
        }
    }
}
