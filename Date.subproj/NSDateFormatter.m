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
    [super dealloc];
#endif
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
