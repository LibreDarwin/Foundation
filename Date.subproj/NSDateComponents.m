/*
 * Copyright (C) 2026, Samuel Zormeister.
 *
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */

#import <Foundation/NSDateComponents.h>
#import <Foundation/NSCoder.h>
#import <Foundation/NSException.h>
#import "NSCalendarSupport.h"

@implementation NSDateComponents {
    NSInteger _week;
}

- (instancetype)init {
    self = [super init];
    if (self != nil) {
        _era = NSDateComponentUndefined;
        _year = NSDateComponentUndefined;
        _month = NSDateComponentUndefined;
        _day = NSDateComponentUndefined;
        _hour = NSDateComponentUndefined;
        _minute = NSDateComponentUndefined;
        _second = NSDateComponentUndefined;
        _nanosecond = NSDateComponentUndefined;
        _weekday = NSDateComponentUndefined;
        _weekdayOrdinal = NSDateComponentUndefined;
        _quarter = NSDateComponentUndefined;
        _weekOfMonth = NSDateComponentUndefined;
        _weekOfYear = NSDateComponentUndefined;
        _yearForWeekOfYear = NSDateComponentUndefined;
        _dayOfYear = NSDateComponentUndefined;
        _week = NSDateComponentUndefined;
    }
    return self;
}

- (id)copyWithZone:(NSZone *)zone {
    (void)zone;
    NSDateComponents *copy = [[NSDateComponents alloc] init];
    copy.calendar = _calendar;
    copy.era = _era;
    copy.year = _year;
    copy.month = _month;
    copy.day = _day;
    copy.hour = _hour;
    copy.minute = _minute;
    copy.second = _second;
    copy.nanosecond = _nanosecond;
    copy.weekday = _weekday;
    copy.weekdayOrdinal = _weekdayOrdinal;
    copy.quarter = _quarter;
    copy.weekOfMonth = _weekOfMonth;
    copy.weekOfYear = _weekOfYear;
    copy.yearForWeekOfYear = _yearForWeekOfYear;
    copy.dayOfYear = _dayOfYear;
    copy.leapMonth = _leapMonth;
    copy.repeatedDay = _repeatedDay;
    copy.week = _week;
    return copy;
}

- (NSDate *)date {
    return NSCalendarDateFromComponents(self.calendar, self);
}

- (NSInteger)week {
    return _week;
}

- (void)setWeek:(NSInteger)v {
    _week = v;
}

- (void)setValue:(NSInteger)value forComponent:(NSCalendarUnit)unit {
    /* The calendar, time zone, and leap-month fields are not reachable here;
     * they are left alone, matching the system. */
    switch (unit) {
        case NSCalendarUnitEra: self.era = value; break;
        case NSCalendarUnitYear: self.year = value; break;
        case NSCalendarUnitQuarter: self.quarter = value; break;
        case NSCalendarUnitMonth: self.month = value; break;
        case NSCalendarUnitWeekOfMonth: self.weekOfMonth = value; break;
        case NSCalendarUnitWeekOfYear: self.weekOfYear = value; break;
        case NSCalendarUnitYearForWeekOfYear: self.yearForWeekOfYear = value; break;
        case NSCalendarUnitDay: self.day = value; break;
        case NSCalendarUnitDayOfYear: self.dayOfYear = value; break;
        case NSCalendarUnitWeekday: self.weekday = value; break;
        case NSCalendarUnitWeekdayOrdinal: self.weekdayOrdinal = value; break;
        case NSCalendarUnitHour: self.hour = value; break;
        case NSCalendarUnitMinute: self.minute = value; break;
        case NSCalendarUnitSecond: self.second = value; break;
        case NSCalendarUnitNanosecond: self.nanosecond = value; break;
        default: break;
    }
}

- (NSInteger)valueForComponent:(NSCalendarUnit)unit {
    switch (unit) {
        case NSCalendarUnitEra: return self.era;
        case NSCalendarUnitYear: return self.year;
        case NSCalendarUnitQuarter: return self.quarter;
        case NSCalendarUnitMonth: return self.month;
        case NSCalendarUnitWeekOfMonth: return self.weekOfMonth;
        case NSCalendarUnitWeekOfYear: return self.weekOfYear;
        case NSCalendarUnitYearForWeekOfYear: return self.yearForWeekOfYear;
        case NSCalendarUnitDay: return self.day;
        case NSCalendarUnitDayOfYear: return self.dayOfYear;
        case NSCalendarUnitWeekday: return self.weekday;
        case NSCalendarUnitWeekdayOrdinal: return self.weekdayOrdinal;
        case NSCalendarUnitHour: return self.hour;
        case NSCalendarUnitMinute: return self.minute;
        case NSCalendarUnitSecond: return self.second;
        case NSCalendarUnitNanosecond: return self.nanosecond;
        default: return NSDateComponentUndefined;
    }
}

- (BOOL)isValidDate {
    return NSCalendarDateComponentsAreValid(self.calendar, self);
}

- (BOOL)isValidDateInCalendar:(NSCalendar *)calendar {
    if (calendar == nil) {
        @throw [NSException exceptionWithName:NSInvalidArgumentException
                                       reason:@"calendar cannot be nil"
                                     userInfo:nil];
    }
    return NSCalendarDateComponentsAreValid(calendar, self);
}

#pragma mark - NSCoding

+ (BOOL)supportsSecureCoding {
    return YES;
}

- (void)encodeWithCoder:(NSCoder *)coder {
    if (![coder allowsKeyedCoding]) return;
    [coder encodeObject:_calendar forKey:@"NSCalendar"];
    [coder encodeInteger:_era forKey:@"NSEra"];
    [coder encodeInteger:_year forKey:@"NSYear"];
    [coder encodeInteger:_month forKey:@"NSMonth"];
    [coder encodeInteger:_day forKey:@"NSDay"];
    [coder encodeInteger:_hour forKey:@"NSHour"];
    [coder encodeInteger:_minute forKey:@"NSMinute"];
    [coder encodeInteger:_second forKey:@"NSSecond"];
    [coder encodeInteger:_nanosecond forKey:@"NSNanosecond"];
    [coder encodeInteger:_weekday forKey:@"NSWeekday"];
    [coder encodeInteger:_weekdayOrdinal forKey:@"NSWeekdayOrdinal"];
    [coder encodeInteger:_quarter forKey:@"NSQuarter"];
    [coder encodeInteger:_weekOfMonth forKey:@"NSWeekOfMonth"];
    [coder encodeInteger:_weekOfYear forKey:@"NSWeekOfYear"];
    [coder encodeInteger:_yearForWeekOfYear forKey:@"NSYearForWeekOfYear"];
    [coder encodeInteger:_dayOfYear forKey:@"NSDayOfYear"];
    [coder encodeInteger:_week forKey:@"NSWeek"];
    [coder encodeInteger:(NSInteger)_leapMonth forKey:@"NSLeapMonth"];
    [coder encodeInteger:(NSInteger)_repeatedDay forKey:@"NSRepeatedDay"];
}

- (instancetype)initWithCoder:(NSCoder *)coder {
    self = [self init];
    if (self == nil) return nil;
    if (![coder allowsKeyedCoding]) return self;
    if ([coder containsValueForKey:@"NSCalendar"]) self.calendar = [coder decodeObjectForKey:@"NSCalendar"];
    if ([coder containsValueForKey:@"NSEra"]) self.era = [coder decodeIntegerForKey:@"NSEra"];
    if ([coder containsValueForKey:@"NSYear"]) self.year = [coder decodeIntegerForKey:@"NSYear"];
    if ([coder containsValueForKey:@"NSMonth"]) self.month = [coder decodeIntegerForKey:@"NSMonth"];
    if ([coder containsValueForKey:@"NSDay"]) self.day = [coder decodeIntegerForKey:@"NSDay"];
    if ([coder containsValueForKey:@"NSHour"]) self.hour = [coder decodeIntegerForKey:@"NSHour"];
    if ([coder containsValueForKey:@"NSMinute"]) self.minute = [coder decodeIntegerForKey:@"NSMinute"];
    if ([coder containsValueForKey:@"NSSecond"]) self.second = [coder decodeIntegerForKey:@"NSSecond"];
    if ([coder containsValueForKey:@"NSNanosecond"]) self.nanosecond = [coder decodeIntegerForKey:@"NSNanosecond"];
    if ([coder containsValueForKey:@"NSWeekday"]) self.weekday = [coder decodeIntegerForKey:@"NSWeekday"];
    if ([coder containsValueForKey:@"NSWeekdayOrdinal"]) self.weekdayOrdinal = [coder decodeIntegerForKey:@"NSWeekdayOrdinal"];
    if ([coder containsValueForKey:@"NSQuarter"]) self.quarter = [coder decodeIntegerForKey:@"NSQuarter"];
    if ([coder containsValueForKey:@"NSWeekOfMonth"]) self.weekOfMonth = [coder decodeIntegerForKey:@"NSWeekOfMonth"];
    if ([coder containsValueForKey:@"NSWeekOfYear"]) self.weekOfYear = [coder decodeIntegerForKey:@"NSWeekOfYear"];
    if ([coder containsValueForKey:@"NSYearForWeekOfYear"]) self.yearForWeekOfYear = [coder decodeIntegerForKey:@"NSYearForWeekOfYear"];
    if ([coder containsValueForKey:@"NSDayOfYear"]) self.dayOfYear = [coder decodeIntegerForKey:@"NSDayOfYear"];
    if ([coder containsValueForKey:@"NSWeek"]) self.week = [coder decodeIntegerForKey:@"NSWeek"];
    if ([coder containsValueForKey:@"NSLeapMonth"]) self.leapMonth = (BOOL)[coder decodeIntegerForKey:@"NSLeapMonth"];
    if ([coder containsValueForKey:@"NSRepeatedDay"]) self.repeatedDay = (BOOL)[coder decodeIntegerForKey:@"NSRepeatedDay"];
    return self;
}

@end
