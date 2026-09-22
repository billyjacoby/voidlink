//
//  ExternalTrackpadView.h
//  VoidLink
//

#import <UIKit/UIKit.h>

/// A non-interactive visual surface for external-trackpad mode.
/// The parent owns its frame and any orientation transform.
@interface ExternalTrackpadView : UIView

- (instancetype)initWithFrame:(CGRect)frame;

@end
