/*
 * Copyright (C) 2026, Samuel Zormeister.
 *
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */

#import <Foundation/NSDate.h>
#import <Foundation/NSCoder.h>
#import <Foundation/NSException.h>
#import <Foundation/NSNumber.h>
#import <Foundation/NSString.h>
#include <CoreFoundation/CFDate.h>
#include <CoreFoundation/ForFoundationOnly.h>
#include <math.h>

#if __has_feature(objc_arc)
#define NSDATE_TRANSFER(value) ((__bridge_transfer id)(value))
#define NSDATE_CF(type, value) ((__bridge type)(value))
#else
#define NSDATE_TRANSFER(value) ((id)CFAutorelease(value))
#define NSDATE_CF(type, value) ((type)(value))
#endif

const NSTimeInterval NSTimeIntervalSince1970 = 978307200.0;

/* NSDate and CFDate share the same epoch - 2001-01-01 00:00:00 GMT - so the
 * reference-date interval passes through untouched. Only the 1970 accessors
 * need the offset. */
@implementation NSDate

+ (instancetype)date {
    return [self dateWithTimeIntervalSinceReferenceDate:CFAbsoluteTimeGetCurrent()];
}

+ (instancetype)now {
    return [self date];
}

+ (NSTimeInterval)timeIntervalSinceReferenceDate {
    return (NSTimeInterval)CFAbsoluteTimeGetCurrent();
}

/* The two sentinel dates are fixed points, not "far enough away" guesses: they
 * are the same values the rest of the family uses, so a date produced here
 * compares and sorts against them the way callers expect. */
+ (instancetype)distantFuture {
    return [self dateWithTimeIntervalSinceReferenceDate:63113904000.0];
}

+ (instancetype)distantPast {
    return [self dateWithTimeIntervalSinceReferenceDate:-63114076800.0];
}

+ (instancetype)dateWithTimeIntervalSinceNow:(NSTimeInterval)seconds {
    return [self dateWithTimeIntervalSinceReferenceDate:CFAbsoluteTimeGetCurrent() + seconds];
}

+ (instancetype)dateWithTimeIntervalSinceReferenceDate:(NSTimeInterval)seconds {
    CFDateRef result = CFDateCreate(kCFAllocatorDefault, (CFAbsoluteTime)seconds);
    return NSDATE_TRANSFER(result);
}

+ (instancetype)dateWithTimeIntervalSince1970:(NSTimeInterval)seconds {
    return [self dateWithTimeIntervalSinceReferenceDate:
            seconds - kCFAbsoluteTimeIntervalSince1970];
}

/* NSDate is immutable, so every init returns a freshly minted CF date in place
 * of the empty +alloc result (ARC releases that receiver and keeps the value
 * we return). This keeps alloc/init correct without placeholder machinery and
 * without breaking the CFDate toll-free identity of the returned object. */
- (instancetype)init {
    return [NSDate date];
}

- (instancetype)initWithTimeIntervalSinceReferenceDate:(NSTimeInterval)seconds {
    return [NSDate dateWithTimeIntervalSinceReferenceDate:seconds];
}

- (instancetype)initWithTimeIntervalSinceNow:(NSTimeInterval)seconds {
    return [NSDate dateWithTimeIntervalSinceNow:seconds];
}

- (instancetype)initWithTimeIntervalSince1970:(NSTimeInterval)seconds {
    return [NSDate dateWithTimeIntervalSince1970:seconds];
}

- (NSTimeInterval)timeIntervalSinceReferenceDate {
    return (NSTimeInterval)CFDateGetAbsoluteTime(NSDATE_CF(CFDateRef, self));
}

- (NSTimeInterval)timeIntervalSince1970 {
    return [self timeIntervalSinceReferenceDate] + kCFAbsoluteTimeIntervalSince1970;
}

- (NSTimeInterval)timeIntervalSinceDate:(NSDate *)other {
    return (NSTimeInterval)CFDateGetTimeIntervalSinceDate(NSDATE_CF(CFDateRef, self),
                                                          NSDATE_CF(CFDateRef, other));
}

- (NSTimeInterval)timeIntervalSinceNow {
    return [self timeIntervalSinceReferenceDate] - CFAbsoluteTimeGetCurrent();
}

- (instancetype)dateByAddingTimeInterval:(NSTimeInterval)seconds {
    return [NSDate dateWithTimeIntervalSinceReferenceDate:
            [self timeIntervalSinceReferenceDate] + seconds];
}

- (instancetype)addingTimeInterval:(NSTimeInterval)seconds {
    return [self dateByAddingTimeInterval:seconds];
}

- (NSDate *)earlierDate:(NSDate *)anotherDate {
    return [self compare:anotherDate] == NSOrderedAscending ? self : anotherDate;
}

- (NSDate *)laterDate:(NSDate *)anotherDate {
    return [self compare:anotherDate] == NSOrderedDescending ? self : anotherDate;
}

- (NSComparisonResult)compare:(NSDate *)other {
    if (other == nil) {
        /* Matches Apple: -compare:nil returns NSOrderedSame, no exception. */
        return NSOrderedSame;
    }
    return (NSComparisonResult)CFDateCompare(NSDATE_CF(CFDateRef, self),
                                             NSDATE_CF(CFDateRef, other), NULL);
}

- (BOOL)isEqualToDate:(NSDate *)other {
    return other != nil && [self compare:other] == NSOrderedSame;
}

- (BOOL)isEqual:(id)object {
    return object != nil && CFEqual(NSDATE_CF(CFTypeRef, self),
                                    NSDATE_CF(CFTypeRef, object));
}

- (NSUInteger)hash {
    return (NSUInteger)CFHash(NSDATE_CF(CFTypeRef, self));
}

- (id)copyWithZone:(NSZone *)zone {
    (void)zone;
    /* NSDate is immutable: copying yields the same instance, like Apple. */
    return self;
}

/* Howard Hinnant's civil_from_days inverse (public-domain algorithm): turn a
 * count of days since 1970-01-01 into a proleptic-Gregorian Y/M/D. */
static void NSDateCivilFromDays(long long z, long long *year,
                                long long *month, long long *day) {
    z += 719468;
    long long era = (z >= 0 ? z : z - 146096) / 146097;
    long long doe = z - era * 146097;
    long long yoe = (doe - doe / 1460 + doe / 36524 - doe / 146096) / 365;
    long long y = yoe + era * 400;
    long long doy = doe - (365 * yoe + yoe / 4 - yoe / 100);
    long long mp = (5 * doy + 2) / 153;
    long long d = doy - (153 * mp + 2) / 5 + 1;
    long long m = mp + (mp < 10 ? 3 : -9);
    y += (m <= 2);
    *year = y;
    *month = m;
    *day = d;
}

/* Apple renders -description in GMT regardless of the process locale; only
 * -descriptionWithLocale: honors a caller-supplied locale (which for now we
 * leave as GMT — full localization lands with the NSLocale work). */
- (NSString *)description {
    double sec1970 = [self timeIntervalSince1970];
    double days = floor(sec1970 / 86400.0);
    double secOfDay = sec1970 - days * 86400.0;
    long long hour = (long long)(secOfDay / 3600.0);
    long long min = (long long)((secOfDay - hour * 3600.0) / 60.0);
    long long sec = (long long)(secOfDay - hour * 3600.0 - min * 60.0);

    long long y, m, d;
    NSDateCivilFromDays((long long)days, &y, &m, &d);
    return [NSString stringWithFormat:@"%04lld-%02lld-%02lld %02lld:%02lld:%02lld +0000",
            y, m, d, hour, min, sec];
}

- (NSString *)descriptionWithLocale:(id)locale {
    (void)locale;
    return [self description];
}

- (void)encodeWithCoder:(NSCoder *)coder {
    NSTimeInterval interval = [self timeIntervalSinceReferenceDate];
    if ([coder allowsKeyedCoding]) {
        /* Matches Apple's archive layout: the interval is stored as a double
         * under the key "NS.time". */
        [coder encodeDouble:interval forKey:@"NS.time"];
    } else {
        [coder encodeObject:[NSNumber numberWithDouble:interval]];
    }
}

- (instancetype)initWithCoder:(NSCoder *)coder {
    NSTimeInterval interval;
    if ([coder allowsKeyedCoding]) {
        interval = [coder decodeDoubleForKey:@"NS.time"];
    } else {
        NSNumber *number = [coder decodeObject];
        interval = number ? [number doubleValue] : 0.0;
    }
    return [NSDate dateWithTimeIntervalSinceReferenceDate:interval];
}

+ (BOOL)supportsSecureCoding {
    return YES;
}

@end

#if DEPLOYMENT_RUNTIME_OBJC
__attribute__((constructor))
static void __NSCFDateBridgeInit(void) {
    _CFRuntimeBridgeClasses(CFDateGetTypeID(), "NSDate");
}
#endif
