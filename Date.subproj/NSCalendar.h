/*
 * Copyright (C) 2026, Samuel Zormeister.
 *
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */

#ifndef NSCalendar_h
#define NSCalendar_h

#import <Foundation/NSObject.h>
#import <Foundation/NSDate.h>
#import <Foundation/NSDateComponents.h>

@class NSString;

typedef NSString *NSCalendarIdentifier;

FOUNDATION_EXPORT NSCalendarIdentifier const NSCalendarIdentifierGregorian;
FOUNDATION_EXPORT NSCalendarIdentifier const NSCalendarIdentifierISO8601;
FOUNDATION_EXPORT NSCalendarIdentifier const NSCalendarIdentifierBuddhist;
FOUNDATION_EXPORT NSCalendarIdentifier const NSCalendarIdentifierJapanese;

typedef NS_OPTIONS(NSUInteger, NSCalendarUnit) {
    NSCalendarUnitEra = (1UL << 1),
    NSCalendarUnitYear = (1UL << 2),
    NSCalendarUnitMonth = (1UL << 3),
    NSCalendarUnitDay = (1UL << 4),
    NSCalendarUnitHour = (1UL << 5),
    NSCalendarUnitMinute = (1UL << 6),
    NSCalendarUnitSecond = (1UL << 7),
    NSCalendarUnitWeekday = (1UL << 9),
    NSCalendarUnitWeekdayOrdinal = (1UL << 10),
    NSCalendarUnitQuarter = (1UL << 11),
    NSCalendarUnitWeekOfMonth = (1UL << 12),
    NSCalendarUnitWeekOfYear = (1UL << 13),
    NSCalendarUnitYearForWeekOfYear = (1UL << 14)
};

@interface NSCalendar : NSObject <NSCopying>
+ (instancetype)calendarWithIdentifier:(NSCalendarIdentifier)identifier;
- (instancetype)initWithCalendarIdentifier:(NSCalendarIdentifier)identifier;
- (NSCalendarIdentifier)calendarIdentifier;
- (NSDateComponents *)components:(NSCalendarUnit)unitFlags fromDate:(NSDate *)date;
- (NSDate *)dateFromComponents:(NSDateComponents *)components;
- (NSDate *)dateByAddingUnit:(NSCalendarUnit)unit value:(NSInteger)value toDate:(NSDate *)date options:(NSUInteger)options;
- (id)copyWithZone:(NSZone *)zone;
@end

#endif /* NSCalendar_h */
