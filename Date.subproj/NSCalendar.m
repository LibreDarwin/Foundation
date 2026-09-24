/*
 * Copyright (C) 2026, Samuel Zormeister.
 *
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */

#import <Foundation/NSCalendar.h>
#import <Foundation/NSCoder.h>
#import "NSCalendarSupport.h"
#include <CoreFoundation/CFCalendar.h>
#include <CoreFoundation/CFDateFormatter.h>
#include <CoreFoundation/CFLocale.h>
#include <math.h>

#if __has_feature(objc_arc)
#define NSCALENDAR_TRANSFER(value) ((__bridge_transfer id)(value))
#define NSCALENDAR_BORROWED(value) ((__bridge id)(value))
#define NSCALENDAR_CF(type, value) ((__bridge type)(value))
#else
#define NSCALENDAR_TRANSFER(value) ((id)CFAutorelease(value))
#define NSCALENDAR_BORROWED(value) ((id)(value))
#define NSCALENDAR_CF(type, value) ((type)(value))
#endif

@interface NSCalendar () {
    CFCalendarRef _calendar;
}
- (CFCalendarRef)_backingCalendar;
- (instancetype)_initWithBackingCalendar:(CFCalendarRef)backing;
@end

/* NSCalendar is an owning wrapper, not toll-free with CFCalendar: it was
 * created through the CoreFoundation constructor and answers through the
 * CFCalendar it holds.  Every entry point unwraps that backing calendar
 * instead of casting self. */
static CFCalendarRef NSCalendarBacking(NSCalendar *calendar) {
    if (calendar == nil || ![calendar isKindOfClass:[NSCalendar class]]) return NULL;
    return [calendar _backingCalendar];
}

NSCalendarIdentifier const NSCalendarIdentifierGregorian = @"gregorian";
NSCalendarIdentifier const NSCalendarIdentifierBuddhist = @"buddhist";
NSCalendarIdentifier const NSCalendarIdentifierChinese = @"chinese";
NSCalendarIdentifier const NSCalendarIdentifierCoptic = @"coptic";
NSCalendarIdentifier const NSCalendarIdentifierEthiopicAmeteMihret = @"ethiopic";
NSCalendarIdentifier const NSCalendarIdentifierEthiopicAmeteAlem = @"ethiopic-amete-alem";
NSCalendarIdentifier const NSCalendarIdentifierHebrew = @"hebrew";
NSCalendarIdentifier const NSCalendarIdentifierISO8601 = @"iso8601";
NSCalendarIdentifier const NSCalendarIdentifierIndian = @"indian";
NSCalendarIdentifier const NSCalendarIdentifierIslamic = @"islamic";
NSCalendarIdentifier const NSCalendarIdentifierIslamicCivil = @"islamic-civil";
NSCalendarIdentifier const NSCalendarIdentifierJapanese = @"japanese";
NSCalendarIdentifier const NSCalendarIdentifierPersian = @"persian";
NSCalendarIdentifier const NSCalendarIdentifierRepublicOfChina = @"roc";
NSCalendarIdentifier const NSCalendarIdentifierIslamicTabular = @"islamic-tbla";
NSCalendarIdentifier const NSCalendarIdentifierIslamicUmmAlQura = @"islamic-umalqura";
NSCalendarIdentifier const NSCalendarIdentifierBangla = @"bangla";
NSCalendarIdentifier const NSCalendarIdentifierGujarati = @"gujarati";
NSCalendarIdentifier const NSCalendarIdentifierKannada = @"kannada";
NSCalendarIdentifier const NSCalendarIdentifierMalayalam = @"malayalam";
NSCalendarIdentifier const NSCalendarIdentifierMarathi = @"marathi";
NSCalendarIdentifier const NSCalendarIdentifierOdia = @"odia";
NSCalendarIdentifier const NSCalendarIdentifierTamil = @"tamil";
NSCalendarIdentifier const NSCalendarIdentifierTelugu = @"telugu";
NSCalendarIdentifier const NSCalendarIdentifierVikram = @"vikram";
NSCalendarIdentifier const NSCalendarIdentifierDangi = @"dangi";
NSCalendarIdentifier const NSCalendarIdentifierVietnamese = @"vietnamese";

NSNotificationName const NSCalendarDayChangedNotification = @"NSCalendarDayChangedNotification";

/* Decompose and compose take their arguments differently, and the difference
 * matters: CFCalendarDecomposeAbsoluteTime and
 * CFCalendarGetComponentDifference fill in out-parameters passed by address,
 * while CFCalendarComposeAbsoluteTime and CFCalendarAddComponents read their
 * inputs by value. The component descriptor characters are, in order: era G,
 * year y, quarter Q, month M, week of month W, week of year w, year for week of
 * year Y, day d, day of year D, weekday E, weekday ordinal F, hour H, minute m,
 * second s. */
static const char NSCalendarAllComponentsDescriptor[] = "GyQMWwYdEFHms";

static int NSCalendarComponentOrDefault(NSInteger value, NSInteger fallback) {
    return (int)(value == NSDateComponentUndefined ? fallback : value);
}

/* Same mapping as NSDateComponents, but the receiver is a bare CFCalendar;
 * used by the decomposition-based comparison paths that do not build an
 * NSDateComponents. */
typedef struct {
    int era, year, quarter, month, weekOfMonth, weekOfYear, yearForWeekOfYear;
    int day, dayOfYear, weekday, weekdayOrdinal, hour, minute, second;
} NSCalendarDecomposed;

static Boolean NSCalendarDecompose(CFCalendarRef calendar,
                                   CFAbsoluteTime absoluteTime,
                                   NSCalendarDecomposed *components) {
    return CFCalendarDecomposeAbsoluteTime(calendar, absoluteTime, "GyQMWwYdDEFHms",
                                           &components->era, &components->year,
                                           &components->quarter, &components->month,
                                           &components->weekOfMonth, &components->weekOfYear,
                                           &components->yearForWeekOfYear, &components->day,
                                           &components->dayOfYear, &components->weekday,
                                           &components->weekdayOrdinal, &components->hour,
                                           &components->minute, &components->second);
}

/* Apple defines the sub-second component as the fractional part of the
 * absolute time, truncated to whole nanoseconds; this works for negative times
 * too because the fraction is taken from floor(), not from a signed truncation. */
static NSInteger NSCalendarNanosecond(CFAbsoluteTime absoluteTime) {
    return (NSInteger)((absoluteTime - floor(absoluteTime)) * 1000000000.0);
}

static NSComparisonResult NSCalendarCompareValues(NSInteger left, NSInteger right) {
    if (left < right) return NSOrderedAscending;
    if (left > right) return NSOrderedDescending;
    return NSOrderedSame;
}

/* Compares two decomposed dates down to `unit` and all larger units. The
 * hierarchy follows the calendar's own nesting: month-based units walk
 * era/year/month/..., while the week units walk era/yearForWeekOfYear/.... */
static NSComparisonResult NSCalendarCompareDecomposed(const NSCalendarDecomposed *left,
                                                      const NSCalendarDecomposed *right,
                                                      NSCalendarUnit unit,
                                                      CFAbsoluteTime leftTime,
                                                      CFAbsoluteTime rightTime) {
#define NSCALENDAR_CMP(field)                                              \
    do {                                                                   \
        NSComparisonResult result = NSCalendarCompareValues(left->field,   \
                                                            right->field); \
        if (result != NSOrderedSame) return result;                        \
    } while (0)
    switch (unit) {
        case NSCalendarUnitEra:
            NSCALENDAR_CMP(era);
            break;
        case NSCalendarUnitYear:
            NSCALENDAR_CMP(era);
            NSCALENDAR_CMP(year);
            break;
        case NSCalendarUnitQuarter:
            /* Apple's quarter-granularity comparison ignores the quarter field
             * entirely and behaves exactly like a day-granularity comparison
             * (verified: Jan 15 vs Feb 15 2009, same quarter and same
             * day-of-month, compares unequal). Match that observed behavior. */
            NSCALENDAR_CMP(era);
            NSCALENDAR_CMP(year);
            NSCALENDAR_CMP(month);
            NSCALENDAR_CMP(day);
            break;
        case NSCalendarUnitMonth:
            NSCALENDAR_CMP(era);
            NSCALENDAR_CMP(year);
            NSCALENDAR_CMP(month);
            break;
        case NSCalendarUnitWeekOfMonth:
            NSCALENDAR_CMP(era);
            NSCALENDAR_CMP(year);
            NSCALENDAR_CMP(month);
            NSCALENDAR_CMP(weekOfMonth);
            break;
        case NSCalendarUnitWeekOfYear:
            NSCALENDAR_CMP(era);
            NSCALENDAR_CMP(yearForWeekOfYear);
            NSCALENDAR_CMP(weekOfYear);
            break;
        case NSCalendarUnitYearForWeekOfYear:
            NSCALENDAR_CMP(era);
            NSCALENDAR_CMP(yearForWeekOfYear);
            break;
        case NSCalendarUnitDay:
            NSCALENDAR_CMP(era);
            NSCALENDAR_CMP(year);
            NSCALENDAR_CMP(month);
            NSCALENDAR_CMP(day);
            break;
        case NSCalendarUnitWeekday:
            NSCALENDAR_CMP(era);
            NSCALENDAR_CMP(yearForWeekOfYear);
            NSCALENDAR_CMP(weekOfYear);
            NSCALENDAR_CMP(weekday);
            break;
        case NSCalendarUnitWeekdayOrdinal:
            NSCALENDAR_CMP(era);
            NSCALENDAR_CMP(year);
            NSCALENDAR_CMP(month);
            NSCALENDAR_CMP(weekdayOrdinal);
            break;
        case NSCalendarUnitHour:
            NSCALENDAR_CMP(era);
            NSCALENDAR_CMP(year);
            NSCALENDAR_CMP(month);
            NSCALENDAR_CMP(day);
            NSCALENDAR_CMP(hour);
            break;
        case NSCalendarUnitMinute:
            NSCALENDAR_CMP(era);
            NSCALENDAR_CMP(year);
            NSCALENDAR_CMP(month);
            NSCALENDAR_CMP(day);
            NSCALENDAR_CMP(hour);
            NSCALENDAR_CMP(minute);
            break;
        case NSCalendarUnitSecond:
            NSCALENDAR_CMP(era);
            NSCALENDAR_CMP(year);
            NSCALENDAR_CMP(month);
            NSCALENDAR_CMP(day);
            NSCALENDAR_CMP(hour);
            NSCALENDAR_CMP(minute);
            NSCALENDAR_CMP(second);
            break;
        case NSCalendarUnitNanosecond:
        default:
            NSCALENDAR_CMP(era);
            NSCALENDAR_CMP(year);
            NSCALENDAR_CMP(month);
            NSCALENDAR_CMP(day);
            NSCALENDAR_CMP(hour);
            NSCALENDAR_CMP(minute);
            NSCALENDAR_CMP(second);
            {
                NSComparisonResult result = NSCalendarCompareValues(
                    NSCalendarNanosecond(leftTime), NSCalendarNanosecond(rightTime));
                if (result != NSOrderedSame) return result;
            }
            break;
    }
#undef NSCALENDAR_CMP
    return NSOrderedSame;
}

static NSRange NSCalendarRangeFromCFRange(CFRange range) {
    if (range.location == kCFNotFound || range.length == kCFNotFound) {
        return NSMakeRange(NSNotFound, NSNotFound);
    }
    return NSMakeRange((NSUInteger)range.location, (NSUInteger)range.length);
}

static Boolean NSCalendarUnitIsCoreFoundation(NSCalendarUnit unit) {
    switch (unit) {
        case NSCalendarUnitEra:
        case NSCalendarUnitYear:
        case NSCalendarUnitMonth:
        case NSCalendarUnitDay:
        case NSCalendarUnitHour:
        case NSCalendarUnitMinute:
        case NSCalendarUnitSecond:
        case NSCalendarUnitWeekday:
        case NSCalendarUnitWeekdayOrdinal:
        case NSCalendarUnitQuarter:
        case NSCalendarUnitWeekOfMonth:
        case NSCalendarUnitWeekOfYear:
        case NSCalendarUnitYearForWeekOfYear:
        case NSCalendarUnitDayOfYear:
            return true;
        default:
            return false;
    }
}

/* A total ordering over the calendar units, coarser first. Used to find the
 * highest specified unit of a match request and to decide which smaller units
 * drop to their base value during probe composition. */
static int NSCalendarUnitRank(NSCalendarUnit unit) {
    switch (unit) {
        case NSCalendarUnitEra: return 0;
        case NSCalendarUnitYear: return 1;
        case NSCalendarUnitQuarter: return 2;
        case NSCalendarUnitMonth: return 3;
        case NSCalendarUnitYearForWeekOfYear: return 4;
        case NSCalendarUnitWeekOfYear:
        case NSCalendarUnitWeekOfMonth: return 5;
        case NSCalendarUnitDay: return 6;
        case NSCalendarUnitWeekday: return 7;
        case NSCalendarUnitHour: return 8;
        case NSCalendarUnitMinute: return 9;
        case NSCalendarUnitSecond: return 10;
        case NSCalendarUnitNanosecond: return 11;
        default: return 12;
    }
}

/* The unit the forward search advances between probe periods: one level above
 * the highest specified unit. Matching a month searches years, a day searches
 * months, an hour searches days. Years step on years (era stepping is a
 * no-op in most calendars); the year-only edges are handled by the no-progress
 * guard rather than by stepping eras. */
static NSCalendarUnit NSCalendarUnitStepForRank(int rank) {
    switch (rank) {
        case 0: return NSCalendarUnitYear;           /* era -> year */
        case 1: return NSCalendarUnitYear;           /* year -> year */
        case 2: return NSCalendarUnitYear;           /* quarter -> year */
        case 3: return NSCalendarUnitYear;           /* month -> year */
        case 4: return NSCalendarUnitYear;           /* yearForWeekOfYear -> year */
        case 5: return NSCalendarUnitYear;           /* week of year -> year */
        case 6: return NSCalendarUnitMonth;          /* day -> month */
        case 7: return NSCalendarUnitDay;            /* weekday -> day */
        case 8: return NSCalendarUnitDay;            /* hour -> day */
        case 9: return NSCalendarUnitHour;           /* minute -> hour */
        case 10: return NSCalendarUnitSecond;        /* second -> minute */
        default: return NSCalendarUnitSecond;        /* nanosecond -> second */
    }
}

/* Base (default) value for a unit that was not specified by the caller but is
 * finer than the highest specified unit: month/day default to 1, the time
 * units to 0, matching the composition conventions documented in NSCalendar.h
 * ("a Day of 1, and an Hour, Minute, Second, and Nanosecond of 0"). */
static int NSCalendarUnitBaseValue(NSCalendarUnit unit) {
    switch (unit) {
        case NSCalendarUnitQuarter:
        case NSCalendarUnitMonth:
        case NSCalendarUnitDay:
        case NSCalendarUnitWeekOfMonth:
        case NSCalendarUnitWeekOfYear:
        case NSCalendarUnitWeekday: return 1;
        case NSCalendarUnitEra: return 1;
        default: return 0;
    }
}

static NSDate *NSCalendarDateByAddingNanoseconds(NSDate *date, NSInteger nanoseconds) {
    if (date == nil || nanoseconds == NSDateComponentUndefined || nanoseconds == 0) return date;
    return [NSDate dateWithTimeIntervalSinceReferenceDate:
                [date timeIntervalSinceReferenceDate] + (NSTimeInterval)nanoseconds / 1000000000.0];
}

/* Builds a date from components at the C level on a backing CFCalendar. This
 * duplicates the two dateWithEra: constructors, but it does not message an
 * NSCalendar: the callers have already unwrapped the backing calendar, and
 * going back through `self` would only re-enter the object surface. */
static NSDate *NSCalendarMakeDate(CFCalendarRef calendar, NSDateComponents *components) {
    if (components.yearForWeekOfYear != NSDateComponentUndefined ||
        components.weekOfYear != NSDateComponentUndefined ||
        components.weekday != NSDateComponentUndefined) {
        int era = NSCalendarComponentOrDefault(components.era, 1);
        int year = NSCalendarComponentOrDefault(components.yearForWeekOfYear,
                                                NSCalendarComponentOrDefault(components.year, 1));
        int week = NSCalendarComponentOrDefault(components.weekOfYear, 1);
        int weekday = NSCalendarComponentOrDefault(components.weekday, 1);
        int hour = NSCalendarComponentOrDefault(components.hour, 0);
        int minute = NSCalendarComponentOrDefault(components.minute, 0);
        int second = NSCalendarComponentOrDefault(components.second, 0);
        CFAbsoluteTime absoluteTime = 0;
        if (!CFCalendarComposeAbsoluteTime(calendar, &absoluteTime, "GwYEHms",
                                            era, week, year, weekday,
                                            hour, minute, second)) return nil;
        return [NSDate dateWithTimeIntervalSinceReferenceDate:absoluteTime];
    }

    int era = NSCalendarComponentOrDefault(components.era, 1);
    int year = NSCalendarComponentOrDefault(components.year, 1);
    int month = NSCalendarComponentOrDefault(components.month, 1);
    int day = NSCalendarComponentOrDefault(components.day, 1);
    int hour = NSCalendarComponentOrDefault(components.hour, 0);
    int minute = NSCalendarComponentOrDefault(components.minute, 0);
    int second = NSCalendarComponentOrDefault(components.second, 0);
    CFAbsoluteTime absoluteTime = 0;
    if (!CFCalendarComposeAbsoluteTime(calendar, &absoluteTime, "GyMdHms",
                                        era, year, month, day,
                                        hour, minute, second)) return nil;
    return [NSDate dateWithTimeIntervalSinceReferenceDate:absoluteTime];
}

/* The difference for a unit depends on which other units travel with it:
 * asking for days alone yields the total day count, while asking for days and
 * months splits it into whole months plus a remainder. So the descriptor has
 * to carry exactly the requested units, in canonical order. */
static NSDateComponents *NSCalendarComponentsBetween(CFCalendarRef calendar,
                                                     NSCalendarUnit unitFlags,
                                                     CFAbsoluteTime startingTime,
                                                     CFAbsoluteTime resultTime,
                                                     NSCalendarOptions options) {
    NSDateComponents *components = [[NSDateComponents alloc] init];
    int era = 0, year = 0, quarter = 0, month = 0, weekOfMonth = 0, weekOfYear = 0, yearForWeekOfYear = 0;
    int day = 0, weekday = 0, weekdayOrdinal = 0, hour = 0, minute = 0, second = 0;

    char descriptor[16];
    int *results[13];
    int count = 0;
#define NSCALENDAR_DIFFERENCE_UNIT(flag, character, variable)     \
    if (unitFlags & (flag)) {                                     \
        descriptor[count] = (character);                          \
        results[count] = &(variable);                             \
        count++;                                                  \
    }
    NSCALENDAR_DIFFERENCE_UNIT(NSCalendarUnitEra, 'G', era)
    NSCALENDAR_DIFFERENCE_UNIT(NSCalendarUnitYear, 'y', year)
    NSCALENDAR_DIFFERENCE_UNIT(NSCalendarUnitQuarter, 'Q', quarter)
    NSCALENDAR_DIFFERENCE_UNIT(NSCalendarUnitMonth, 'M', month)
    NSCALENDAR_DIFFERENCE_UNIT(NSCalendarUnitWeekOfMonth, 'W', weekOfMonth)
    NSCALENDAR_DIFFERENCE_UNIT(NSCalendarUnitWeekOfYear, 'w', weekOfYear)
    NSCALENDAR_DIFFERENCE_UNIT(NSCalendarUnitYearForWeekOfYear, 'Y', yearForWeekOfYear)
    NSCALENDAR_DIFFERENCE_UNIT(NSCalendarUnitDay, 'd', day)
    NSCALENDAR_DIFFERENCE_UNIT(NSCalendarUnitWeekday, 'E', weekday)
    NSCALENDAR_DIFFERENCE_UNIT(NSCalendarUnitWeekdayOrdinal, 'F', weekdayOrdinal)
    NSCALENDAR_DIFFERENCE_UNIT(NSCalendarUnitHour, 'H', hour)
    NSCALENDAR_DIFFERENCE_UNIT(NSCalendarUnitMinute, 'm', minute)
    NSCALENDAR_DIFFERENCE_UNIT(NSCalendarUnitSecond, 's', second)
#undef NSCALENDAR_DIFFERENCE_UNIT
    descriptor[count] = '\0';

    CFOptionFlags flags = (CFOptionFlags)options;
    Boolean ok = false;
    switch (count) {
        case 0:  ok = CFCalendarGetComponentDifference(calendar, startingTime, resultTime, flags, descriptor); break;
        case 1:  ok = CFCalendarGetComponentDifference(calendar, startingTime, resultTime, flags, descriptor, results[0]); break;
        case 2:  ok = CFCalendarGetComponentDifference(calendar, startingTime, resultTime, flags, descriptor, results[0], results[1]); break;
        case 3:  ok = CFCalendarGetComponentDifference(calendar, startingTime, resultTime, flags, descriptor, results[0], results[1], results[2]); break;
        case 4:  ok = CFCalendarGetComponentDifference(calendar, startingTime, resultTime, flags, descriptor, results[0], results[1], results[2], results[3]); break;
        case 5:  ok = CFCalendarGetComponentDifference(calendar, startingTime, resultTime, flags, descriptor, results[0], results[1], results[2], results[3], results[4]); break;
        case 6:  ok = CFCalendarGetComponentDifference(calendar, startingTime, resultTime, flags, descriptor, results[0], results[1], results[2], results[3], results[4], results[5]); break;
        case 7:  ok = CFCalendarGetComponentDifference(calendar, startingTime, resultTime, flags, descriptor, results[0], results[1], results[2], results[3], results[4], results[5], results[6]); break;
        case 8:  ok = CFCalendarGetComponentDifference(calendar, startingTime, resultTime, flags, descriptor, results[0], results[1], results[2], results[3], results[4], results[5], results[6], results[7]); break;
        case 9:  ok = CFCalendarGetComponentDifference(calendar, startingTime, resultTime, flags, descriptor, results[0], results[1], results[2], results[3], results[4], results[5], results[6], results[7], results[8]); break;
        case 10: ok = CFCalendarGetComponentDifference(calendar, startingTime, resultTime, flags, descriptor, results[0], results[1], results[2], results[3], results[4], results[5], results[6], results[7], results[8], results[9]); break;
        case 11: ok = CFCalendarGetComponentDifference(calendar, startingTime, resultTime, flags, descriptor, results[0], results[1], results[2], results[3], results[4], results[5], results[6], results[7], results[8], results[9], results[10]); break;
        case 12: ok = CFCalendarGetComponentDifference(calendar, startingTime, resultTime, flags, descriptor, results[0], results[1], results[2], results[3], results[4], results[5], results[6], results[7], results[8], results[9], results[10], results[11]); break;
        default: ok = CFCalendarGetComponentDifference(calendar, startingTime, resultTime, flags, descriptor, results[0], results[1], results[2], results[3], results[4], results[5], results[6], results[7], results[8], results[9], results[10], results[11], results[12]); break;
    }
    if (!ok) return components;
    if (unitFlags & NSCalendarUnitEra) components.era = era;
    if (unitFlags & NSCalendarUnitYear) components.year = year;
    if (unitFlags & NSCalendarUnitQuarter) components.quarter = quarter;
    if (unitFlags & NSCalendarUnitMonth) components.month = month;
    if (unitFlags & NSCalendarUnitWeekOfMonth) components.weekOfMonth = weekOfMonth;
    if (unitFlags & NSCalendarUnitWeekOfYear) components.weekOfYear = weekOfYear;
    if (unitFlags & NSCalendarUnitYearForWeekOfYear) components.yearForWeekOfYear = yearForWeekOfYear;
    if (unitFlags & NSCalendarUnitDay) components.day = day;
    if (unitFlags & NSCalendarUnitWeekday) components.weekday = weekday;
    if (unitFlags & NSCalendarUnitWeekdayOrdinal) components.weekdayOrdinal = weekdayOrdinal;
    if (unitFlags & NSCalendarUnitHour) components.hour = hour;
    if (unitFlags & NSCalendarUnitMinute) components.minute = minute;
    if (unitFlags & NSCalendarUnitSecond) components.second = second;
    return components;
}

NSDate *NSCalendarDateFromComponents(NSCalendar *calendar, NSDateComponents *components) {
    if (calendar == nil) return nil;
    return NSCalendarMakeDate(NSCalendarBacking(calendar), components);
}

CFCalendarRef NSCalendarGetBackingCalendar(NSCalendar *calendar) {
    return NSCalendarBacking(calendar);
}

BOOL NSCalendarDateComponentsAreValid(NSCalendar *calendar, NSDateComponents *components) {
    if (calendar == nil || components == nil) return NO;
    CFCalendarRef cfCalendar = NSCalendarBacking(calendar);
    NSDate *date = NSCalendarMakeDate(cfCalendar, components);
    if (date == nil) return NO;

    /* Compose the fields into a date, then decompose it back. Any field whose
     * value changed did not name an existing date: composing Feb 30 yields
     * Mar 2, so the day no longer matches. Only the fields actually set by the
     * caller are examined. */
    NSCalendarDecomposed recomposed;
    if (!NSCalendarDecompose(cfCalendar, [date timeIntervalSinceReferenceDate], &recomposed)) return NO;
#define NSCALENDAR_VALIDATE(property, field)                        \
    if (components.property != NSDateComponentUndefined &&          \
        components.property != recomposed.field) return NO;
    NSCALENDAR_VALIDATE(era, era)
    NSCALENDAR_VALIDATE(year, year)
    NSCALENDAR_VALIDATE(quarter, quarter)
    NSCALENDAR_VALIDATE(month, month)
    NSCALENDAR_VALIDATE(weekOfMonth, weekOfMonth)
    NSCALENDAR_VALIDATE(weekOfYear, weekOfYear)
    NSCALENDAR_VALIDATE(yearForWeekOfYear, yearForWeekOfYear)
    NSCALENDAR_VALIDATE(day, day)
    NSCALENDAR_VALIDATE(dayOfYear, dayOfYear)
    NSCALENDAR_VALIDATE(weekday, weekday)
    NSCALENDAR_VALIDATE(weekdayOrdinal, weekdayOrdinal)
    NSCALENDAR_VALIDATE(hour, hour)
    NSCALENDAR_VALIDATE(minute, minute)
    NSCALENDAR_VALIDATE(second, second)
#undef NSCALENDAR_VALIDATE
    return YES;
}

/* The localized name arrays are exposed by CFDateFormatter, not CFCalendar, so
 * each getter builds a throwaway formatter around the calendar's locale and
 * copies the requested property. */
static id NSCalendarCopySymbols(CFCalendarRef calendar, CFStringRef key) {
    CFLocaleRef locale = CFCalendarCopyLocale(calendar);
    CFLocaleRef borrowed = NULL;
    if (locale == NULL) {
        borrowed = CFLocaleGetSystem();
        locale = borrowed;
    }
    CFDateFormatterRef formatter = CFDateFormatterCreate(kCFAllocatorDefault, locale,
                                                          kCFDateFormatterNoStyle,
                                                          kCFDateFormatterNoStyle);
    if (locale != borrowed && locale != NULL) CFRelease(locale);
    if (formatter == NULL) return nil;
    CFTypeRef value = CFDateFormatterCopyProperty(formatter, key);
    CFRelease(formatter);
    if (value == NULL) return nil;
    return NSCALENDAR_TRANSFER(value);
}

@implementation NSCalendar

- (CFCalendarRef)_backingCalendar {
    return _calendar;
}

- (instancetype)_initWithBackingCalendar:(CFCalendarRef)backing {
    if (backing == NULL) return nil;
    self = [super init];
    if (self != nil) {
        _calendar = backing;
    }
    return self;
}

+ (instancetype)currentCalendar {
    return [[NSCalendar alloc] _initWithBackingCalendar:CFCalendarCopyCurrent()];
}

+ (instancetype)autoupdatingCurrentCalendar {
    /* Without a KVO/notification pipeline for user-preference changes there is
     * nothing to which this object could subscribe, so it is a snapshot of the
     * current calendar rather than a live-updating view. */
    return [[NSCalendar alloc] _initWithBackingCalendar:CFCalendarCopyCurrent()];
}

+ (instancetype)calendarWithIdentifier:(NSCalendarIdentifier)identifier {
    return [[NSCalendar alloc] initWithCalendarIdentifier:identifier];
}

- (instancetype)initWithCalendarIdentifier:(NSCalendarIdentifier)identifier {
    CFCalendarRef backing = CFCalendarCreateWithIdentifier(
        kCFAllocatorDefault, NSCALENDAR_CF(CFStringRef, identifier));
    if (backing == NULL) return nil;
    _calendar = backing;
    return self;
}

- (void)dealloc {
    if (_calendar != NULL) CFRelease(_calendar);
}

- (NSCalendarIdentifier)calendarIdentifier {
    return NSCALENDAR_BORROWED(CFCalendarGetIdentifier(NSCalendarBacking(self)));
}

- (NSLocale *)locale {
    CFLocaleRef locale = CFCalendarCopyLocale(NSCalendarBacking(self));
    if (locale == NULL) return nil;
    return NSCALENDAR_TRANSFER(locale);
}

- (void)setLocale:(NSLocale *)locale {
    /* CFCalendarSetLocale cannot unset the locale with NULL, and nil is not a
     * meaningful value here, so a nil assignment is a no-op. */
    if (locale == nil) return;
    CFCalendarSetLocale(NSCalendarBacking(self), NSCALENDAR_CF(CFLocaleRef, locale));
}

- (NSUInteger)firstWeekday {
    return (NSUInteger)CFCalendarGetFirstWeekday(NSCalendarBacking(self));
}

- (void)setFirstWeekday:(NSUInteger)firstWeekday {
    CFCalendarSetFirstWeekday(NSCalendarBacking(self), (CFIndex)firstWeekday);
}

- (NSUInteger)minimumDaysInFirstWeek {
    return (NSUInteger)CFCalendarGetMinimumDaysInFirstWeek(NSCalendarBacking(self));
}

- (void)setMinimumDaysInFirstWeek:(NSUInteger)minimumDaysInFirstWeek {
    CFCalendarSetMinimumDaysInFirstWeek(NSCalendarBacking(self),
                                        (CFIndex)minimumDaysInFirstWeek);
}

- (NSArray<NSString *> *)eraSymbols {
    return NSCalendarCopySymbols(NSCalendarBacking(self), kCFDateFormatterEraSymbols);
}

- (NSArray<NSString *> *)longEraSymbols {
    return NSCalendarCopySymbols(NSCalendarBacking(self), kCFDateFormatterLongEraSymbols);
}

- (NSArray<NSString *> *)monthSymbols {
    return NSCalendarCopySymbols(NSCalendarBacking(self), kCFDateFormatterMonthSymbols);
}

- (NSArray<NSString *> *)shortMonthSymbols {
    return NSCalendarCopySymbols(NSCalendarBacking(self), kCFDateFormatterShortMonthSymbols);
}

- (NSArray<NSString *> *)veryShortMonthSymbols {
    return NSCalendarCopySymbols(NSCalendarBacking(self), kCFDateFormatterVeryShortMonthSymbols);
}

- (NSArray<NSString *> *)standaloneMonthSymbols {
    return NSCalendarCopySymbols(NSCalendarBacking(self), kCFDateFormatterStandaloneMonthSymbols);
}

- (NSArray<NSString *> *)shortStandaloneMonthSymbols {
    return NSCalendarCopySymbols(NSCalendarBacking(self), kCFDateFormatterShortStandaloneMonthSymbols);
}

- (NSArray<NSString *> *)veryShortStandaloneMonthSymbols {
    return NSCalendarCopySymbols(NSCalendarBacking(self), kCFDateFormatterVeryShortStandaloneMonthSymbols);
}

- (NSArray<NSString *> *)weekdaySymbols {
    return NSCalendarCopySymbols(NSCalendarBacking(self), kCFDateFormatterWeekdaySymbols);
}

- (NSArray<NSString *> *)shortWeekdaySymbols {
    return NSCalendarCopySymbols(NSCalendarBacking(self), kCFDateFormatterShortWeekdaySymbols);
}

- (NSArray<NSString *> *)veryShortWeekdaySymbols {
    return NSCalendarCopySymbols(NSCalendarBacking(self), kCFDateFormatterVeryShortWeekdaySymbols);
}

- (NSArray<NSString *> *)standaloneWeekdaySymbols {
    return NSCalendarCopySymbols(NSCalendarBacking(self), kCFDateFormatterStandaloneWeekdaySymbols);
}

- (NSArray<NSString *> *)shortStandaloneWeekdaySymbols {
    return NSCalendarCopySymbols(NSCalendarBacking(self), kCFDateFormatterShortStandaloneWeekdaySymbols);
}

- (NSArray<NSString *> *)veryShortStandaloneWeekdaySymbols {
    return NSCalendarCopySymbols(NSCalendarBacking(self), kCFDateFormatterVeryShortStandaloneWeekdaySymbols);
}

- (NSArray<NSString *> *)quarterSymbols {
    return NSCalendarCopySymbols(NSCalendarBacking(self), kCFDateFormatterQuarterSymbols);
}

- (NSArray<NSString *> *)shortQuarterSymbols {
    return NSCalendarCopySymbols(NSCalendarBacking(self), kCFDateFormatterShortQuarterSymbols);
}

- (NSArray<NSString *> *)standaloneQuarterSymbols {
    return NSCalendarCopySymbols(NSCalendarBacking(self), kCFDateFormatterStandaloneQuarterSymbols);
}

- (NSArray<NSString *> *)shortStandaloneQuarterSymbols {
    return NSCalendarCopySymbols(NSCalendarBacking(self), kCFDateFormatterShortStandaloneQuarterSymbols);
}

- (NSString *)AMSymbol {
    return NSCalendarCopySymbols(NSCalendarBacking(self), kCFDateFormatterAMSymbol);
}

- (NSString *)PMSymbol {
    return NSCalendarCopySymbols(NSCalendarBacking(self), kCFDateFormatterPMSymbol);
}

- (NSRange)minimumRangeOfUnit:(NSCalendarUnit)unit {
    if (unit == NSCalendarUnitNanosecond) return NSMakeRange(0, 1000000000);
    if (!NSCalendarUnitIsCoreFoundation(unit)) return NSMakeRange(NSNotFound, NSNotFound);
    return NSCalendarRangeFromCFRange(CFCalendarGetMinimumRangeOfUnit(
        NSCalendarBacking(self), (CFCalendarUnit)unit));
}

- (NSRange)maximumRangeOfUnit:(NSCalendarUnit)unit {
    if (unit == NSCalendarUnitNanosecond) return NSMakeRange(0, 1000000000);
    if (!NSCalendarUnitIsCoreFoundation(unit)) return NSMakeRange(NSNotFound, NSNotFound);
    return NSCalendarRangeFromCFRange(CFCalendarGetMaximumRangeOfUnit(
        NSCalendarBacking(self), (CFCalendarUnit)unit));
}

- (NSDateComponents *)components:(NSCalendarUnit)unitFlags fromDate:(NSDate *)date {
    NSDateComponents *components = [[NSDateComponents alloc] init];
    CFAbsoluteTime absoluteTime = [date timeIntervalSinceReferenceDate];
    int era = 0, year = 0, quarter = 0, month = 0, weekOfMonth = 0, weekOfYear = 0, yearForWeekOfYear = 0;
    int day = 0, weekday = 0, weekdayOrdinal = 0, hour = 0, minute = 0, second = 0;
    if (!CFCalendarDecomposeAbsoluteTime(NSCalendarBacking(self), absoluteTime,
                                         NSCalendarAllComponentsDescriptor,
                                         &era, &year, &quarter, &month, &weekOfMonth, &weekOfYear,
                                         &yearForWeekOfYear, &day, &weekday, &weekdayOrdinal,
                                         &hour, &minute, &second)) return components;
    if (unitFlags & NSCalendarUnitEra) components.era = era;
    if (unitFlags & NSCalendarUnitYear) components.year = year;
    if (unitFlags & NSCalendarUnitQuarter) components.quarter = quarter;
    if (unitFlags & NSCalendarUnitMonth) components.month = month;
    if (unitFlags & NSCalendarUnitWeekOfMonth) components.weekOfMonth = weekOfMonth;
    if (unitFlags & NSCalendarUnitWeekOfYear) components.weekOfYear = weekOfYear;
    if (unitFlags & NSCalendarUnitYearForWeekOfYear) components.yearForWeekOfYear = yearForWeekOfYear;
    if (unitFlags & NSCalendarUnitDay) components.day = day;
    if (unitFlags & NSCalendarUnitWeekday) components.weekday = weekday;
    if (unitFlags & NSCalendarUnitWeekdayOrdinal) components.weekdayOrdinal = weekdayOrdinal;
    if (unitFlags & NSCalendarUnitHour) components.hour = hour;
    if (unitFlags & NSCalendarUnitMinute) components.minute = minute;
    if (unitFlags & NSCalendarUnitSecond) components.second = second;
    return components;
}

- (NSDateComponents *)components:(NSCalendarUnit)unitFlags
                        fromDate:(NSDate *)startingDate
                          toDate:(NSDate *)resultDate
                         options:(NSCalendarOptions)options {
    return NSCalendarComponentsBetween(NSCalendarBacking(self), unitFlags,
                                       [startingDate timeIntervalSinceReferenceDate],
                                       [resultDate timeIntervalSinceReferenceDate],
                                       options);
}

- (NSDate *)dateFromComponents:(NSDateComponents *)components {
    return NSCalendarMakeDate(NSCalendarBacking(self), components);
}

- (NSDate *)dateByAddingComponents:(NSDateComponents *)components
                            toDate:(NSDate *)date
                           options:(NSCalendarOptions)options {
    CFAbsoluteTime absoluteTime = [date timeIntervalSinceReferenceDate];
    int era = NSCalendarComponentOrDefault(components.era, 0);
    int year = NSCalendarComponentOrDefault(components.year, 0);
    int quarter = NSCalendarComponentOrDefault(components.quarter, 0);
    int month = NSCalendarComponentOrDefault(components.month, 0);
    int weekOfMonth = NSCalendarComponentOrDefault(components.weekOfMonth, 0);
    int weekOfYear = NSCalendarComponentOrDefault(components.weekOfYear, 0);
    int yearForWeekOfYear = NSCalendarComponentOrDefault(components.yearForWeekOfYear, 0);
    int day = NSCalendarComponentOrDefault(components.day, 0);
    int weekday = NSCalendarComponentOrDefault(components.weekday, 0);
    int weekdayOrdinal = NSCalendarComponentOrDefault(components.weekdayOrdinal, 0);
    int hour = NSCalendarComponentOrDefault(components.hour, 0);
    int minute = NSCalendarComponentOrDefault(components.minute, 0);
    int second = NSCalendarComponentOrDefault(components.second, 0);
    if (!CFCalendarAddComponents(NSCalendarBacking(self), &absoluteTime,
                                 (CFOptionFlags)options, NSCalendarAllComponentsDescriptor,
                                 era, year, quarter, month, weekOfMonth, weekOfYear,
                                 yearForWeekOfYear, day, weekday, weekdayOrdinal,
                                 hour, minute, second)) return nil;
    return [NSDate dateWithTimeIntervalSinceReferenceDate:absoluteTime];
}

- (NSDate *)dateByAddingUnit:(NSCalendarUnit)unit
                       value:(NSInteger)value
                      toDate:(NSDate *)date
                     options:(NSCalendarOptions)options {
    const char *descriptor = NULL;
    switch (unit) {
        case NSCalendarUnitEra: descriptor = "G"; break;
        case NSCalendarUnitYear: descriptor = "y"; break;
        case NSCalendarUnitQuarter: descriptor = "Q"; break;
        case NSCalendarUnitMonth: descriptor = "M"; break;
        case NSCalendarUnitWeekOfMonth: descriptor = "W"; break;
        case NSCalendarUnitWeekOfYear: descriptor = "w"; break;
        case NSCalendarUnitYearForWeekOfYear: descriptor = "Y"; break;
        case NSCalendarUnitDay: descriptor = "d"; break;
        case NSCalendarUnitWeekday: descriptor = "E"; break;
        case NSCalendarUnitWeekdayOrdinal: descriptor = "F"; break;
        case NSCalendarUnitHour: descriptor = "H"; break;
        case NSCalendarUnitMinute: descriptor = "m"; break;
        case NSCalendarUnitSecond: descriptor = "s"; break;
        default: return nil;
    }
    CFAbsoluteTime absoluteTime = [date timeIntervalSinceReferenceDate];
    if (!CFCalendarAddComponents(NSCalendarBacking(self), &absoluteTime,
                                 (CFOptionFlags)options, descriptor, (int)value)) return nil;
    return [NSDate dateWithTimeIntervalSinceReferenceDate:absoluteTime];
}

- (NSDate *)dateBySettingUnit:(NSCalendarUnit)unit
                        value:(NSInteger)value
                       ofDate:(NSDate *)date
                      options:(NSCalendarOptions)opts {
    NSCalendarUnit flags = (NSCalendarUnitEra | NSCalendarUnitYear | NSCalendarUnitMonth | NSCalendarUnitDay |
                            NSCalendarUnitHour | NSCalendarUnitMinute | NSCalendarUnitSecond | NSCalendarUnitNanosecond |
                            NSCalendarUnitWeekday | NSCalendarUnitWeekdayOrdinal | NSCalendarUnitQuarter |
                            NSCalendarUnitWeekOfMonth | NSCalendarUnitWeekOfYear | NSCalendarUnitYearForWeekOfYear);
    NSDateComponents *components = [self components:flags fromDate:date];
    [components setValue:value forComponent:unit];
    NSDate *result = [self dateFromComponents:components];
    if (!result) return nil;
    if ((opts & NSCalendarMatchNextTime)) {
        for (NSInteger i = 0; i < 3; i++) {
            if ([result compare:date] == NSOrderedDescending) break;
            NSDate *advanced = [self dateByAddingUnit:unit value:1 toDate:result options:0];
            if (!advanced) break;
            result = advanced;
        }
    }
    return result;
}

- (NSDate *)dateBySettingHour:(NSInteger)hour
                        minute:(NSInteger)minute
                        second:(NSInteger)second
                        ofDate:(NSDate *)date
                       options:(NSCalendarOptions)opts {
    NSCalendarUnit flags = (NSCalendarUnitEra | NSCalendarUnitYear | NSCalendarUnitMonth | NSCalendarUnitDay |
                            NSCalendarUnitHour | NSCalendarUnitMinute | NSCalendarUnitSecond | NSCalendarUnitNanosecond |
                            NSCalendarUnitWeekday | NSCalendarUnitWeekdayOrdinal | NSCalendarUnitQuarter |
                            NSCalendarUnitWeekOfMonth | NSCalendarUnitWeekOfYear | NSCalendarUnitYearForWeekOfYear);
    NSDateComponents *components = [self components:flags fromDate:date];
    components.hour = hour;
    components.minute = minute;
    components.second = second;
    NSDate *result = [self dateFromComponents:components];
    if (!result) return nil;
    if ((opts & NSCalendarMatchNextTime)) {
        for (NSInteger i = 0; i < 3; i++) {
            if ([result compare:date] == NSOrderedDescending) break;
            NSDate *advanced = [self dateByAddingUnit:NSCalendarUnitDay value:1 toDate:result options:0];
            if (!advanced) break;
            result = advanced;
        }
    }
    return result;
}

- (NSDate *)nextDateAfterDate:(NSDate *)date
           matchingComponents:(NSDateComponents *)requested
                      options:(NSCalendarOptions)opts {
    if (!date || !requested) return nil;

    /* Find the highest specified unit; with nothing to match, there is no
     * result. Exact matching only ever checks specified (non-undefined)
     * fields, via -date:matchesComponents:. */
    NSCalendarUnit allFlags = (NSCalendarUnitEra | NSCalendarUnitYear | NSCalendarUnitYearForWeekOfYear |
                               NSCalendarUnitQuarter | NSCalendarUnitMonth | NSCalendarUnitWeekOfMonth |
                               NSCalendarUnitWeekOfYear | NSCalendarUnitDay | NSCalendarUnitWeekday |
                               NSCalendarUnitWeekdayOrdinal | NSCalendarUnitHour | NSCalendarUnitMinute |
                               NSCalendarUnitSecond);
    NSCalendarUnit highest = 0;
    BOOL any = NO;
    BOOL usesWeekPath = NO;
#define NSCALENDAR_HIGHEST(flag, field)                                        \
    if (requested.field != NSDateComponentUndefined) {                         \
        if (!any || NSCalendarUnitRank(flag) < NSCalendarUnitRank(highest)) {  \
            highest = flag;                                                    \
        }                                                                      \
        any = YES;                                                             \
        if (flag == NSCalendarUnitWeekday || flag == NSCalendarUnitWeekOfYear ||\
            flag == NSCalendarUnitYearForWeekOfYear) {                         \
            usesWeekPath = YES;                                                \
        }                                                                      \
    }
    NSCALENDAR_HIGHEST(NSCalendarUnitEra, era)
    NSCALENDAR_HIGHEST(NSCalendarUnitYear, year)
    NSCALENDAR_HIGHEST(NSCalendarUnitQuarter, quarter)
    NSCALENDAR_HIGHEST(NSCalendarUnitMonth, month)
    NSCALENDAR_HIGHEST(NSCalendarUnitWeekOfMonth, weekOfMonth)
    NSCALENDAR_HIGHEST(NSCalendarUnitWeekOfYear, weekOfYear)
    NSCALENDAR_HIGHEST(NSCalendarUnitYearForWeekOfYear, yearForWeekOfYear)
    NSCALENDAR_HIGHEST(NSCalendarUnitDay, day)
    NSCALENDAR_HIGHEST(NSCalendarUnitWeekday, weekday)
    NSCALENDAR_HIGHEST(NSCalendarUnitHour, hour)
    NSCALENDAR_HIGHEST(NSCalendarUnitMinute, minute)
    NSCALENDAR_HIGHEST(NSCalendarUnitSecond, second)
#undef NSCALENDAR_HIGHEST
    if (!any) return nil;

    int highestRank = NSCalendarUnitRank(highest);
    NSCalendarUnit stepUnit = NSCalendarUnitStepForRank(highestRank);

    /* The forward probe: NSDateComponents filled from the probe date for every
     * unit coarser than the highest specified one, from the request for
     * specified units, and from the unit base conventions for finely-specified
     * smaller units. Underspecified results compose to a concrete absolute
     * date, exactly as -dateFromComponents: does elsewhere in this file. */
    NSDate *probe = date;
    NSDate *firstCandidateOfYear = nil;
    NSInteger lastProbeYear = NSDateComponentUndefined;
    const NSInteger strictLimit = 10000;
    for (NSInteger iteration = 0; iteration < strictLimit; iteration++) {
        NSDateComponents *fill = [self components:allFlags fromDate:probe];
        if (fill == nil) return nil;
        if (requested.era != NSDateComponentUndefined) fill.era = requested.era;
        if (requested.year != NSDateComponentUndefined) fill.year = requested.year;
        if (requested.quarter != NSDateComponentUndefined) fill.quarter = requested.quarter;
        if (requested.month != NSDateComponentUndefined) {
            fill.month = requested.month;
        } else if (requested.quarter != NSDateComponentUndefined) {
            /* dateFromComponents: cannot express a quarter, so a quarter-only
             * request is anchored on the first month of that quarter. */
            fill.month = (requested.quarter - 1) * 3 + 1;
        }
        if (requested.weekOfMonth != NSDateComponentUndefined) fill.weekOfMonth = requested.weekOfMonth;
        if (requested.weekOfYear != NSDateComponentUndefined) fill.weekOfYear = requested.weekOfYear;
        if (requested.yearForWeekOfYear != NSDateComponentUndefined) fill.yearForWeekOfYear = requested.yearForWeekOfYear;
        if (requested.day != NSDateComponentUndefined) fill.day = requested.day;
        if (requested.weekday != NSDateComponentUndefined) fill.weekday = requested.weekday;
        if (requested.weekdayOrdinal != NSDateComponentUndefined) fill.weekdayOrdinal = requested.weekdayOrdinal;
        if (requested.hour != NSDateComponentUndefined) fill.hour = requested.hour;
        if (requested.minute != NSDateComponentUndefined) fill.minute = requested.minute;
        if (requested.second != NSDateComponentUndefined) fill.second = requested.second;

        /* Collapse units finer than the highest specified one down to their
         * base default, so that, for example, a day request times out at
         * 00:00:00 rather than inheriting the probe's wall clock. */
#define NSCALENDAR_COLLAPSE(flag, field)                                  \
        if (requested.field == NSDateComponentUndefined &&                \
            NSCalendarUnitRank(flag) > highestRank) {                     \
            fill.field = NSCalendarUnitBaseValue(flag);                   \
        }
        NSCALENDAR_COLLAPSE(NSCalendarUnitYear, year)
        NSCALENDAR_COLLAPSE(NSCalendarUnitQuarter, quarter)
        /* The month collapse is the one exception to the size rule: a quarter
         * request anchors its month to the first month of the quarter up
         * above, and that anchor must survive. */
        if (requested.month == NSDateComponentUndefined &&
            requested.quarter == NSDateComponentUndefined &&
            NSCalendarUnitRank(NSCalendarUnitMonth) > highestRank) {
            fill.month = NSCalendarUnitBaseValue(NSCalendarUnitMonth);
        }
        NSCALENDAR_COLLAPSE(NSCalendarUnitWeekOfMonth, weekOfMonth)
        NSCALENDAR_COLLAPSE(NSCalendarUnitWeekOfYear, weekOfYear)
        NSCALENDAR_COLLAPSE(NSCalendarUnitYearForWeekOfYear, yearForWeekOfYear)
        NSCALENDAR_COLLAPSE(NSCalendarUnitDay, day)
        NSCALENDAR_COLLAPSE(NSCalendarUnitWeekday, weekday)
        NSCALENDAR_COLLAPSE(NSCalendarUnitHour, hour)
        NSCALENDAR_COLLAPSE(NSCalendarUnitMinute, minute)
        NSCALENDAR_COLLAPSE(NSCalendarUnitSecond, second)
#undef NSCALENDAR_COLLAPSE

        /* NSCalendarMakeDate() takes the week composition path ("GwYEHms")
         * whenever any of weekday/weekOfYear/yearForWeekOfYear is non-
         * undefined, and that path ignores the month/day fields. A request
         * that names a week-based unit therefore composes on the probe's own
         * weekOfYear/yearForWeekOfYear (already present from the full
         * decomposition above); any other request must clear those three
         * fields or it would silently compose on the wrong path. */
        if (!usesWeekPath) {
            fill.weekOfYear = NSDateComponentUndefined;
            fill.yearForWeekOfYear = NSDateComponentUndefined;
            fill.weekday = NSDateComponentUndefined;
        }

        NSDate *candidate = [self dateFromComponents:fill];
        if (!candidate) return nil;
        if (requested.nanosecond != NSDateComponentUndefined) {
            candidate = NSCalendarDateByAddingNanoseconds(candidate, requested.nanosecond);
        }

        /* The search is strictly forward: a candidate equal to or before the
         * input date (even an exact one) is skipped. */
        if ([candidate compare:date] == NSOrderedDescending) {
            if ([self date:candidate matchesComponents:requested]) return candidate;
            /* Closest match. Apple's non-strict search returns the next
             * existing time once the window between the probe periods is
             * exhausted rather than raising, so the composed (possibly rolled)
             * candidate is the answer. Strict searches keep going for an exact
             * match instead. */
            if (!(opts & NSCalendarMatchStrictly)) return candidate;
        }

        /* Freeze detection. Candidate composition can legitimately repeat
         * within one calendar year (say a leap-day request searched by month),
         * so an equal candidate is only a dead end once the probe has crossed
         * into a new calendar year and composed the same absolute time as the
         * one that opened the previous year (for example a year in the past).
         * Without this, such requests spin until the strict limit. */
        NSDateComponents *probeYearComps = [self components:NSCalendarUnitYear fromDate:probe];
        NSInteger probeYear = (probeYearComps != nil) ? probeYearComps.year : NSDateComponentUndefined;
        if (probeYear != NSDateComponentUndefined) {
            if (probeYear != lastProbeYear) {
                if (firstCandidateOfYear != nil && [candidate isEqualToDate:firstCandidateOfYear]) return nil;
                firstCandidateOfYear = candidate;
                lastProbeYear = probeYear;
            }
        }

        NSDate *next = [self dateByAddingUnit:stepUnit value:1 toDate:probe options:0];
        if (!next || [next timeIntervalSinceReferenceDate] <= [probe timeIntervalSinceReferenceDate]) {
            return nil;
        }
        probe = next;
    }
    return nil;
}

- (NSDate *)nextDateAfterDate:(NSDate *)date
                matchingUnit:(NSCalendarUnit)unit
                       value:(NSInteger)value
                     options:(NSCalendarOptions)opts {
    NSDateComponents *comps = [[NSDateComponents alloc] init];
    [comps setValue:value forComponent:unit];
    NSDate *result = [self nextDateAfterDate:date matchingComponents:comps options:opts];
    return result;
}

- (NSDate *)nextDateAfterDate:(NSDate *)date
               matchingHour:(NSInteger)hour
                     minute:(NSInteger)minute
                     second:(NSInteger)second
                    options:(NSCalendarOptions)opts {
    NSDateComponents *comps = [[NSDateComponents alloc] init];
    comps.hour = hour;
    comps.minute = minute;
    comps.second = second;
    return [self nextDateAfterDate:date matchingComponents:comps options:opts];
}

- (NSRange)rangeOfUnit:(NSCalendarUnit)smaller inUnit:(NSCalendarUnit)larger forDate:(NSDate *)date {
    CFRange range = CFCalendarGetRangeOfUnit(NSCalendarBacking(self),
                                             (CFCalendarUnit)smaller, (CFCalendarUnit)larger,
                                             [date timeIntervalSinceReferenceDate]);
    /* CoreFoundation reports an unsupported pairing as kCFNotFound; NSRange
     * spells the same thing NSNotFound. */
    return NSCalendarRangeFromCFRange(range);
}

- (NSUInteger)ordinalityOfUnit:(NSCalendarUnit)smaller inUnit:(NSCalendarUnit)larger forDate:(NSDate *)date {
    CFIndex ordinality = CFCalendarGetOrdinalityOfUnit(NSCalendarBacking(self),
                                                        (CFCalendarUnit)smaller,
                                                        (CFCalendarUnit)larger,
                                                        [date timeIntervalSinceReferenceDate]);
    if (ordinality == kCFNotFound) return NSNotFound;
    return (NSUInteger)ordinality;
}

- (BOOL)rangeOfUnit:(NSCalendarUnit)unit
          startDate:(NSDate **)datep
           interval:(NSTimeInterval *)tip
            forDate:(NSDate *)date {
    CFAbsoluteTime start = 0;
    CFTimeInterval interval = 0;
    if (!CFCalendarGetTimeRangeOfUnit(NSCalendarBacking(self), (CFCalendarUnit)unit,
                                      [date timeIntervalSinceReferenceDate],
                                      &start, &interval)) return NO;
    if (datep != NULL) *datep = [NSDate dateWithTimeIntervalSinceReferenceDate:start];
    if (tip != NULL) *tip = (NSTimeInterval)interval;
    return YES;
}

- (void)getEra:(NSInteger *)eraValuePointer
          year:(NSInteger *)yearValuePointer
         month:(NSInteger *)monthValuePointer
           day:(NSInteger *)dayValuePointer
      fromDate:(NSDate *)date {
    NSDateComponents *components = [self components:(NSCalendarUnitEra | NSCalendarUnitYear |
                                                     NSCalendarUnitMonth | NSCalendarUnitDay)
                                           fromDate:date];
    if (eraValuePointer != NULL) *eraValuePointer = components.era;
    if (yearValuePointer != NULL) *yearValuePointer = components.year;
    if (monthValuePointer != NULL) *monthValuePointer = components.month;
    if (dayValuePointer != NULL) *dayValuePointer = components.day;
}

- (void)getEra:(NSInteger *)eraValuePointer
yearForWeekOfYear:(NSInteger *)yearValuePointer
    weekOfYear:(NSInteger *)weekValuePointer
       weekday:(NSInteger *)weekdayValuePointer
      fromDate:(NSDate *)date {
    NSDateComponents *components = [self components:(NSCalendarUnitEra | NSCalendarUnitYearForWeekOfYear |
                                                     NSCalendarUnitWeekOfYear | NSCalendarUnitWeekday)
                                           fromDate:date];
    if (eraValuePointer != NULL) *eraValuePointer = components.era;
    if (yearValuePointer != NULL) *yearValuePointer = components.yearForWeekOfYear;
    if (weekValuePointer != NULL) *weekValuePointer = components.weekOfYear;
    if (weekdayValuePointer != NULL) *weekdayValuePointer = components.weekday;
}

- (void)getHour:(NSInteger *)hourValuePointer
         minute:(NSInteger *)minuteValuePointer
         second:(NSInteger *)secondValuePointer
     nanosecond:(NSInteger *)nanosecondValuePointer
       fromDate:(NSDate *)date {
    NSDateComponents *components = [self components:(NSCalendarUnitHour | NSCalendarUnitMinute |
                                                     NSCalendarUnitSecond)
                                           fromDate:date];
    if (hourValuePointer != NULL) *hourValuePointer = components.hour;
    if (minuteValuePointer != NULL) *minuteValuePointer = components.minute;
    if (secondValuePointer != NULL) *secondValuePointer = components.second;
    if (nanosecondValuePointer != NULL) {
        *nanosecondValuePointer = NSCalendarNanosecond([date timeIntervalSinceReferenceDate]);
    }
}

- (NSInteger)component:(NSCalendarUnit)unit fromDate:(NSDate *)date {
    CFAbsoluteTime absoluteTime = [date timeIntervalSinceReferenceDate];
    if (unit == NSCalendarUnitNanosecond) return NSCalendarNanosecond(absoluteTime);
    /* The calendar and time zone are not decomposed from the absolute time;
     * Apple answers zero for both. */
    if (unit == NSCalendarUnitCalendar || unit == NSCalendarUnitTimeZone) return 0;
    if (unit == NSCalendarUnitDayOfYear) {
        int year = 0, dayOfYear = 0;
        if (!CFCalendarDecomposeAbsoluteTime(NSCalendarBacking(self), absoluteTime,
                                             "yD", &year, &dayOfYear)) {
            return NSDateComponentUndefined;
        }
        return dayOfYear;
    }
    NSDateComponents *components = [self components:unit fromDate:date];
    switch (unit) {
        case NSCalendarUnitEra: return components.era;
        case NSCalendarUnitYear: return components.year;
        case NSCalendarUnitQuarter: return components.quarter;
        case NSCalendarUnitMonth: return components.month;
        case NSCalendarUnitWeekOfMonth: return components.weekOfMonth;
        case NSCalendarUnitWeekOfYear: return components.weekOfYear;
        case NSCalendarUnitYearForWeekOfYear: return components.yearForWeekOfYear;
        case NSCalendarUnitDay: return components.day;
        case NSCalendarUnitWeekday: return components.weekday;
        case NSCalendarUnitWeekdayOrdinal: return components.weekdayOrdinal;
        case NSCalendarUnitHour: return components.hour;
        case NSCalendarUnitMinute: return components.minute;
        case NSCalendarUnitSecond: return components.second;
        default: return NSDateComponentUndefined;
    }
}

- (NSDate *)dateWithEra:(NSInteger)eraValue
                   year:(NSInteger)yearValue
                  month:(NSInteger)monthValue
                    day:(NSInteger)dayValue
                   hour:(NSInteger)hourValue
                 minute:(NSInteger)minuteValue
                 second:(NSInteger)secondValue
             nanosecond:(NSInteger)nanosecondValue {
    int era = NSCalendarComponentOrDefault(eraValue, 1);
    int year = NSCalendarComponentOrDefault(yearValue, 1);
    int month = NSCalendarComponentOrDefault(monthValue, 1);
    int day = NSCalendarComponentOrDefault(dayValue, 1);
    int hour = NSCalendarComponentOrDefault(hourValue, 0);
    int minute = NSCalendarComponentOrDefault(minuteValue, 0);
    int second = NSCalendarComponentOrDefault(secondValue, 0);
    CFAbsoluteTime absoluteTime = 0;
    if (!CFCalendarComposeAbsoluteTime(NSCalendarBacking(self), &absoluteTime,
                                        "GyMdHms", era, year, month, day,
                                        hour, minute, second)) return nil;
    return NSCalendarDateByAddingNanoseconds([NSDate dateWithTimeIntervalSinceReferenceDate:absoluteTime],
                                             nanosecondValue);
}

- (NSDate *)dateWithEra:(NSInteger)eraValue
       yearForWeekOfYear:(NSInteger)yearValue
             weekOfYear:(NSInteger)weekValue
                weekday:(NSInteger)weekdayValue
                   hour:(NSInteger)hourValue
                 minute:(NSInteger)minuteValue
                 second:(NSInteger)secondValue
             nanosecond:(NSInteger)nanosecondValue {
    int era = NSCalendarComponentOrDefault(eraValue, 1);
    int year = NSCalendarComponentOrDefault(yearValue, 1);
    int week = NSCalendarComponentOrDefault(weekValue, 1);
    int weekday = NSCalendarComponentOrDefault(weekdayValue, 1);
    int hour = NSCalendarComponentOrDefault(hourValue, 0);
    int minute = NSCalendarComponentOrDefault(minuteValue, 0);
    int second = NSCalendarComponentOrDefault(secondValue, 0);
    CFAbsoluteTime absoluteTime = 0;
    if (!CFCalendarComposeAbsoluteTime(NSCalendarBacking(self), &absoluteTime,
                                        "GwYEHms", era, week, year, weekday,
                                        hour, minute, second)) return nil;
    return NSCalendarDateByAddingNanoseconds([NSDate dateWithTimeIntervalSinceReferenceDate:absoluteTime],
                                             nanosecondValue);
}

- (NSDate *)startOfDayForDate:(NSDate *)date {
    NSDate *start = nil;
    if (![self rangeOfUnit:NSCalendarUnitDay startDate:&start interval:NULL forDate:date]) return date;
    return start != nil ? start : date;
}

- (NSComparisonResult)compareDate:(NSDate *)date1
                           toDate:(NSDate *)date2
                toUnitGranularity:(NSCalendarUnit)unit {
    CFAbsoluteTime time1 = [date1 timeIntervalSinceReferenceDate];
    CFAbsoluteTime time2 = [date2 timeIntervalSinceReferenceDate];
    NSCalendarDecomposed decomposed1, decomposed2;
    if (!NSCalendarDecompose(NSCalendarBacking(self), time1, &decomposed1) ||
        !NSCalendarDecompose(NSCalendarBacking(self), time2, &decomposed2)) {
        return NSCalendarCompareValues((NSInteger)time1, (NSInteger)time2);
    }
    return NSCalendarCompareDecomposed(&decomposed1, &decomposed2, unit, time1, time2);
}

- (BOOL)isDate:(NSDate *)date1 equalToDate:(NSDate *)date2 toUnitGranularity:(NSCalendarUnit)unit {
    return [self compareDate:date1 toDate:date2 toUnitGranularity:unit] == NSOrderedSame;
}

- (BOOL)isDate:(NSDate *)date1 inSameDayAsDate:(NSDate *)date2 {
    return [self compareDate:date1 toDate:date2 toUnitGranularity:NSCalendarUnitDay] == NSOrderedSame;
}

- (BOOL)isDateInToday:(NSDate *)date {
    return [self isDate:date inSameDayAsDate:[NSDate date]];
}

- (BOOL)isDateInYesterday:(NSDate *)date {
    NSDate *yesterday = [self dateByAddingUnit:NSCalendarUnitDay value:-1 toDate:[NSDate date] options:0];
    return [self isDate:date inSameDayAsDate:yesterday];
}

- (BOOL)isDateInTomorrow:(NSDate *)date {
    NSDate *tomorrow = [self dateByAddingUnit:NSCalendarUnitDay value:1 toDate:[NSDate date] options:0];
    return [self isDate:date inSameDayAsDate:tomorrow];
}

- (BOOL)date:(NSDate *)date matchesComponents:(NSDateComponents *)components {
    CFAbsoluteTime absoluteTime = [date timeIntervalSinceReferenceDate];
    NSCalendarDecomposed decomposed;
    if (!NSCalendarDecompose(NSCalendarBacking(self), absoluteTime, &decomposed)) return NO;
#define NSCALENDAR_MATCH(property, field)                                     \
    if (components.property != NSDateComponentUndefined &&                    \
        components.property != (NSInteger)decomposed.field) return NO;
    NSCALENDAR_MATCH(era, era)
    NSCALENDAR_MATCH(year, year)
    NSCALENDAR_MATCH(quarter, quarter)
    NSCALENDAR_MATCH(month, month)
    NSCALENDAR_MATCH(weekOfMonth, weekOfMonth)
    NSCALENDAR_MATCH(weekOfYear, weekOfYear)
    NSCALENDAR_MATCH(yearForWeekOfYear, yearForWeekOfYear)
    NSCALENDAR_MATCH(day, day)
    NSCALENDAR_MATCH(weekday, weekday)
    NSCALENDAR_MATCH(weekdayOrdinal, weekdayOrdinal)
    NSCALENDAR_MATCH(hour, hour)
    NSCALENDAR_MATCH(minute, minute)
    NSCALENDAR_MATCH(second, second)
#undef NSCALENDAR_MATCH
    return YES;
}

- (NSDateComponents *)components:(NSCalendarUnit)unitFlags
               fromDateComponents:(NSDateComponents *)startingDateComp
                 toDateComponents:(NSDateComponents *)resultDateComp
                          options:(NSCalendarOptions)options {
    CFCalendarRef calendar = NSCalendarBacking(self);
    NSDate *startingDate = NSCalendarMakeDate(calendar, startingDateComp);
    NSDate *resultDate = NSCalendarMakeDate(calendar, resultDateComp);
    if (startingDate == nil || resultDate == nil) return [[NSDateComponents alloc] init];
    return NSCalendarComponentsBetween(calendar, unitFlags,
                                       [startingDate timeIntervalSinceReferenceDate],
                                       [resultDate timeIntervalSinceReferenceDate],
                                       options);
}

- (id)copyWithZone:(NSZone *)zone {
    (void)zone;
    NSCalendar *copy = [NSCalendar calendarWithIdentifier:self.calendarIdentifier];
    if (copy == nil) return nil;
    copy.firstWeekday = self.firstWeekday;
    copy.minimumDaysInFirstWeek = self.minimumDaysInFirstWeek;
    copy.locale = self.locale;
    return copy;
}

#pragma mark - NSCoding

+ (BOOL)supportsSecureCoding {
    return YES;
}

- (void)encodeWithCoder:(NSCoder *)coder {
    if (![coder allowsKeyedCoding]) return;
    [coder encodeObject:self.calendarIdentifier forKey:@"NSIdentifier"];
    [coder encodeInteger:(NSInteger)self.firstWeekday forKey:@"NSFirstWeekday"];
    [coder encodeInteger:(NSInteger)self.minimumDaysInFirstWeek forKey:@"NSMinimumDaysInFirstWeek"];
    [coder encodeObject:self.locale forKey:@"NSLocale"];
}

- (instancetype)initWithCoder:(NSCoder *)coder {
    if (![coder allowsKeyedCoding]) {
        return [[NSCalendar alloc] initWithCalendarIdentifier:NSCalendarIdentifierGregorian];
    }
    NSString *identifier = [coder decodeObjectForKey:@"NSIdentifier"];
    if (identifier == nil) identifier = NSCalendarIdentifierGregorian;
    CFCalendarRef backing = CFCalendarCreateWithIdentifier(
        kCFAllocatorDefault, NSCALENDAR_CF(CFStringRef, identifier));
    if (backing == NULL) return nil;
    _calendar = backing;
    if ([coder containsValueForKey:@"NSFirstWeekday"]) {
        self.firstWeekday = (NSUInteger)[coder decodeIntegerForKey:@"NSFirstWeekday"];
    }
    if ([coder containsValueForKey:@"NSMinimumDaysInFirstWeek"]) {
        self.minimumDaysInFirstWeek = (NSUInteger)[coder decodeIntegerForKey:@"NSMinimumDaysInFirstWeek"];
    }
    if ([coder containsValueForKey:@"NSLocale"]) {
        self.locale = [coder decodeObjectForKey:@"NSLocale"];
    }
    return self;
}

@end
