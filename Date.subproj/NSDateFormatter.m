/*
 * Copyright (C) 2026, Samuel Zormeister.
 *
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */

#import <Foundation/NSDateFormatter.h>
#import <Foundation/FoundationErrors.h>
#import <Foundation/NSDictionary.h>
#import <Foundation/NSString.h>
#include <CoreFoundation/CFDateFormatter.h>
#include <CoreFoundation/CFNumber.h>
#include <CoreFoundation/CFTimeZone.h>
#include <CoreFoundation/CFCalendar.h>

#if __has_feature(objc_arc)
#define NSFORMATTER_TRANSFER(value) ((__bridge_transfer id)(value))
#define NSFORMATTER_CF(type, value) ((__bridge type)(value))
#else
#define NSFORMATTER_TRANSFER(value) ((id)CFAutorelease(value))
#define NSFORMATTER_CF(type, value) ((type)(value))
#endif

/* NSLocale owns its CFLocale rather than being toll-free with it; extract the
 * backing locale for CFDateFormatterCreate instead of casting the wrapper. */
@interface NSLocale ()
- (CFLocaleRef)_backingLocale;
@end

/* NSCalendar likewise owns its CFCalendar; redeclare its private accessors so
 * the formatter can hand the backing calendar to CFDateFormatterSetProperty. */
@interface NSCalendar ()
- (CFCalendarRef)_backingCalendar;
- (instancetype)_initWithBackingCalendar:(CFCalendarRef)backing;
@end

@implementation NSDateFormatter

+ (instancetype)dateFormatter {
    return [[self alloc] init];
}

+ (NSString *)localizedStringFromDate:(NSDate *)date dateStyle:(NSDateFormatterStyle)dstyle timeStyle:(NSDateFormatterStyle)tstyle {
    /* +localizedStringFromDate: dates the book to the behavior-10_0 era: it
     * renders the hardcoded classic patterns (never the ICU style-derived
     * ones), and joins with ", " for short dates but " at " otherwise. */
    NSDateFormatter *f = [[NSDateFormatter alloc] init];
    [f setLocale:[NSLocale localeWithLocaleIdentifier:@"en_US"]];
    NSString *datePart = nil;
    NSString *timePart = nil;
    if (dstyle != NSDateFormatterNoStyle) {
        [f setDateFormat:(dstyle == NSDateFormatterShortStyle ? @"d.M.yyyy"
                          : dstyle == NSDateFormatterMediumStyle ? @"d MMM yyyy"
                          : dstyle == NSDateFormatterLongStyle ? @"d MMMM yyyy"
                          : @"EEEE, d MMMM yyyy")];
        datePart = [f stringFromDate:date];
    }
    if (tstyle != NSDateFormatterNoStyle) {
        [f setDateFormat:(tstyle == NSDateFormatterShortStyle ? @"HH:mm"
                          : tstyle == NSDateFormatterMediumStyle ? @"HH:mm:ss"
                          : tstyle == NSDateFormatterLongStyle ? @"HH:mm:ss z"
                          : @"HH:mm:ss zzzz")];
        timePart = [f stringFromDate:date];
    }
    if (datePart == nil) {
        if (timePart != nil) return timePart;
        return @"";
    }
    if (timePart == nil) return datePart;
    return [NSString stringWithFormat:@"%@%@%@", datePart,
            dstyle == NSDateFormatterShortStyle ? @", " : @" at ", timePart];
}

+ (NSString *)dateFormatFromTemplate:(NSString *)tmplate options:(NSUInteger)opts locale:(NSLocale *)locale {
    CFLocaleRef cfLocale = NULL;
    if (locale != nil) {
        if ([locale isKindOfClass:[NSLocale class]]) cfLocale = [locale _backingLocale];
        else cfLocale = NSFORMATTER_CF(CFLocaleRef, locale);
    }
    CFStringRef format = CFDateFormatterCreateDateFormatFromTemplate(
        kCFAllocatorDefault, NSFORMATTER_CF(CFStringRef, tmplate), (CFOptionFlags)opts, cfLocale);
    if (format == NULL) return nil;
    return NSFORMATTER_TRANSFER(format);
}

- (instancetype)init {
    return [self initWithDateFormat:nil locale:[NSLocale currentLocale]];
}

- (instancetype)initWithDateFormat:(NSString *)format locale:(NSLocale *)locale {
    self = [super init];
    if (self != nil) {
        CFLocaleRef cfLocale = NULL;
        if (locale != nil) {
            if ([locale isKindOfClass:[NSLocale class]]) cfLocale = [locale _backingLocale];
            else cfLocale = NSFORMATTER_CF(CFLocaleRef, locale);
        }
        _formatter = CFDateFormatterCreate(kCFAllocatorDefault, cfLocale,
                                            kCFDateFormatterNoStyle,
                                            kCFDateFormatterNoStyle);
        if (format != nil) CFDateFormatterSetFormat(_formatter, NSFORMATTER_CF(CFStringRef, format));
    }
    return self;
}

- (void)dealloc {
    if (_formatter != NULL) CFRelease(_formatter);
#if !__has_feature(objc_arc)
    [_symbolOverrides release];
    [super dealloc];
#endif
}

- (NSArray<NSString *> *)_symbolArrayForKey:(CFStringRef)key shadow:(NSString *)shadow {
    if (_symbolOverrides != nil) {
        NSArray *override = [_symbolOverrides objectForKey:shadow];
        if (override != nil) return override;
    }
    return NSFORMATTER_TRANSFER(CFDateFormatterCopyProperty(_formatter, key));
}

- (void)_setSymbolArray:(NSArray<NSString *> *)symbols forKey:(CFStringRef)key shadow:(NSString *)shadow {
    if (_symbolOverrides == nil) _symbolOverrides = [NSMutableDictionary dictionary];
    [_symbolOverrides setObject:[symbols copy] forKey:shadow];
    CFDateFormatterSetProperty(_formatter, key, NSFORMATTER_CF(CFArrayRef, symbols));
}

- (NSDateFormatterStyle)dateStyle {
    return (NSDateFormatterStyle)CFDateFormatterGetDateStyle(_formatter);
}

- (void)setDateStyle:(NSDateFormatterStyle)style {
    CFDateFormatterRef replacement = CFDateFormatterCreate(
        kCFAllocatorDefault, CFDateFormatterGetLocale(_formatter),
        (CFDateFormatterStyle)style, CFDateFormatterGetTimeStyle(_formatter));
    if (replacement == NULL) return;
    CFRelease(_formatter);
    _formatter = replacement;
}

- (NSDateFormatterStyle)timeStyle {
    return (NSDateFormatterStyle)CFDateFormatterGetTimeStyle(_formatter);
}

- (void)setTimeStyle:(NSDateFormatterStyle)style {
    CFDateFormatterRef replacement = CFDateFormatterCreate(
        kCFAllocatorDefault, CFDateFormatterGetLocale(_formatter),
        CFDateFormatterGetDateStyle(_formatter), (CFDateFormatterStyle)style);
    if (replacement == NULL) return;
    CFRelease(_formatter);
    _formatter = replacement;
}

- (NSString *)dateFormat {
    return NSFORMATTER_TRANSFER(CFRetain(CFDateFormatterGetFormat(_formatter)));
}

- (void)setDateFormat:(NSString *)format {
    CFDateFormatterSetFormat(_formatter, NSFORMATTER_CF(CFStringRef, format));
}

- (void)setLocalizedDateFormatFromTemplate:(NSString *)dateFormatTemplate {
    CFStringRef format = CFDateFormatterCreateDateFormatFromTemplate(
        kCFAllocatorDefault, NSFORMATTER_CF(CFStringRef, dateFormatTemplate), 0,
        CFDateFormatterGetLocale(_formatter));
    if (format == NULL) return;
    CFDateFormatterSetFormat(_formatter, format);
    CFRelease(format);
}

- (NSLocale *)locale {
    return NSFORMATTER_TRANSFER(CFLocaleCreateCopy(kCFAllocatorDefault,
                                                   CFDateFormatterGetLocale(_formatter)));
}

- (void)setLocale:(NSLocale *)locale {
    if (locale == nil) locale = [NSLocale currentLocale];
    CFLocaleRef cfLocale = NULL;
    if ([locale isKindOfClass:[NSLocale class]]) {
        cfLocale = [locale _backingLocale];
    } else {
        cfLocale = NSFORMATTER_CF(CFLocaleRef, locale);
    }
    /* CFDateFormatterSetLocale is SPI; recreate like setDateStyle does. */
    CFDateFormatterRef replacement = CFDateFormatterCreate(
        kCFAllocatorDefault, cfLocale, CFDateFormatterGetDateStyle(_formatter),
        CFDateFormatterGetTimeStyle(_formatter));
    if (replacement == NULL) return;
    CFStringRef format = CFDateFormatterGetFormat(_formatter);
    if (format != NULL) CFDateFormatterSetFormat(replacement, format);
    CFRelease(_formatter);
    _formatter = replacement;
}

- (BOOL)isLenient {
    CFTypeRef value = CFDateFormatterCopyProperty(_formatter, kCFDateFormatterIsLenient);
    BOOL lenient = value != NULL && CFBooleanGetValue((CFBooleanRef)value);
    if (value != NULL) CFRelease(value);
    return lenient;
}

- (void)setLenient:(BOOL)lenient {
    CFDateFormatterSetProperty(_formatter, kCFDateFormatterIsLenient,
                               lenient ? kCFBooleanTrue : kCFBooleanFalse);
}

- (NSDate *)defaultDate {
    CFDateRef date = CFDateFormatterCopyProperty(_formatter, kCFDateFormatterDefaultDate);
    if (date == NULL) return nil;
    NSDate *result = [NSDate dateWithTimeIntervalSinceReferenceDate:CFDateGetAbsoluteTime(date)];
    CFRelease(date);
    return result;
}

- (void)setDefaultDate:(NSDate *)date {
    CFDateFormatterSetProperty(_formatter, kCFDateFormatterDefaultDate,
                               date ? NSFORMATTER_CF(CFDateRef, date) : NULL);
}

- (BOOL)doesRelativeDateFormatting {
    CFTypeRef value = CFDateFormatterCopyProperty(_formatter, kCFDateFormatterDoesRelativeDateFormattingKey);
    BOOL relative = value != NULL && CFBooleanGetValue((CFBooleanRef)value);
    if (value != NULL) CFRelease(value);
    return relative;
}

- (void)setDoesRelativeDateFormatting:(BOOL)flag {
    CFDateFormatterSetProperty(_formatter, kCFDateFormatterDoesRelativeDateFormattingKey,
                               flag ? kCFBooleanTrue : kCFBooleanFalse);
}

- (NSDate *)gregorianStartDate {
    CFDateRef date = CFDateFormatterCopyProperty(_formatter, kCFDateFormatterGregorianStartDate);
    if (date == NULL) return nil;
    NSDate *result = [NSDate dateWithTimeIntervalSinceReferenceDate:CFDateGetAbsoluteTime(date)];
    CFRelease(date);
    return result;
}

- (void)setGregorianStartDate:(NSDate *)date {
    CFDateFormatterSetProperty(_formatter, kCFDateFormatterGregorianStartDate,
                               date ? NSFORMATTER_CF(CFDateRef, date) : NULL);
}

- (NSTimeZone *)timeZone {
    CFTimeZoneRef tz = CFDateFormatterCopyProperty(_formatter, kCFDateFormatterTimeZone);
    if (tz == NULL) return [NSTimeZone systemTimeZone];
    NSTimeZone *result = [NSTimeZone timeZoneWithName:
        NSFORMATTER_TRANSFER(CFStringCreateCopy(kCFAllocatorDefault,
                                                CFTimeZoneGetName(tz)))];
    CFRelease(tz);
    return result;
}

- (void)setTimeZone:(NSTimeZone *)tz {
    if (tz == nil) {
        CFDateFormatterSetProperty(_formatter, kCFDateFormatterTimeZone, NULL);
        return;
    }
    CFTimeZoneRef cfTz = CFTimeZoneCreateWithName(kCFAllocatorDefault,
                                                   NSFORMATTER_CF(CFStringRef, [tz name]),
                                                   false);
    if (cfTz == NULL) return;
    CFDateFormatterSetProperty(_formatter, kCFDateFormatterTimeZone, cfTz);
    CFRelease(cfTz);
}

- (NSCalendar *)calendar {
    CFCalendarRef cal = CFDateFormatterCopyProperty(_formatter, kCFDateFormatterCalendar);
    if (cal == NULL) return [NSCalendar currentCalendar];
    return [[NSCalendar alloc] _initWithBackingCalendar:cal];
}

- (void)setCalendar:(NSCalendar *)cal {
    if (cal == nil) {
        CFCalendarRef cur = CFCalendarCopyCurrent();
        if (cur != NULL) {
            CFDateFormatterSetProperty(_formatter, kCFDateFormatterCalendar, cur);
            CFRelease(cur);
        }
        return;
    }
    CFDateFormatterSetProperty(_formatter, kCFDateFormatterCalendar, [cal _backingCalendar]);
}

- (NSArray<NSString *> *)eraSymbols {
    return [self _symbolArrayForKey:kCFDateFormatterEraSymbols shadow:@"eraSymbols"];
}

- (void)setEraSymbols:(NSArray<NSString *> *)eraSymbols {
    [self _setSymbolArray:eraSymbols forKey:kCFDateFormatterEraSymbols shadow:@"eraSymbols"];
}

- (NSArray<NSString *> *)monthSymbols {
    return [self _symbolArrayForKey:kCFDateFormatterMonthSymbols shadow:@"monthSymbols"];
}

- (void)setMonthSymbols:(NSArray<NSString *> *)monthSymbols {
    [self _setSymbolArray:monthSymbols forKey:kCFDateFormatterMonthSymbols shadow:@"monthSymbols"];
}

- (NSArray<NSString *> *)shortMonthSymbols {
    return [self _symbolArrayForKey:kCFDateFormatterShortMonthSymbols shadow:@"shortMonthSymbols"];
}

- (void)setShortMonthSymbols:(NSArray<NSString *> *)shortMonthSymbols {
    [self _setSymbolArray:shortMonthSymbols forKey:kCFDateFormatterShortMonthSymbols shadow:@"shortMonthSymbols"];
}

- (NSArray<NSString *> *)veryShortMonthSymbols {
    return [self _symbolArrayForKey:kCFDateFormatterVeryShortMonthSymbols shadow:@"veryShortMonthSymbols"];
}

- (void)setVeryShortMonthSymbols:(NSArray<NSString *> *)veryShortMonthSymbols {
    [self _setSymbolArray:veryShortMonthSymbols forKey:kCFDateFormatterVeryShortMonthSymbols shadow:@"veryShortMonthSymbols"];
}

- (NSArray<NSString *> *)weekdaySymbols {
    return [self _symbolArrayForKey:kCFDateFormatterWeekdaySymbols shadow:@"weekdaySymbols"];
}

- (void)setWeekdaySymbols:(NSArray<NSString *> *)weekdaySymbols {
    [self _setSymbolArray:weekdaySymbols forKey:kCFDateFormatterWeekdaySymbols shadow:@"weekdaySymbols"];
}

- (NSArray<NSString *> *)shortWeekdaySymbols {
    return [self _symbolArrayForKey:kCFDateFormatterShortWeekdaySymbols shadow:@"shortWeekdaySymbols"];
}

- (void)setShortWeekdaySymbols:(NSArray<NSString *> *)shortWeekdaySymbols {
    [self _setSymbolArray:shortWeekdaySymbols forKey:kCFDateFormatterShortWeekdaySymbols shadow:@"shortWeekdaySymbols"];
}

- (NSArray<NSString *> *)veryShortWeekdaySymbols {
    return [self _symbolArrayForKey:kCFDateFormatterVeryShortWeekdaySymbols shadow:@"veryShortWeekdaySymbols"];
}

- (void)setVeryShortWeekdaySymbols:(NSArray<NSString *> *)veryShortWeekdaySymbols {
    [self _setSymbolArray:veryShortWeekdaySymbols forKey:kCFDateFormatterVeryShortWeekdaySymbols shadow:@"veryShortWeekdaySymbols"];
}

- (NSArray<NSString *> *)longEraSymbols {
    return [self _symbolArrayForKey:kCFDateFormatterLongEraSymbols shadow:@"longEraSymbols"];
}

- (void)setLongEraSymbols:(NSArray<NSString *> *)longEraSymbols {
    [self _setSymbolArray:longEraSymbols forKey:kCFDateFormatterLongEraSymbols shadow:@"longEraSymbols"];
}

- (NSArray<NSString *> *)standaloneMonthSymbols {
    return [self _symbolArrayForKey:kCFDateFormatterStandaloneMonthSymbols shadow:@"standaloneMonthSymbols"];
}

- (void)setStandaloneMonthSymbols:(NSArray<NSString *> *)standaloneMonthSymbols {
    [self _setSymbolArray:standaloneMonthSymbols forKey:kCFDateFormatterStandaloneMonthSymbols shadow:@"standaloneMonthSymbols"];
}

- (NSArray<NSString *> *)shortStandaloneMonthSymbols {
    return [self _symbolArrayForKey:kCFDateFormatterShortStandaloneMonthSymbols shadow:@"shortStandaloneMonthSymbols"];
}

- (void)setShortStandaloneMonthSymbols:(NSArray<NSString *> *)shortStandaloneMonthSymbols {
    [self _setSymbolArray:shortStandaloneMonthSymbols forKey:kCFDateFormatterShortStandaloneMonthSymbols shadow:@"shortStandaloneMonthSymbols"];
}

- (NSArray<NSString *> *)veryShortStandaloneMonthSymbols {
    return [self _symbolArrayForKey:kCFDateFormatterVeryShortStandaloneMonthSymbols shadow:@"veryShortStandaloneMonthSymbols"];
}

- (void)setVeryShortStandaloneMonthSymbols:(NSArray<NSString *> *)veryShortStandaloneMonthSymbols {
    [self _setSymbolArray:veryShortStandaloneMonthSymbols forKey:kCFDateFormatterVeryShortStandaloneMonthSymbols shadow:@"veryShortStandaloneMonthSymbols"];
}

- (NSArray<NSString *> *)standaloneWeekdaySymbols {
    return [self _symbolArrayForKey:kCFDateFormatterStandaloneWeekdaySymbols shadow:@"standaloneWeekdaySymbols"];
}

- (void)setStandaloneWeekdaySymbols:(NSArray<NSString *> *)standaloneWeekdaySymbols {
    [self _setSymbolArray:standaloneWeekdaySymbols forKey:kCFDateFormatterStandaloneWeekdaySymbols shadow:@"standaloneWeekdaySymbols"];
}

- (NSArray<NSString *> *)shortStandaloneWeekdaySymbols {
    return [self _symbolArrayForKey:kCFDateFormatterShortStandaloneWeekdaySymbols shadow:@"shortStandaloneWeekdaySymbols"];
}

- (void)setShortStandaloneWeekdaySymbols:(NSArray<NSString *> *)shortStandaloneWeekdaySymbols {
    [self _setSymbolArray:shortStandaloneWeekdaySymbols forKey:kCFDateFormatterShortStandaloneWeekdaySymbols shadow:@"shortStandaloneWeekdaySymbols"];
}

- (NSArray<NSString *> *)veryShortStandaloneWeekdaySymbols {
    return [self _symbolArrayForKey:kCFDateFormatterVeryShortStandaloneWeekdaySymbols shadow:@"veryShortStandaloneWeekdaySymbols"];
}

- (void)setVeryShortStandaloneWeekdaySymbols:(NSArray<NSString *> *)veryShortStandaloneWeekdaySymbols {
    [self _setSymbolArray:veryShortStandaloneWeekdaySymbols forKey:kCFDateFormatterVeryShortStandaloneWeekdaySymbols shadow:@"veryShortStandaloneWeekdaySymbols"];
}

- (NSArray<NSString *> *)quarterSymbols {
    return [self _symbolArrayForKey:kCFDateFormatterQuarterSymbols shadow:@"quarterSymbols"];
}

- (void)setQuarterSymbols:(NSArray<NSString *> *)quarterSymbols {
    [self _setSymbolArray:quarterSymbols forKey:kCFDateFormatterQuarterSymbols shadow:@"quarterSymbols"];
}

- (NSArray<NSString *> *)shortQuarterSymbols {
    return [self _symbolArrayForKey:kCFDateFormatterShortQuarterSymbols shadow:@"shortQuarterSymbols"];
}

- (void)setShortQuarterSymbols:(NSArray<NSString *> *)shortQuarterSymbols {
    [self _setSymbolArray:shortQuarterSymbols forKey:kCFDateFormatterShortQuarterSymbols shadow:@"shortQuarterSymbols"];
}

- (NSArray<NSString *> *)standaloneQuarterSymbols {
    return [self _symbolArrayForKey:kCFDateFormatterStandaloneQuarterSymbols shadow:@"standaloneQuarterSymbols"];
}

- (void)setStandaloneQuarterSymbols:(NSArray<NSString *> *)standaloneQuarterSymbols {
    [self _setSymbolArray:standaloneQuarterSymbols forKey:kCFDateFormatterStandaloneQuarterSymbols shadow:@"standaloneQuarterSymbols"];
}

- (NSArray<NSString *> *)shortStandaloneQuarterSymbols {
    return [self _symbolArrayForKey:kCFDateFormatterShortStandaloneQuarterSymbols shadow:@"shortStandaloneQuarterSymbols"];
}

- (void)setShortStandaloneQuarterSymbols:(NSArray<NSString *> *)shortStandaloneQuarterSymbols {
    [self _setSymbolArray:shortStandaloneQuarterSymbols forKey:kCFDateFormatterShortStandaloneQuarterSymbols shadow:@"shortStandaloneQuarterSymbols"];
}

- (NSString *)AMSymbol {
    return NSFORMATTER_TRANSFER(CFDateFormatterCopyProperty(_formatter, kCFDateFormatterAMSymbol));
}

- (void)setAMSymbol:(NSString *)AMSymbol {
    CFDateFormatterSetProperty(_formatter, kCFDateFormatterAMSymbol, NSFORMATTER_CF(CFStringRef, AMSymbol));
}

- (NSString *)PMSymbol {
    return NSFORMATTER_TRANSFER(CFDateFormatterCopyProperty(_formatter, kCFDateFormatterPMSymbol));
}

- (void)setPMSymbol:(NSString *)PMSymbol {
    CFDateFormatterSetProperty(_formatter, kCFDateFormatterPMSymbol, NSFORMATTER_CF(CFStringRef, PMSymbol));
}

- (NSString *)stringFromDate:(NSDate *)date {
    return NSFORMATTER_TRANSFER(CFDateFormatterCreateStringWithDate(
        kCFAllocatorDefault, _formatter, NSFORMATTER_CF(CFDateRef, date)));
}

- (NSDate *)dateFromString:(NSString *)string {
    CFDateRef date = CFDateFormatterCreateDateFromString(
        kCFAllocatorDefault, _formatter, NSFORMATTER_CF(CFStringRef, string), NULL);
    if (date == NULL) return nil;
    NSDate *result = [NSDate dateWithTimeIntervalSinceReferenceDate:CFDateGetAbsoluteTime(date)];
    CFRelease(date);
    return result;
}

- (BOOL)getObjectValue:(id *)obj forString:(NSString *)string range:(NSRange *)rangep error:(NSError **)error {
    if (obj == nil) return NO;
    *obj = nil;
    if (error != nil) *error = nil;
    CFRange range = CFRangeMake(rangep ? rangep->location : 0, rangep ? rangep->length : 0);
    CFAbsoluteTime absolute = 0.0;
    Boolean ok = CFDateFormatterGetAbsoluteTimeFromString(
        _formatter, NSFORMATTER_CF(CFStringRef, string), rangep ? &range : NULL, &absolute);
    if (!ok) {
        if (error != nil) {
            *error = [NSError errorWithDomain:NSCocoaErrorDomain code:NSFormattingError
                        userInfo:@{ NSLocalizedDescriptionKey: @"Could not be parsed." }];
        }
        return NO;
    }
    *obj = [NSDate dateWithTimeIntervalSinceReferenceDate:absolute];
    if (rangep != NULL) {
        rangep->location = range.location;
        rangep->length = range.length;
    }
    return YES;
}

@end
