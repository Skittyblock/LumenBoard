#pragma once

#import <CoreGraphics/CoreGraphics.h>
#import <Foundation/Foundation.h>

extern BOOL LMCalendarHooksInstalled;

typedef NS_OPTIONS(NSUInteger, LMCalendarArtworkOptions) {
    LMCalendarArtworkBackground = 1 << 0,
    LMCalendarArtworkDay = 1 << 1,
    LMCalendarArtworkDate = 1 << 2,
    LMCalendarArtworkAll = 7
};

CGImageRef LMCreateCalendarArtwork(
    CGImageRef base,
    NSDateComponents *components,
    NSCalendar *calendar,
    CGSize size,
    CGFloat scale
) CF_RETURNS_RETAINED;
BOOL LMHasCalendarSettings(void);
void LMInvalidateCalendarSettings(void);

void LMInstallCalendarHooks(void);
