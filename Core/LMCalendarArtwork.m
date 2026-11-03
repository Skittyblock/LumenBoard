#import "LMCalendarArtwork.h"
#import "../Shared/LMShared.h"
#import <CoreText/CoreText.h>
#import <math.h>

static NSLock *LMCalendarLock;
static NSDictionary *LMCalendarSettings;

static void LMPrepareCalendarLock(void) {
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        LMCalendarLock = [NSLock new];
    });
}

void LMInvalidateCalendarSettings(void) {
    LMPrepareCalendarLock();
    [LMCalendarLock lock];
    LMCalendarSettings = nil;
    [LMCalendarLock unlock];
}

static NSDictionary *LMReadCalendarSettings(void) {
    LMPrepareCalendarLock();
    [LMCalendarLock lock];
    if (!LMCalendarSettings) {
        // find first enabled theme that sets calendar icon settings
        NSDictionary *config = [NSDictionary dictionaryWithContentsOfFile:LMConfigPath];
        id themes = config[LMConfigEnabledThemes];
        NSDictionary *date, *day;
        if ([themes isKindOfClass:[NSArray class]]) {
            for (id name in themes) {
                NSString *path = [[LMThemesDirectory stringByAppendingPathComponent:name] stringByAppendingPathComponent:@"Info.plist"];
                NSDictionary *info = [NSDictionary dictionaryWithContentsOfFile:path];
                id value = info[@"CalendarIconDateSettings"];
                if ([value isKindOfClass:[NSDictionary class]]) date = [value copy];
                value = info[@"CalendarIconDaySettings"];
                if ([value isKindOfClass:[NSDictionary class]]) day = [value copy];
                if (date || day) break;
            }
        }
        NSMutableDictionary *settings = [NSMutableDictionary new];
        if (date) settings[@"CalendarIconDateSettings"] = date;
        if (day) settings[@"CalendarIconDaySettings"] = day;
        LMCalendarSettings = [settings copy];
    }
    NSDictionary *settings = LMCalendarSettings;
    [LMCalendarLock unlock];
    return settings;
}

BOOL LMHasCalendarSettings(void) {
    return LMReadCalendarSettings().count != 0;
}

static CGFloat LMNumber(
    NSDictionary *settings,
    NSString *key,
    CGFloat fallback,
    CGFloat low,
    CGFloat high
) {
    id value = settings[key];
    double number;
    // snowboard supported strings for number values so there may be some themes that used them
    if ([value isKindOfClass:[NSString class]]) {
        NSScanner *scanner = [NSScanner scannerWithString:value];
        if (![scanner scanDouble:&number] || !scanner.isAtEnd) return fallback;
    } else if ([value isKindOfClass:[NSNumber class]] && CFGetTypeID((__bridge CFTypeRef)value) != CFBooleanGetTypeID()) {
        number = [value doubleValue];
    } else {
        return fallback;
    }
    return isfinite(number) && number >= low && number <= high ? number : fallback;
}

static CGColorRef LMCreateColor(id value) CF_RETURNS_RETAINED {
    if (![value isKindOfClass:[NSString class]] || [value length] > 128) return NULL;
    NSString *text = [[value stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]] lowercaseString];
    NSDictionary *names = @{
        @"black" : @"#000000",
        @"white" : @"#ffffff",
        @"clear" : @"#00000000",
        @"transparent" : @"#00000000",
        @"red" : @"#ff0000",
        @"blue" : @"#0000ff",
        @"green" : @"#00ff00",
        @"lime" : @"#00ff00",
        @"gray" : @"#808080",
        @"grey" : @"#808080",
        @"yellow" : @"#ffff00",
        @"orange" : @"#ff8000",
        @"purple" : @"#800080",
        @"brown" : @"#996633",
        @"darkgray" : @"#555555",
        @"lightgray" : @"#aaaaaa",
        @"pink" : @"#ffc0cb",
        @"cyan" : @"#00ffff",
        @"magenta" : @"#ff00ff",
        @"silver" : @"#c0c0c0",
        @"navy" : @"#000080"
    };
    text = names[text] ?: text;
    CGFloat channels[4] = {0, 0, 0, 1};
    if ([text hasPrefix:@"#"]) {
        NSString *hex = [text substringFromIndex:1];
        NSUInteger length = hex.length;
        if (length != 3 && length != 4 && length != 6 && length != 8) return NULL;
        NSCharacterSet *invalidHexSet = [[NSCharacterSet characterSetWithCharactersInString:@"0123456789abcdef"] invertedSet]];
        if ([hex rangeOfCharacterFromSet:invalidHexSet].location != NSNotFound) return NULL;
        unsigned long long bits = 0;
        if (![[NSScanner scannerWithString:hex] scanHexLongLong:&bits]) return NULL;
        BOOL shortForm = length <= 4;
        NSUInteger count = shortForm ? length : length / 2;
        unsigned shift = shortForm ? 4 : 8;
        unsigned mask = shortForm ? 15 : 255;
        for (NSUInteger i = 0; i < count; i++)
            channels[i] = ((bits >> ((count - i - 1) * shift)) & mask) / (CGFloat)mask;
    } else {
        BOOL alpha = [text hasPrefix:@"rgba("];
        if ((!alpha && ![text hasPrefix:@"rgb("]) || ![text hasSuffix:@")"]) return NULL;
        NSUInteger start = alpha ? 5 : 4;
        NSArray *parts = [[text substringWithRange:NSMakeRange(start, text.length - start - 1)] componentsSeparatedByString:@","];
        if (parts.count != (alpha ? 4 : 3)) return NULL;
        for (NSUInteger i = 0; i < parts.count; i++) {
            NSString *part = [parts[i] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
            BOOL percent = [part hasSuffix:@"%"];
            if (percent) part = [part substringToIndex:part.length - 1];
            NSScanner *scanner = [NSScanner scannerWithString:part];
            double number;
            if (![scanner scanDouble:&number] || !scanner.isAtEnd || !isfinite(number)) return NULL;
            double maximum = percent ? 100 : (i == 3 ? 1 : 255);
            if (number < 0 || number > maximum) return NULL;
            channels[i] = number / maximum;
        }
    }
    CGColorSpaceRef space = CGColorSpaceCreateDeviceRGB();
    CGColorRef color = CGColorCreate(space, channels);
    CGColorSpaceRelease(space);
    return color;
}

static CTFontRef LMCreateCalendarFont(
    NSDictionary *settings,
    CGFloat size,
    BOOL day
) CF_RETURNS_RETAINED {
    id name = settings[@"FontName"];
    id weight = settings[@"FontWeight"];
    BOOL systemName = [name isKindOfClass:[NSString class]] && [name hasPrefix:@".SF"];
    if (!weight && systemName) {
        NSArray *parts = [name componentsSeparatedByString:@"-"];
        weight = parts.count > 1 ? parts[1] : @"regular";
    }
    CTFontRef font = NULL;
    if (!weight && !systemName && [name isKindOfClass:[NSString class]] && [name length] && [name length] <= 256)
        font = CTFontCreateWithName((__bridge CFStringRef)name, size, NULL);
    if (!font) font = CTFontCreateUIFontForLanguage(kCTFontUIFontSystem, size, NULL);
    if (!font) font = CTFontCreateWithName(CFSTR("Helvetica"), size, NULL);
    NSDictionary *weights = @{
        @"ultralight" : @(-0.8),
        @"thin" : @(-0.6),
        @"light" : @(-0.4),
        @"regular" : @0,
        @"normal" : @0,
        @"medium" : @0.23,
        @"semibold" : @0.3,
        @"bold" : @0.4,
        @"heavy" : @0.56,
        @"black" : @0.62
    };
    NSNumber *trait = [weight isKindOfClass:[NSString class]] ? weights[[weight lowercaseString]] : nil;
    if ([weight isKindOfClass:[NSNumber class]]) trait = @(LMNumber(settings, @"FontWeight", day ? 0.23 : -0.6, -1, 1));
    BOOL italic = [weight isKindOfClass:[NSString class]] && [[weight lowercaseString] isEqualToString:@"italic"];
    if (!trait && weight) trait = @0;
    if (!trait && ![name isKindOfClass:[NSString class]]) trait = day ? @0.3 : @(-0.6);
    if (trait) {
        NSDictionary *attributes = @{(__bridge NSString *)kCTFontTraitsAttribute : @{(__bridge NSString *)kCTFontWeightTrait : trait}};
        CTFontDescriptorRef descriptor = CTFontDescriptorCreateWithAttributes((__bridge CFDictionaryRef)attributes);
        CTFontRef weighted = CTFontCreateCopyWithAttributes(font, size, NULL, descriptor);
        CFRelease(descriptor);
        if (weighted) {
            CFRelease(font);
            font = weighted;
        }
    }
    if (italic) {
        CTFontRef slanted = CTFontCreateCopyWithSymbolicTraits(font, size, NULL, kCTFontItalicTrait, kCTFontItalicTrait);
        if (slanted) {
            CFRelease(font);
            font = slanted;
        }
    }
    return font;
}

static void LMDrawCalendarText(
    CGContextRef context,
    NSString *text,
    NSDictionary *settings,
    BOOL day,
    NSLocale *locale
) {
    id textCase = settings[@"TextCase"];
    if ([textCase isKindOfClass:[NSString class]]) {
        NSString *mode = [textCase lowercaseString];
        if ([mode isEqualToString:@"uppercase"])
            text = [text uppercaseStringWithLocale:locale];
        else if ([mode isEqualToString:@"lowercase"])
            text = [text lowercaseStringWithLocale:locale];
        else if ([mode isEqualToString:@"capitalize"] || [mode isEqualToString:@"capitalized"])
            text = [text capitalizedStringWithLocale:locale];
    }
    CGFloat size = LMNumber(settings, @"FontSize", day ? 10 : 39.5, 0, 120);
    if (size == 0) return; // coretext treats a 0 font size as default, but we should hide it instead
    CTFontRef font = LMCreateCalendarFont(settings, size, day);
    CGColorRef color = LMCreateColor(settings[@"TextColor"]);
    if (!color) color = LMCreateColor(settings[@"TextColor"] ? @"black" : (day ? @"#ff3b30" : @"black"));
    NSDictionary *attributes =
        @{(__bridge NSString *)kCTFontAttributeName : (__bridge id)font, (__bridge NSString *)kCTForegroundColorAttributeName : (__bridge id)color};
    NSAttributedString *string = [[NSAttributedString alloc] initWithString:text attributes:attributes];
    CTLineRef line = CTLineCreateWithAttributedString((__bridge CFAttributedStringRef)string);
    CGFloat ascent, descent, leading;
    double width = CTLineGetTypographicBounds(line, &ascent, &descent, &leading);
    CGFloat dx = LMNumber(settings, @"TextXoffset", 0, -240, 240);
    CGFloat dy = LMNumber(settings, @"TextYoffset", 0, -240, 240);
    // -1 means the default position
    CGFloat x = (60 - width) / 2 + (dx == -1 ? 0 : dx);
    CGFloat y = (day ? 6 : 12) + (dy == -1 ? 0 : dy);
    CGContextSaveGState(context);
    CGColorRef shadow = LMCreateColor(settings[@"ShadowColor"]);
    if (shadow) {
        CGFloat dx = LMNumber(settings, @"ShadowXoffset", 0, -240, 240);
        CGFloat dy = LMNumber(settings, @"ShadowYoffset", 0, -240, 240);
        CGFloat blurRadius = LMNumber(settings, @"ShadowBlurRadius", 0, 0, 120);
        CGContextSetShadowWithColor(context, CGSizeMake(dx, -dy), blurRadius, shadow);
        CGColorRelease(shadow);
    }
    CGContextSetTextMatrix(context, CGAffineTransformMakeScale(1, -1));
    CGContextSetTextPosition(context, x, y + ascent);
    CTLineDraw(line, context);
    CGContextRestoreGState(context);
    CFRelease(line);
    CGColorRelease(color);
    CFRelease(font);
}

CGImageRef LMCreateCalendarArtwork(
    CGImageRef base,
    NSDateComponents *components,
    NSCalendar *calendar,
    CGSize size,
    CGFloat scale
) {
    if (![components isKindOfClass:[NSDateComponents class]] || ![calendar isKindOfClass:[NSCalendar class]]) return NULL;
    if (!isfinite(size.width) || !isfinite(size.height) || !isfinite(scale)) return NULL;
    if (size.width <= 0 || size.height <= 0 || scale <= 0 || scale > 16) return NULL;
    double width = ceil(size.width * scale), height = ceil(size.height * scale);
    if (!isfinite(width) || !isfinite(height) || width < 1 || height < 1 || width > 4096 || height > 4096 || width * height > 16777216) return NULL;

    @autoreleasepool {
        NSCalendar *localCalendar = [calendar copy];
        NSDate *date = [localCalendar dateFromComponents:components];
        if (!date) return NULL;

        NSDateFormatter *formatter = [NSDateFormatter new];
        NSLocale *locale = [NSLocale currentLocale];
        formatter.locale = locale;
        formatter.calendar = localCalendar;
        formatter.timeZone = localCalendar.timeZone;
        NSString *dateText, *dayText;
        formatter.dateFormat = @"d";
        dateText = [formatter stringFromDate:date];
        formatter.dateFormat = @"EEEE"; // todo: we probably want to support custom date formats, since this is no longer the system default
        dayText = [formatter stringFromDate:date];

        NSDictionary *settings = LMReadCalendarSettings();
        CGColorSpaceRef space = CGColorSpaceCreateDeviceRGB();
        CGContextRef context =
            CGBitmapContextCreate(NULL, (size_t)width, (size_t)height, 8, 0, space, kCGImageAlphaPremultipliedLast | kCGBitmapByteOrder32Big);
        CGColorSpaceRelease(space);
        if (!context) return NULL;
        if (base) {
            CGContextDrawImage(context, CGRectMake(0, 0, width, height), base);
        }
        CGContextTranslateCTM(context, 0, height);
        CGContextScaleCTM(context, width / 60, -height / 60);
        LMDrawCalendarText(context, dateText, settings[@"CalendarIconDateSettings"], NO, locale);
        LMDrawCalendarText(context, dayText, settings[@"CalendarIconDaySettings"], YES, locale);
        CGImageRef result = CGBitmapContextCreateImage(context);
        CGContextRelease(context);
        return result;
    }
}
