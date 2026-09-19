/*
 * Copyright (C) 2026, Samuel Zormeister.
 *
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */

#import <Foundation/NSCalendar.h>
#include <CoreFoundation/CFCalendar.h>

#if __has_feature(objc_arc)
#define NSCALENDAR_TRANSFER(value) ((__bridge_transfer id)(value))
#define NSCALENDAR_BORROWED(value) ((__bridge id)(value))
#define NSCALENDAR_CF(type, value) ((__bridge type)(value))
#else
#define NSCALENDAR_TRANSFER(value) ((id)CFAutorelease(value))
#define NSCALENDAR_BORROWED(value) ((id)(value))
#define NSCALENDAR_CF(type, value) ((type)(value))
#endif

NSCalendarIdentifier const NSCalendarIdentifierGregorian = @"gregorian";
NSCalendarIdentifier const NSCalendarIdentifierISO8601 = @"iso8601";
NSCalendarIdentifier const NSCalendarIdentifierBuddhist = @"buddhist";
NSCalendarIdentifier const NSCalendarIdentifierJapanese = @"japanese";

static CFCalendarUnit NSCalendarCFUnit(NSCalendarUnit unit) {
    return (CFCalendarUnit)unit;
}

@implementation NSCalendar

+ (instancetype)calendarWithIdentifier:(NSCalendarIdentifier)identifier {
    return NSCALENDAR_TRANSFER(CFCalendarCreateWithIdentifier(
        kCFAllocatorDefault, NSCALENDAR_CF(CFStringRef, identifier)));
}

- (instancetype)initWithCalendarIdentifier:(NSCalendarIdentifier)identifier {
    return NSCALENDAR_TRANSFER(CFCalendarCreateWithIdentifier(
        kCFAllocatorDefault, NSCALENDAR_CF(CFStringRef, identifier)));
}

- (NSCalendarIdentifier)calendarIdentifier {
    return NSCALENDAR_BORROWED(CFCalendarGetIdentifier(NSCALENDAR_CF(CFCalendarRef, self)));
}

- (NSDateComponents *)components:(NSCalendarUnit)unitFlags fromDate:(NSDate *)date {
    NSDateComponents *components = [[NSDateComponents alloc] init];
    int era = 0, year = 0, month = 0, day = 0, hour = 0, minute = 0, second = 0;
    CFAbsoluteTime absoluteTime = [date timeIntervalSinceReferenceDate];
    CFCalendarDecomposeAbsoluteTime(NSCALENDAR_CF(CFCalendarRef, self), absoluteTime,
                                     "yMdHms", &year, &month, &day, &hour,
                                     &minute, &second);
    if (unitFlags & NSCalendarUnitEra) components.era = era;
    if (unitFlags & NSCalendarUnitYear) components.year = year;
    if (unitFlags & NSCalendarUnitMonth) components.month = month;
    if (unitFlags & NSCalendarUnitDay) components.day = day;
    if (unitFlags & NSCalendarUnitHour) components.hour = hour;
    if (unitFlags & NSCalendarUnitMinute) components.minute = minute;
    if (unitFlags & NSCalendarUnitSecond) components.second = second;
    return components;
}

- (NSDate *)dateFromComponents:(NSDateComponents *)components {
    int year = (int)components.year;
    int month = (int)(components.month == NSDateComponentUndefined ? 1 : components.month);
    int day = (int)(components.day == NSDateComponentUndefined ? 1 : components.day);
    int hour = (int)(components.hour == NSDateComponentUndefined ? 0 : components.hour);
    int minute = (int)(components.minute == NSDateComponentUndefined ? 0 : components.minute);
    int second = (int)(components.second == NSDateComponentUndefined ? 0 : components.second);
    CFAbsoluteTime absoluteTime = 0;
    if (!CFCalendarComposeAbsoluteTime(NSCALENDAR_CF(CFCalendarRef, self), &absoluteTime,
                                        "yMdHms", &year, &month, &day,
                                        &hour, &minute, &second)) return nil;
    return [NSDate dateWithTimeIntervalSinceReferenceDate:absoluteTime];
}

- (NSDate *)dateByAddingUnit:(NSCalendarUnit)unit value:(NSInteger)value toDate:(NSDate *)date options:(NSUInteger)options {
    CFAbsoluteTime absoluteTime = [date timeIntervalSinceReferenceDate];
    int amount = (int)value;
    char component = 'd';
    switch (unit) {
        case NSCalendarUnitYear: component = 'y'; break;
        case NSCalendarUnitMonth: component = 'M'; break;
        case NSCalendarUnitWeekOfYear: component = 'w'; break;
        case NSCalendarUnitDay: component = 'd'; break;
        case NSCalendarUnitHour: component = 'H'; break;
        case NSCalendarUnitMinute: component = 'm'; break;
        case NSCalendarUnitSecond: component = 's'; break;
        default: return nil;
    }
    char descriptor[2] = { component, 0 };
    if (!CFCalendarAddComponents(NSCALENDAR_CF(CFCalendarRef, self), &absoluteTime,
                                 (CFOptionFlags)options, descriptor, &amount)) return nil;
    return [NSDate dateWithTimeIntervalSinceReferenceDate:absoluteTime];
}

- (id)copyWithZone:(NSZone *)zone {
    (void)zone;
    return NSCALENDAR_TRANSFER(CFCalendarCreateWithIdentifier(
        kCFAllocatorDefault, CFCalendarGetIdentifier(NSCALENDAR_CF(CFCalendarRef, self))));
}

@end

#if DEPLOYMENT_RUNTIME_OBJC
__attribute__((constructor))
static void __NSCFCalendarBridgeInit(void) {
    _CFRuntimeBridgeClasses(CFCalendarGetTypeID(), "NSCalendar");
}
#endif
