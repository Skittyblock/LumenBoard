#import "LMCalendarArtwork.h"
#import "LMIconStore.h"
#import "LMStatus.h"
#import "Private.h"
#import <objc/runtime.h>

BOOL LMCalendarHooksInstalled = NO;

static CGImageRef LMCalendarImage(
    NSDateComponents *components,
    NSCalendar *calendar,
    CGSize size,
    double scale,
    long long appearance,
    LMCalendarArtworkOptions options
) CF_RETURNS_RETAINED {
    BOOL themedBackground = [[LMIconStore sharedStore] iconForBundleIdentifier:@"com.apple.mobilecal"] != nil;
    if (!themedBackground && ((options & LMCalendarArtworkBackground) || !LMHasCalendarSettings())) return NULL;

    NSMutableDictionary *threadState = [NSThread currentThread].threadDictionary;
    NSString *isRenderingKey = @"com.xsxs18.lumenboard.calendar-rendering";
    if (threadState[isRenderingKey]) return NULL;
    threadState[isRenderingKey] = @YES;
    @try {
        id background = nil;
        CGImageRef base = NULL;
        if (options & LMCalendarArtworkBackground) {
            Class iconClass = objc_getClass("ISIcon"), descriptorClass = objc_getClass("ISImageDescriptor");
            if (![descriptorClass instancesRespondToSelector:@selector(initWithSize:scale:)]) return NULL;

            ISIcon *icon = [iconClass alloc];
            if (![icon respondsToSelector:@selector(initWithBundleIdentifier:)]) return NULL;
            icon = [icon initWithBundleIdentifier:@"com.apple.mobilecal"];
            if (![icon respondsToSelector:@selector(imageForImageDescriptor:)]) return NULL;

            ISImageDescriptor *descriptor = [[descriptorClass alloc] initWithSize:size scale:scale];
            if ([descriptor respondsToSelector:@selector(setAppearance:)]) {
                [descriptor setAppearance:appearance];
            }

            background = [icon imageForImageDescriptor:descriptor];
            if (![background respondsToSelector:@selector(cgImage)]) return NULL;
            base = [background cgImage];
            if (!base) return NULL;
        }
        return LMCreateCalendarArtwork(base, components, calendar, size, scale);
    } @catch (NSException *exception) {
        LMStatusEvent(@"Calendar rendering failed: %@", exception.reason);
        return NULL;
    } @finally {
        [threadState removeObjectForKey:isRenderingKey];
    }
}

%group CalendarIcon
%hook CUIKIcon
- (id)_imageForDescriptor:(ISImageDescriptor *)descriptor {
    if (![self respondsToSelector:@selector(dateComponents)] || ![self respondsToSelector:@selector(calendar)]) return %orig;
    if (![descriptor respondsToSelector:@selector(size)] || ![descriptor respondsToSelector:@selector(scale)]) return %orig;
    long long appearance = [descriptor respondsToSelector:@selector(appearance)] ? descriptor.appearance : 0;
    CGImageRef image = LMCalendarImage(self.dateComponents, self.calendar, descriptor.size, descriptor.scale, appearance, LMCalendarArtworkAll);
    if (!image) return %orig;
    IFImage *result = [[%c(IFImage) alloc] initWithCGImage:image scale:descriptor.scale];
    CGImageRelease(image);
    return result;
}
%end

// handle calls for the icon that only request specific layers
// fixes themes where a background is not set for the calendar icon but the text is themed
%hook CUIKIcon
- (id)iconImageWithSize:(CGSize)size scale:(double)scale appearance:(NSInteger)appearance layers:(NSUInteger)layers {
    if (!layers || (layers & ~((NSUInteger)7))) return %orig;
    LMCalendarArtworkOptions options = 0;
    if (layers & 1) options |= LMCalendarArtworkBackground;
    if (layers & 2) options |= LMCalendarArtworkDay;
    if (layers & 4) options |= LMCalendarArtworkDate;
    CGImageRef image = LMCalendarImage(self.dateComponents, self.calendar, size, scale, appearance, options);
    if (!image) return %orig;
    IFImage *result = [[%c(IFImage) alloc] initWithCGImage:image scale:scale];
    CGImageRelease(image);
    return result ?: %orig;
}
%end
%end

void LMInstallCalendarHooks(void) {
    if (LMCalendarHooksInstalled) return;
    Class icon = objc_getClass("CUIKIcon");
    if (!icon || !objc_getClass("IFImage")) return;
    LMCalendarHooksInstalled = YES;
    %init(CalendarIcon);
}
