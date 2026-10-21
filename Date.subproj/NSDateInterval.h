/*
 * Copyright (C) 2026, Samuel Zormeister.
 *
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */

#ifndef NSDateInterval_h
#define NSDateInterval_h

#import <Foundation/NSObject.h>
#import <Foundation/NSDate.h>
#import <Foundation/NSCoder.h>

/* A closed interval [startDate, endDate]. The endpoints may be the same, in
 * which case the duration is zero. Reverse intervals - ones whose duration is
 * negative - are not representable. */
@interface NSDateInterval : NSObject <NSCopying, NSSecureCoding>

@property (readonly, copy) NSDate *startDate;
@property (readonly, copy) NSDate *endDate;
@property (readonly) NSTimeInterval duration;

/* Sets both endpoints to the current date and the duration to zero. */
- (instancetype)init;

- (instancetype)initWithCoder:(NSCoder *)coder NS_DESIGNATED_INITIALIZER;

/* Throws an NSInvalidArgumentException when the duration is negative. */
- (instancetype)initWithStartDate:(NSDate *)startDate duration:(NSTimeInterval)duration NS_DESIGNATED_INITIALIZER;

/* Throws an NSGenericException when the end date comes before the start date. */
- (instancetype)initWithStartDate:(NSDate *)startDate endDate:(NSDate *)endDate;

/* Orders by start date first; equal start dates fall back to the duration. */
- (NSComparisonResult)compare:(NSDateInterval *)dateInterval;

- (BOOL)isEqualToDateInterval:(NSDateInterval *)dateInterval;
- (BOOL)intersectsDateInterval:(NSDateInterval *)dateInterval;

/* The overlap between the two intervals, or nil when they do not intersect. */
- (nullable NSDateInterval *)intersectionWithDateInterval:(NSDateInterval *)dateInterval;

- (BOOL)containsDate:(NSDate *)date;

@end

#endif /* NSDateInterval_h */
