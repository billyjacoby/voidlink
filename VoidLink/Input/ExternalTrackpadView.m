//
//  ExternalTrackpadView.m
//  VoidLink
//

#import "ExternalTrackpadView.h"

@interface ExternalTrackpadView ()
@property (nonatomic, strong) UILabel *topLabel;
@property (nonatomic, strong) UILabel *titleLabel;
@property (nonatomic, strong) UILabel *statusLabel;
@property (nonatomic, strong) UILabel *hintLabel;
@end

@implementation ExternalTrackpadView

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        self.backgroundColor = UIColor.blackColor;
        self.opaque = YES;
        self.userInteractionEnabled = NO;
        self.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
        self.isAccessibilityElement = YES;
        self.accessibilityLabel = @"External trackpad. Connected display. Slide to move. Tap to click.";
        self.accessibilityTraits = UIAccessibilityTraitStaticText;

        _topLabel = [self labelWithText:@"TOP" font:[UIFont monospacedSystemFontOfSize:10.0 weight:UIFontWeightSemibold]];
        _topLabel.textAlignment = NSTextAlignmentCenter;

        _titleLabel = [self labelWithText:@"TRACKPAD" font:[UIFont monospacedSystemFontOfSize:11.0 weight:UIFontWeightSemibold]];
        _titleLabel.textAlignment = NSTextAlignmentLeft;

        _statusLabel = [self labelWithText:@"●  DISPLAY CONNECTED" font:[UIFont monospacedSystemFontOfSize:9.0 weight:UIFontWeightMedium]];
        _statusLabel.textAlignment = NSTextAlignmentRight;
        _statusLabel.textColor = [UIColor colorWithRed:0.53 green:0.78 blue:0.65 alpha:0.82];

        _hintLabel = [self labelWithText:@"Slide to move · Tap to click" font:[UIFont systemFontOfSize:13.0 weight:UIFontWeightRegular]];
        _hintLabel.textAlignment = NSTextAlignmentCenter;
        _hintLabel.textColor = [UIColor colorWithWhite:0.84 alpha:0.72];

        [self addSubview:_topLabel];
        [self addSubview:_titleLabel];
        [self addSubview:_statusLabel];
        [self addSubview:_hintLabel];
    }
    return self;
}

- (UILabel *)labelWithText:(NSString *)text font:(UIFont *)font {
    UILabel *label = [[UILabel alloc] initWithFrame:CGRectZero];
    label.text = text;
    label.font = font;
    label.textColor = [UIColor colorWithWhite:0.9 alpha:0.76];
    label.numberOfLines = 1;
    label.adjustsFontSizeToFitWidth = YES;
    label.minimumScaleFactor = 0.7;
    label.userInteractionEnabled = NO;
    return label;
}

- (void)layoutSubviews {
    [super layoutSubviews];

    UIEdgeInsets safeArea = self.safeAreaInsets;
    CGRect safeBounds = UIEdgeInsetsInsetRect(self.bounds, safeArea);
    CGFloat horizontalInset = MIN(MAX(16.0, safeBounds.size.width * 0.055), 36.0);
    CGFloat verticalInset = MIN(MAX(14.0, safeBounds.size.height * 0.035), 28.0);
    CGRect panel = CGRectInset(safeBounds, horizontalInset, verticalInset);
    CGFloat panelWidth = MAX(0.0, panel.size.width);
    CGFloat panelHeight = MAX(0.0, panel.size.height);

    CGFloat topY = CGRectGetMinY(panel) + MIN(24.0, panelHeight * 0.07);
    self.topLabel.frame = CGRectMake(CGRectGetMinX(panel) + 24.0, topY + 15.0, MAX(0.0, panelWidth - 48.0), 14.0);

    CGFloat headerY = topY + 50.0;
    CGFloat headerWidth = MAX(0.0, panelWidth - 40.0);
    self.titleLabel.frame = CGRectMake(CGRectGetMinX(panel) + 20.0, headerY, headerWidth * 0.48, 16.0);
    self.statusLabel.frame = CGRectMake(CGRectGetMinX(panel) + 20.0 + headerWidth * 0.42, headerY, headerWidth * 0.58, 16.0);

    CGFloat hintHeight = 20.0;
    CGFloat hintY = MAX(headerY + 28.0, CGRectGetMaxY(panel) - MIN(46.0, panelHeight * 0.13));
    self.hintLabel.frame = CGRectMake(CGRectGetMinX(panel) + 20.0, hintY, MAX(0.0, panelWidth - 40.0), hintHeight);
    [self setNeedsDisplay];
}

- (void)safeAreaInsetsDidChange {
    [super safeAreaInsetsDidChange];
    [self setNeedsLayout];
}

- (void)drawRect:(CGRect)rect {
    CGContextRef context = UIGraphicsGetCurrentContext();
    if (context == NULL) {
        return;
    }

    CGRect safeBounds = UIEdgeInsetsInsetRect(self.bounds, self.safeAreaInsets);
    CGFloat horizontalInset = MIN(MAX(16.0, safeBounds.size.width * 0.055), 36.0);
    CGFloat verticalInset = MIN(MAX(14.0, safeBounds.size.height * 0.035), 28.0);
    CGRect panel = CGRectInset(safeBounds, horizontalInset, verticalInset);
    if (CGRectIsEmpty(panel)) {
        return;
    }

    CGFloat cornerRadius = MIN(28.0, MIN(panel.size.width, panel.size.height) * 0.08);
    UIBezierPath *panelPath = [UIBezierPath bezierPathWithRoundedRect:panel cornerRadius:cornerRadius];
    [[UIColor colorWithRed:0.12 green:0.13 blue:0.15 alpha:1.0] setFill];
    [panelPath fill];
    [[UIColor colorWithWhite:1.0 alpha:0.105] setStroke];
    panelPath.lineWidth = 1.0 / UIScreen.mainScreen.scale;
    [panelPath stroke];

    CGContextSaveGState(context);
    [panelPath addClip];
    CGFloat dotSpacing = MIN(MAX(14.0, MIN(panel.size.width, panel.size.height) / 26.0), 22.0);
    CGFloat dotRadius = 0.75;
    CGFloat gridTop = CGRectGetMinY(self.titleLabel.frame) + 34.0;
    CGFloat gridBottom = CGRectGetMinY(self.hintLabel.frame) - 16.0;
    if (gridBottom > gridTop) {
        CGContextSetFillColorWithColor(context, [UIColor colorWithWhite:1.0 alpha:0.075].CGColor);
        for (CGFloat y = gridTop; y < gridBottom; y += dotSpacing) {
            for (CGFloat x = CGRectGetMinX(panel) + dotSpacing; x < CGRectGetMaxX(panel) - dotSpacing; x += dotSpacing) {
                CGContextFillEllipseInRect(context, CGRectMake(x - dotRadius, y - dotRadius, dotRadius * 2.0, dotRadius * 2.0));
            }
        }
    }
    CGContextRestoreGState(context);

    CGFloat arrowCenterX = CGRectGetMidX(panel);
    CGFloat arrowY = CGRectGetMinY(panel) + MIN(23.0, panel.size.height * 0.07);
    CGContextSetStrokeColorWithColor(context, [UIColor colorWithWhite:0.92 alpha:0.67].CGColor);
    CGContextSetLineWidth(context, 1.4);
    CGContextSetLineCap(context, kCGLineCapRound);
    CGContextMoveToPoint(context, arrowCenterX, arrowY + 10.0);
    CGContextAddLineToPoint(context, arrowCenterX, arrowY);
    CGContextMoveToPoint(context, arrowCenterX, arrowY);
    CGContextAddLineToPoint(context, arrowCenterX - 4.0, arrowY + 4.0);
    CGContextMoveToPoint(context, arrowCenterX, arrowY);
    CGContextAddLineToPoint(context, arrowCenterX + 4.0, arrowY + 4.0);
    CGContextStrokePath(context);
}

@end
