#import "../Shared/LMShared.h"
#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <stdatomic.h>
#import <roothide.h>

@interface BKDisplayRenderOverlaySpinny : NSObject
- (CALayer *)contentLayer;
@end

static atomic_bool LMRespringLogoNeedsUpdate = true;

static CGImageRef LMGetRespringLogo(void) {
    static CGImageRef image;
    if (atomic_exchange(&LMRespringLogoNeedsUpdate, false)) {
        if (image) CGImageRelease(image);
        image = NULL;
        NSDictionary *config = [NSDictionary dictionaryWithContentsOfFile:LMConfigPath] ? : @{};
        NSArray *themes = [config[LMConfigEnabledThemes] isKindOfClass:[NSArray class]] ? config[LMConfigEnabledThemes] : @[];

        // backboardd no longer loads an image for a respring logo, so to keep compatibility with old anemone/winterboard themes
        // we just load the apple-logo image ourselves.
        NSArray *fileNames;
        if (UI_USER_INTERFACE_IDIOM() == UIUserInterfaceIdiomPad) {
            fileNames = @[@"apple-logo@3x.png", @"apple-logo@2x~ipad.png", @"apple-logo@2x.png", @"apple-logo~ipad.png", @"apple-logo.png"];
        } else {
            fileNames = @[
                @"apple-logo@3x.png", @"apple-logo@3x~iphone.png", @"apple-logo@2x.png",
                @"apple-logo@2x~iphone.png", @"apple-logo.png", @"apple-logo~iphone.png"
            ];
        }

        for (NSString *theme in themes) {
            NSString *themeDirectory = [LMThemesDirectory stringByAppendingPathComponent:theme];
            NSString *bundleDirectory = [themeDirectory stringByAppendingPathComponent:@"Bundles"];
            NSString *progressDirectory = [bundleDirectory stringByAppendingPathComponent:@"com.apple.ProgressUI"];

            BOOL isDirectory = NO;
            if (![[NSFileManager defaultManager] fileExistsAtPath:progressDirectory isDirectory:&isDirectory]) continue;
            if (!isDirectory) continue;

            for (NSString *name in fileNames) {
                NSURL *url = [NSURL fileURLWithPath:[progressDirectory stringByAppendingPathComponent:name]];
                CGImageSourceRef source = CGImageSourceCreateWithURL((__bridge CFURLRef)url, NULL);
                if (!source) continue;
                image = CGImageSourceCreateImageAtIndex(source, 0, NULL);
                CFRelease(source);
                if (image) return image;
            }
        }
    }
    return image;
}

static char LMOriginalLayerStateKey;

static BOOL LMApplyRespringLogo(CALayer *layer) {
    if (!layer) return NO;

    @synchronized (%c(BKDisplayRenderOverlaySpinny)) {
        CGImageRef image = LMGetRespringLogo();
        NSDictionary *originalState = objc_getAssociatedObject(layer, &LMOriginalLayerStateKey);
        if (!image) {
            if (originalState) {
                [CATransaction begin];
                [CATransaction setDisableActions:YES];
                layer.bounds = [originalState[@"bounds"] CGRectValue];
                layer.contents = originalState[@"contents"] == NSNull.null ? nil : originalState[@"contents"];
                layer.contentsGravity = originalState[@"gravity"];
                [CATransaction commit];
                objc_setAssociatedObject(layer, &LMOriginalLayerStateKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
            }
            return NO;
        }
        if (!originalState) {
            originalState = @{
                @"bounds": [NSValue valueWithCGRect:layer.bounds],
                @"contents": layer.contents ?: NSNull.null,
                @"gravity": layer.contentsGravity
            };
            objc_setAssociatedObject(layer, &LMOriginalLayerStateKey, originalState, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        }

        [CATransaction begin];
        [CATransaction setDisableActions:YES];
        [layer removeAllAnimations];
        layer.bounds = CGRectMake(0, 0, CGImageGetWidth(image), CGImageGetHeight(image));
        layer.contents = (__bridge id)image;
        layer.contentsGravity = kCAGravityResizeAspect;
        [CATransaction commit];
        return YES;
    }
}

%hook BKDisplayRenderOverlaySpinny

- (CALayer *)_prepareContentLayerForPresentation:(id)presentation {
    CALayer *layer = %orig;
    LMApplyRespringLogo(layer);
    return layer;
}

- (void)_startAnimating {
    if (!LMApplyRespringLogo([self contentLayer])) {
        %orig;
    }
}

%end

static void LMRespringLogoMapChanged(
    CFNotificationCenterRef center,
    void *observer,
    CFStringRef name,
    const void *object,
    CFDictionaryRef userInfo
) {
    atomic_store(&LMRespringLogoNeedsUpdate, true);
}

%ctor {
    CFNotificationCenterAddObserver(
        CFNotificationCenterGetDarwinNotifyCenter(),
        NULL,
        LMRespringLogoMapChanged,
        CFSTR(LMNotifyMapChanged),
        NULL,
        CFNotificationSuspensionBehaviorDeliverImmediately
    );
}
