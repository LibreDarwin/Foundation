/*
 * Copyright (C) 2026, Samuel Zormeister.
 *
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */

#import <Foundation/NSDate.h>
#include <CoreFoundation/CFDate.h>
#include <CoreFoundation/ForFoundationOnly.h>

#if __has_feature(objc_arc)
#define NSDATE_TRANSFER(value) ((__bridge_transfer id)(value))
#define NSDATE_CF(type, value) ((__bridge type)(value))
#else
#define NSDATE_TRANSFER(value) ((id)CFAutorelease(value))
#define NSDATE_CF(type, value) ((type)(value))
#endif

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

- (NSComparisonResult)compare:(NSDate *)other {
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
    return NSDATE_TRANSFER(CFDateCreate(kCFAllocatorDefault,
                                        CFDateGetAbsoluteTime(NSDATE_CF(CFDateRef, self))));
}

@end

#if DEPLOYMENT_RUNTIME_OBJC
__attribute__((constructor))
static void __NSCFDateBridgeInit(void) {
    _CFRuntimeBridgeClasses(CFDateGetTypeID(), "NSDate");
}
#endif
