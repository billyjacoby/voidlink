//
//  RelativeTouchHandler.m
//  VoidLink
//
//  Completely refactored by True砖家 on 2024.9.13
//  Copyright © 2024 True砖家 on Bilibili. All rights reserved.
//

#import "RelativeTouchHandler.h"
#import "DataManager.h"
#import "VoidLink-Swift.h"

#include <Limelight.h>


static const float QUICK_TAP_TIME_INTERVAL = 0.2;

@implementation RelativeTouchHandler {
    TemporarySettings* currentSettings;
    CGPoint latestMousePointerLocation, initialMousePointerLocation;
    NSTimeInterval mousePointerTimestamp;
    BOOL firstTouchMoved;
    BOOL mousePointerMoved;
    BOOL quickTapDetected;
    
    // upper screen edge check
    bool touchPointSpawnedAtUpperScreenEdge;
    CGFloat _edgeTolerance;

    UITouch* touchLockedForMouseMove;

    bool multiTouchesDetected;
    BOOL suppressUntilFreshTouch;
    BOOL leftButtonDown;
    BOOL rightButtonDown;
    NSUInteger inputGeneration;
    NSUInteger leftClickGeneration;
    NSUInteger rightClickGeneration;
    NSTimeInterval inputResetTimestamp;
    
#if TARGET_OS_TV
    UIGestureRecognizer* remotePressRecognizer;
    UIGestureRecognizer* remoteLongPressRecognizer;
#endif
    
    __weak StreamView* streamView;
}

- (id)initWithView:(StreamView*)view andSettings:(TemporarySettings*)settings {
    self = [self init];
    self->streamView = view;
    self->currentSettings = settings;
    // replace righclick recoginizing with my CustomTapGestureRecognizer for better experience, higher recoginizing rate.
    _mouseRightClickTapRecognizer = [[CustomTapGestureRecognizer alloc] initWithTarget:self action:@selector(mouseRightClick)];
    _mouseRightClickTapRecognizer.numberOfTouchesRequired = 2;
    _mouseRightClickTapRecognizer.tapDownTimeThreshold = RIGHTCLICK_TAP_DOWN_TIME_THRESHOLD_S; // tap down time in seconds.
    _mouseRightClickTapRecognizer.delaysTouchesBegan = NO;
    _mouseRightClickTapRecognizer.delaysTouchesEnded = NO;
    [self->streamView.streamFrameTopLayerView addGestureRecognizer:_mouseRightClickTapRecognizer]; // add all additional gestures to the streamFrameTopLayerView instead of the streamview.
    _mouseRightClickTapRecognizer.touchCapturingView = streamView;
    
    firstTouchMoved = false;
    mousePointerMoved = false;
    mousePointerTimestamp = 0;
    
    // upper screen check
    _edgeTolerance = settings.edgeSlidingSensitivity.floatValue;
    self->touchPointSpawnedAtUpperScreenEdge = false;
    
#if TARGET_OS_TV
    remotePressRecognizer = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(remoteButtonPressed:)];
    remotePressRecognizer.allowedPressTypes = @[@(UIPressTypeSelect)];
    
    remoteLongPressRecognizer = [[UILongPressGestureRecognizer alloc] initWithTarget:self action:@selector(remoteButtonLongPressed:)];
    remoteLongPressRecognizer.allowedPressTypes = @[@(UIPressTypeSelect)];
    
    [self->view addGestureRecognizer:remotePressRecognizer];
    [self->view addGestureRecognizer:remoteLongPressRecognizer];
#endif
    
    return self;
}

- (bool)isOnScreenControllerBeingPressed:(NSSet* )touches{
    for(UITouch* touch in touches){
        if([OnScreenControls.touchesCapturedByOnScreenControls containsObject:touch]) return true;
    }
    return false;
}

- (void)mouseRightClick {
    if (suppressUntilFreshTouch || _mouseRightClickTapRecognizer.gestureCapturedTime <= inputResetTimestamp) return;
    multiTouchesDetected = false;
    NSUInteger generation = inputGeneration;
    NSUInteger clickGeneration = ++rightClickGeneration;
    rightButtonDown = YES;
    LiSendMouseButtonEvent(BUTTON_ACTION_PRESS, BUTTON_RIGHT);
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.1 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        if (generation != self->inputGeneration || clickGeneration != self->rightClickGeneration) return;
        self->rightButtonDown = NO;
        LiSendMouseButtonEvent(BUTTON_ACTION_RELEASE, BUTTON_RIGHT);
    });
}

- (UIView*)coordinateView {
    return streamView.relativeTouchCoordinateView ?: streamView;
}

- (void)releaseLeftButton {
    if (leftButtonDown) {
        LiSendMouseButtonEvent(BUTTON_ACTION_RELEASE, BUTTON_LEFT);
        leftButtonDown = NO;
    }
}

- (void)resetInput {
    NSAssert([NSThread isMainThread], @"Relative touch input must be reset on the main thread");
    ++inputGeneration;
    inputResetTimestamp = CACurrentMediaTime();
    ++leftClickGeneration;
    ++rightClickGeneration;
    [self releaseLeftButton];
    if (rightButtonDown) {
        LiSendMouseButtonEvent(BUTTON_ACTION_RELEASE, BUTTON_RIGHT);
        rightButtonDown = NO;
    }
    [TouchPadGestureHandler resetGesture];
    touchLockedForMouseMove = nil;
    initialMousePointerLocation = latestMousePointerLocation = CGPointZero;
    mousePointerTimestamp = 0;
    firstTouchMoved = mousePointerMoved = quickTapDetected = NO;
    multiTouchesDetected = touchPointSpawnedAtUpperScreenEdge = false;
    // Only a fresh touchesBegan sequence may resume input. An existing finger's
    // move/up must not become a new tap, drag, scroll, or right click.
    suppressUntilFreshTouch = YES;
    BOOL recognizerEnabled = _mouseRightClickTapRecognizer.enabled;
    _mouseRightClickTapRecognizer.enabled = NO;
    _mouseRightClickTapRecognizer.enabled = recognizerEnabled;
}

/*
- (BOOL)isConfirmedMove:(CGPoint)currentPoint from:(CGPoint)originalPoint {
    // Movements of greater than 1 point are considered confirmed
    return hypotf(originalPoint.x - currentPoint.x, originalPoint.y - currentPoint.y) >= 1;
}*/

- (BOOL)isAdjacentTouches:(CGPoint)currentPoint from:(CGPoint)originalPoint {
    return hypotf(originalPoint.x - currentPoint.x, originalPoint.y - currentPoint.y) <= 300;
}

- (BOOL)isAdjacentPoints:(CGPoint)currentPoint from:(CGPoint)originalPoint tolerance:(CGFloat)tolerance {
    bool isAdjacent = hypotf(originalPoint.x - currentPoint.x, originalPoint.y - currentPoint.y) <= hypot(tolerance, tolerance);
    return isAdjacent;
}

- (void)touchesBegan:(NSSet *)touches withEvent:(UIEvent *)event {
    NSSet* currentTouches = [UITouchUtil touchesIn:streamView from:event];
    if (suppressUntilFreshTouch) {
        for (UITouch* touch in currentTouches) {
            if (touch.phase != UITouchPhaseEnded && touch.phase != UITouchPhaseCancelled &&
                ![touches containsObject:touch]) return;
        }
        suppressUntilFreshTouch = NO;
    }
    if (currentTouches.count == touches.count) [TouchPadGestureHandler resetGesture];
    firstTouchMoved = false;
    UIView* coordinateView = [self coordinateView];
    CGRect bounds = coordinateView.bounds;
    
    //check if touch point is spawned on the left or right upper half screen edges, this is the highest priority
    CGPoint initialPoint = [[touches anyObject] locationInView:coordinateView];
    if(initialPoint.y < CGRectGetMinY(bounds) + CGRectGetHeight(bounds) * 0.4 &&
       (initialPoint.x < CGRectGetMinX(bounds) + _edgeTolerance || initialPoint.x > CGRectGetMaxX(bounds) - _edgeTolerance)) {
        self->touchPointSpawnedAtUpperScreenEdge = true;
        return;
    }
    
    touchPointSpawnedAtUpperScreenEdge = false; // reset this flag immediately if we get a touch event passing the check above, this fixes irresponsive touch after closing the command tool menu.
     
    if(currentTouches.count>=2){
        multiTouchesDetected = true;
        touchLockedForMouseMove = nil;
        quickTapDetected = NO;
        mousePointerMoved = NO;
        mousePointerTimestamp = 0;
        ++leftClickGeneration;
        [self releaseLeftButton];
        return;
    }
    
    UITouch* candidateTouch = nil;
    
    // the onscreen controllers are implmented by CALayer, which can not intercept UITouch event, touch will penetrate to the streamView level and captured in the touches callback of this touchHandler class.
    // the onscreen button are UIViews, they intercept UITouch events, so we don't need to worry about them.
    for(UITouch* touch in touches){
        if([OnScreenControls.touchesCapturedByOnScreenControls containsObject:touch]){
            continue;
        }
        else candidateTouch = touch;
    }

    // quick double tap detection for dragging. simulates a real notebook computer touchpad
    if (candidateTouch == nil) return;
    CGPoint currentTouchLocation = [candidateTouch locationInView:coordinateView];
    
    if(currentTouches.count == 1){
        NSTimeInterval tapInterval = CACurrentMediaTime() - mousePointerTimestamp;
        if(tapInterval < QUICK_TAP_TIME_INTERVAL
           && [self isAdjacentTouches:currentTouchLocation from:initialMousePointerLocation]) {
            quickTapDetected = true;
            NSLog(@"quick Tap Detected");
        }
    }
        
    // use [event allTouches] to check if touchLockedForMouseMove is captured, if already captured, don't update touchLockedForMouseMove
    if(candidateTouch != nil && ![[event allTouches] containsObject:touchLockedForMouseMove]){
        touchLockedForMouseMove = candidateTouch;
        // NSLog(@"Candidate touch for mouse movement locked");
        mousePointerTimestamp = CACurrentMediaTime();
        initialMousePointerLocation = latestMousePointerLocation = [touchLockedForMouseMove locationInView:coordinateView];
    }
}

- (void)touchesMoved:(NSSet *)touches withEvent:(UIEvent *)event {
    if (suppressUntilFreshTouch) return;
        
    NSSet* currentTouches = [UITouchUtil touchesIn:streamView from:event];
        
    if(![self isOnScreenControllerBeingPressed:currentTouches]) {
        [TouchPadGestureHandler handleGestureIn:streamView coordinateView:[self coordinateView] with:event];
    }
         
    if(multiTouchesDetected) return;
    
    if([touches containsObject:touchLockedForMouseMove]){
        CGPoint currentLocation = [touchLockedForMouseMove locationInView:[self coordinateView]];
        bool isAdjacentPoints = [self isAdjacentPoints:initialMousePointerLocation from:currentLocation tolerance:currentSettings.singleTapSensitivity.doubleValue];
        if(!mousePointerMoved && !isAdjacentPoints){
            mousePointerMoved = true;
        }
        [self sendMouseMoveEvent:currentLocation];
    }
}

- (void)touchesEnded:(NSSet *)touches withEvent:(UIEvent *)event {
    if (suppressUntilFreshTouch) {
        for (UITouch* touch in touches) {
            [OnScreenControls.touchesCapturedByOnScreenControls removeObject:touch];
        }
        return;
    }
    
    [TouchPadGestureHandler releasePinchModifier];
    
    [TouchPadGestureHandler startInertialScroll];
    
    if(multiTouchesDetected){
        if([UITouchUtil touchesIn:streamView from:event].count == touches.count){
            multiTouchesDetected = false;
        }
        return;
    }
    if([UITouchUtil touchesIn:streamView from:event].count == touches.count) multiTouchesDetected = false;

    if([touches containsObject:touchLockedForMouseMove]){
        // dealing with a single first tap, whether the button will be released, is going to be decided in sendLongMouseLeftButtonClickEvent
        if(!mousePointerMoved && !self->quickTapDetected) [self sendLongMouseLeftButtonClickEvent];
        
        // dealing with a second quick tap following the first tap:
        if(self->quickTapDetected){
            // we're in at least the second tap release of the very short time interval after the first tap.
            ++leftClickGeneration;
            [self releaseLeftButton];
            if(!mousePointerMoved) [self sendShortMouseLeftButtonClickEvent]; // if it is a quick tap and the pointer was not moved, we must send another click to simulate double click.
            self->quickTapDetected = false; // reset flag
        }
        touchLockedForMouseMove = nil;
        mousePointerMoved = false;
    }
    
    for(UITouch* touch in touches){
        [OnScreenControls.touchesCapturedByOnScreenControls removeObject:touch];
    }
        
    if([UITouchUtil touchesIn:streamView from:event].count == [touches count]){
        touchLockedForMouseMove = nil;
        mousePointerMoved = false; // need to reset this anyway
    }
        
    touchPointSpawnedAtUpperScreenEdge = false;
}

- (void)sendMouseMoveEvent:(CGPoint)currentLocation{
    // UIKit and gesture state stay on the main thread. LiSendMouseMoveEvent
    // already queues input deltas on moonlight-common's input queue. Avoid
    // an additional dispatch hop that can mix old locations with a reset or
    // reorder a drag's last movement after its button release.
    bool isAdjacentPoints = [self isAdjacentPoints:initialMousePointerLocation from:currentLocation tolerance:currentSettings.relativeTouchSlideThreshold.floatValue];
    if (!firstTouchMoved && !isAdjacentPoints) {
        latestMousePointerLocation = currentLocation;
        firstTouchMoved = true;
    }
    int deltaX = (currentLocation.x - latestMousePointerLocation.x) * 1.35 * currentSettings.mousePointerVelocityFactor.floatValue;
    int deltaY = (currentLocation.y - latestMousePointerLocation.y) * 1.35 * currentSettings.mousePointerVelocityFactor.floatValue;
    if (deltaX == 0 && deltaY == 0) return;
    latestMousePointerLocation = currentLocation;
    if (touchPointSpawnedAtUpperScreenEdge || !firstTouchMoved) return;
    LiSendMouseMoveEvent(deltaX, deltaY);
}

// this will turn into a dragging anytime...
- (void)sendLongMouseLeftButtonClickEvent{
    NSUInteger generation = inputGeneration;
    NSUInteger clickGeneration = ++leftClickGeneration;
    leftButtonDown = YES;
    LiSendMouseButtonEvent(BUTTON_ACTION_PRESS, BUTTON_LEFT);
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(QUICK_TAP_TIME_INTERVAL * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        if (generation != self->inputGeneration || clickGeneration != self->leftClickGeneration) return;
        // Keep the button down when the second tap has turned into a drag.
        if (!self->quickTapDetected) [self releaseLeftButton];
    });
}

- (void)sendShortMouseLeftButtonClickEvent{
    NSUInteger generation = inputGeneration;
    NSUInteger clickGeneration = ++leftClickGeneration;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.05 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        if (generation != self->inputGeneration || clickGeneration != self->leftClickGeneration) return;
        self->leftButtonDown = YES;
        LiSendMouseButtonEvent(BUTTON_ACTION_PRESS, BUTTON_LEFT);
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.05 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            if (generation != self->inputGeneration || clickGeneration != self->leftClickGeneration) return;
            if (!self->quickTapDetected) [self releaseLeftButton];
        });
    });
}

- (void)touchesCancelled:(NSSet *)touches withEvent:(UIEvent *)event {
    [self resetInput];
    for (UITouch* touch in touches) {
        [OnScreenControls.touchesCapturedByOnScreenControls removeObject:touch];
    }
}

#if TARGET_OS_TV
- (void)remoteButtonPressed:(id)sender {
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_HIGH, 0), ^{
        Log(LOG_D, @"Sending left mouse button press");
        
        // Mark this as touchMoved to avoid a duplicate press on touch up
        self->touchMoved = true;
        
        LiSendMouseButtonEvent(BUTTON_ACTION_PRESS, BUTTON_LEFT);
        
        // Wait 100 ms to simulate a real button press
        usleep(100 * 1000);
            
        LiSendMouseButtonEvent(BUTTON_ACTION_RELEASE, BUTTON_LEFT);
    });
}
- (void)remoteButtonLongPressed:(id)sender {
    Log(LOG_D, @"Holding left mouse button");
    
    isDragging = true;
    LiSendMouseButtonEvent(BUTTON_ACTION_PRESS, BUTTON_LEFT);
}
#endif

@end
