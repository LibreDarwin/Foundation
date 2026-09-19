/*
 * Copyright (C) 2026, Samuel Zormeister.
 *
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */

#import <Foundation/NSDateFormatter.h>
#include <CoreFoundation/CFDateFormatter.h>

#if __has_feature(objc_arc)
#define NSFORMATTER_TRANSFER(value) ((__bridge_transfer id)(value))
#define NSFORMATTER_CF(type, value) ((__bridge type)(value))
#else
#define NSFORMATTER_TRANSFER(value) ((id)CFAutorelease(value))
#define NSFORMATTER_CF(type, value) ((type)(value))
#endif

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
        CFLocaleRef cfLocale = NSFORMATTER_CF(CFLocaleRef, locale);
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

@end
