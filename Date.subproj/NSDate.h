/*
 * Copyright (C) 2026, Samuel Zormeister.
 *
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */

#ifndef NSDate_h
#define NSDate_h

#import <Foundation/NSObject.h>
#import <Foundation/NSObjCRuntime.h>

typedef double NSTimeInterval;

FOUNDATION_EXPORT const NSTimeInterval NSTimeIntervalSince1970;

@interface NSDate : NSObject <NSCopying, NSCoding, NSSecureCoding>

+ (instancetype)date;
+ (instancetype)now;
+ (instancetype)distantFuture;
+ (instancetype)distantPast;
+ (instancetype)dateWithTimeIntervalSinceNow:(NSTimeInterval)seconds;
+ (instancetype)dateWithTimeIntervalSinceReferenceDate:(NSTimeInterval)seconds;
+ (instancetype)dateWithTimeIntervalSince1970:(NSTimeInterval)seconds;
+ (NSTimeInterval)timeIntervalSinceReferenceDate;

- (instancetype)init;
- (instancetype)initWithTimeIntervalSinceReferenceDate:(NSTimeInterval)seconds;
- (instancetype)initWithTimeIntervalSinceNow:(NSTimeInterval)seconds;
- (instancetype)initWithTimeIntervalSince1970:(NSTimeInterval)seconds;

- (NSTimeInterval)timeIntervalSinceDate:(NSDate *)other;
- (NSTimeInterval)timeIntervalSinceNow;
- (NSTimeInterval)timeIntervalSinceReferenceDate;
- (NSTimeInterval)timeIntervalSince1970;
- (instancetype)dateByAddingTimeInterval:(NSTimeInterval)seconds;
- (instancetype)addingTimeInterval:(NSTimeInterval)seconds;
- (NSDate *)earlierDate:(NSDate *)anotherDate;
- (NSDate *)laterDate:(NSDate *)anotherDate;
- (NSComparisonResult)compare:(NSDate *)other;
- (BOOL)isEqualToDate:(NSDate *)other;
- (NSUInteger)hash;
- (NSString *)description;
- (NSString *)descriptionWithLocale:(id)locale;
- (id)copyWithZone:(NSZone *)zone;

- (void)encodeWithCoder:(NSCoder *)coder;
- (instancetype)initWithCoder:(NSCoder *)coder;
+ (BOOL)supportsSecureCoding;

@end

#endif /* NSDate_h */
