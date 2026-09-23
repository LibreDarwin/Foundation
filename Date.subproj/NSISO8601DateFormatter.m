/*
 * Copyright (C) 2026, Samuel Zormeister.
 *
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */

#import <Foundation/NSISO8601DateFormatter.h>
#import <Foundation/NSTimeZone.h>
#import <Foundation/NSDate.h>
#import <Foundation/NSCoder.h>
#import <Foundation/NSNumber.h>
#import <Foundation/NSString.h>
#include <CoreFoundation/CFDateFormatter.h>
#include <CoreFoundation/CFDate.h>

/* LibreDarwin CoreFoundation predates the ISO8601 formatter API (macOS 10.12);
 * the host CoreFoundation, which the gate links, exports the symbol. */
extern CFDateFormatterRef CFDateFormatterCreateISO8601Formatter(
    CFAllocatorRef allocator, CFOptionFlags formatOptions);

#if __has_feature(objc_arc)
#define NSISO_TRANSFER(value) ((__bridge_transfer id)(value))
#define NSISO_CF(type, value) ((__bridge type)(value))
#else
#define NSISO_TRANSFER(value) ((id)CFAutorelease(value))
#define NSISO_CF(type, value) ((type)(value))
#endif

/* Apple's -init preconfigures with RFC 3339 plus the two colon separators,
 * and the formatOptions getter exposes that stored mask verbatim (1907). */
static const NSISO8601DateFormatOptions NSISO8601DefaultOptions =
    NSISO8601DateFormatWithInternetDateTime |
    NSISO8601DateFormatWithColonSeparatorInTime |
    NSISO8601DateFormatWithColonSeparatorInTimeZone;

@implementation NSISO8601DateFormatter

- (instancetype)init {
    self = [super init];
    if (self != nil) {
        _formatter = NULL;
        _timeZone = nil;
        _formatOptions = NSISO8601DefaultOptions;
        _formatter = [self _rebuildFormatter];
    }
    return self;
}

- (void)dealloc {
    if (_formatter != NULL) CFRelease(_formatter);
    _formatter = NULL;
}

/* The CF ISO8601 formatter is created with a fixed options mask (it has no
 * options setter), so any change to formatOptions or timeZone rebuilds it —
 * exactly the "resetting can be expensive" behavior Apple documents. */
- (CFDateFormatterRef)_rebuildFormatter {
    if (_formatter != NULL) CFRelease(_formatter);
    _formatter = NULL;
    _formatter = CFDateFormatterCreateISO8601Formatter(
        kCFAllocatorDefault, (CFOptionFlags)_formatOptions);
    if (_formatter != NULL) {
        NSTimeZone *tz = [self timeZone];
        if (tz != nil) {
            CFDateFormatterSetProperty(_formatter, kCFDateFormatterTimeZone,
                                       NSISO_CF(CFTimeZoneRef, tz));
        }
    }
    return _formatter;
}

- (NSTimeZone *)timeZone {
    return _timeZone ?: [NSTimeZone timeZoneForSecondsFromGMT:0];
}

- (void)setTimeZone:(NSTimeZone *)timeZone {
    _timeZone = [timeZone copy];
    [self _rebuildFormatter];
}

- (NSISO8601DateFormatOptions)formatOptions {
    return _formatOptions;
}

- (void)setFormatOptions:(NSISO8601DateFormatOptions)formatOptions {
    if (_formatOptions != formatOptions) {
        _formatOptions = formatOptions;
        [self _rebuildFormatter];
    }
}

- (NSString *)stringFromDate:(NSDate *)date {
    if (_formatter == NULL || date == nil) return nil;
    CFStringRef result = CFDateFormatterCreateStringWithDate(
        kCFAllocatorDefault, _formatter, NSISO_CF(CFDateRef, date));
    if (result == NULL) return nil;
    return (NSString *)NSISO_TRANSFER(result);
}

- (NSDate *)dateFromString:(NSString *)string {
    if (_formatter == NULL || string == nil) return nil;
    CFStringRef cfString = NSISO_CF(CFStringRef, string);
    CFRange range = CFRangeMake(0, (CFIndex)[string length]);
    CFDateRef date = CFDateFormatterCreateDateFromString(
        kCFAllocatorDefault, _formatter, cfString, &range);
    if (date == NULL) return nil;
    NSDate *result =
        [NSDate dateWithTimeIntervalSinceReferenceDate:CFDateGetAbsoluteTime(date)];
    CFRelease(date);
    return result;
}

+ (NSString *)stringFromDate:(NSDate *)date timeZone:(NSTimeZone *)timeZone formatOptions:(NSISO8601DateFormatOptions)formatOptions {
    NSISO8601DateFormatter *formatter = [[self alloc] init];
    formatter.timeZone = timeZone;
    formatter.formatOptions = formatOptions;
    return [formatter stringFromDate:date];
}

- (void)encodeWithCoder:(NSCoder *)coder {
    [coder encodeInteger:(NSInteger)_formatOptions forKey:@"NS.formatOptions"];
    if (_timeZone != nil) [coder encodeObject:_timeZone forKey:@"NS.timeZone"];
}

- (instancetype)initWithCoder:(NSCoder *)coder {
    self = [self init];
    if (self != nil) {
        _formatOptions = (NSISO8601DateFormatOptions)[coder decodeIntegerForKey:@"NS.formatOptions"];
        NSTimeZone *timeZone = [coder decodeObjectForKey:@"NS.timeZone"];
        if (timeZone != nil) _timeZone = [timeZone copy];
        _formatter = [self _rebuildFormatter];
    }
    return self;
}

+ (BOOL)supportsSecureCoding {
    return YES;
}

@end