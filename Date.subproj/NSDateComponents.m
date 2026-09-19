/*
 * Copyright (C) 2026, Samuel Zormeister.
 *
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */

#import <Foundation/NSDateComponents.h>

const NSInteger NSDateComponentUndefined = NSIntegerMax;

@implementation NSDateComponents

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
        _weekday = NSDateComponentUndefined;
        _weekdayOrdinal = NSDateComponentUndefined;
        _quarter = NSDateComponentUndefined;
        _weekOfMonth = NSDateComponentUndefined;
        _weekOfYear = NSDateComponentUndefined;
        _yearForWeekOfYear = NSDateComponentUndefined;
    }
    return self;
}

- (id)copyWithZone:(NSZone *)zone {
    (void)zone;
    NSDateComponents *copy = [[NSDateComponents alloc] init];
    copy.era = _era;
    copy.year = _year;
    copy.month = _month;
    copy.day = _day;
    copy.hour = _hour;
    copy.minute = _minute;
    copy.second = _second;
    copy.weekday = _weekday;
    copy.weekdayOrdinal = _weekdayOrdinal;
    copy.quarter = _quarter;
    copy.weekOfMonth = _weekOfMonth;
    copy.weekOfYear = _weekOfYear;
    copy.yearForWeekOfYear = _yearForWeekOfYear;
    return copy;
}

@end
