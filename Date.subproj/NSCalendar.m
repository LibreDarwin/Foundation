/*
 * Copyright (C) 2026, Samuel Zormeister.
 *
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */

#import <Foundation/NSCalendar.h>
#import <Foundation/NSCoder.h>
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

static NSDate *NSCalendarDateByAddingNanoseconds(NSDate *date, NSInteger nanoseconds) {
    if (date == nil || nanoseconds == NSDateComponentUndefined || nanoseconds == 0) return date;
    return [NSDate dateWithTimeIntervalSinceReferenceDate:
                [date timeIntervalSinceReferenceDate] + (NSTimeInterval)nanoseconds / 1000000000.0];
}

/* Builds a date from components at the C level. This duplicates the two
 * dateWithEra: constructors, but it must not re-dispatch to `self`: an
 * NSCalendar instance's isa is the CoreFoundation-bridged class, so messaging
 * it can land in CoreFoundation's implementation instead of ours. */
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

+ (instancetype)currentCalendar {
    return NSCALENDAR_TRANSFER(CFCalendarCopyCurrent());
}

+ (instancetype)autoupdatingCurrentCalendar {
    /* Without a KVO/notification pipeline for user-preference changes there is
     * nothing to which this object could subscribe, so it is a snapshot of the
     * current calendar rather than a live-updating view. */
    return NSCALENDAR_TRANSFER(CFCalendarCopyCurrent());
}

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

- (NSLocale *)locale {
    CFLocaleRef locale = CFCalendarCopyLocale(NSCALENDAR_CF(CFCalendarRef, self));
    if (locale == NULL) return nil;
    return NSCALENDAR_TRANSFER(locale);
}

- (void)setLocale:(NSLocale *)locale {
    /* CFCalendarSetLocale cannot unset the locale with NULL, and nil is not a
     * meaningful value here, so a nil assignment is a no-op. */
    if (locale == nil) return;
    CFCalendarSetLocale(NSCALENDAR_CF(CFCalendarRef, self), NSCALENDAR_CF(CFLocaleRef, locale));
}

- (NSUInteger)firstWeekday {
    return (NSUInteger)CFCalendarGetFirstWeekday(NSCALENDAR_CF(CFCalendarRef, self));
}

- (void)setFirstWeekday:(NSUInteger)firstWeekday {
    CFCalendarSetFirstWeekday(NSCALENDAR_CF(CFCalendarRef, self), (CFIndex)firstWeekday);
}

- (NSUInteger)minimumDaysInFirstWeek {
    return (NSUInteger)CFCalendarGetMinimumDaysInFirstWeek(NSCALENDAR_CF(CFCalendarRef, self));
}

- (void)setMinimumDaysInFirstWeek:(NSUInteger)minimumDaysInFirstWeek {
    CFCalendarSetMinimumDaysInFirstWeek(NSCALENDAR_CF(CFCalendarRef, self),
                                        (CFIndex)minimumDaysInFirstWeek);
}

- (NSArray<NSString *> *)eraSymbols {
    return NSCalendarCopySymbols(NSCALENDAR_CF(CFCalendarRef, self), kCFDateFormatterEraSymbols);
}

- (NSArray<NSString *> *)longEraSymbols {
    return NSCalendarCopySymbols(NSCALENDAR_CF(CFCalendarRef, self), kCFDateFormatterLongEraSymbols);
}

- (NSArray<NSString *> *)monthSymbols {
    return NSCalendarCopySymbols(NSCALENDAR_CF(CFCalendarRef, self), kCFDateFormatterMonthSymbols);
}

- (NSArray<NSString *> *)shortMonthSymbols {
    return NSCalendarCopySymbols(NSCALENDAR_CF(CFCalendarRef, self), kCFDateFormatterShortMonthSymbols);
}

- (NSArray<NSString *> *)veryShortMonthSymbols {
    return NSCalendarCopySymbols(NSCALENDAR_CF(CFCalendarRef, self), kCFDateFormatterVeryShortMonthSymbols);
}

- (NSArray<NSString *> *)standaloneMonthSymbols {
    return NSCalendarCopySymbols(NSCALENDAR_CF(CFCalendarRef, self), kCFDateFormatterStandaloneMonthSymbols);
}

- (NSArray<NSString *> *)shortStandaloneMonthSymbols {
    return NSCalendarCopySymbols(NSCALENDAR_CF(CFCalendarRef, self), kCFDateFormatterShortStandaloneMonthSymbols);
}

- (NSArray<NSString *> *)veryShortStandaloneMonthSymbols {
    return NSCalendarCopySymbols(NSCALENDAR_CF(CFCalendarRef, self), kCFDateFormatterVeryShortStandaloneMonthSymbols);
}

- (NSArray<NSString *> *)weekdaySymbols {
    return NSCalendarCopySymbols(NSCALENDAR_CF(CFCalendarRef, self), kCFDateFormatterWeekdaySymbols);
}

- (NSArray<NSString *> *)shortWeekdaySymbols {
    return NSCalendarCopySymbols(NSCALENDAR_CF(CFCalendarRef, self), kCFDateFormatterShortWeekdaySymbols);
}

- (NSArray<NSString *> *)veryShortWeekdaySymbols {
    return NSCalendarCopySymbols(NSCALENDAR_CF(CFCalendarRef, self), kCFDateFormatterVeryShortWeekdaySymbols);
}

- (NSArray<NSString *> *)standaloneWeekdaySymbols {
    return NSCalendarCopySymbols(NSCALENDAR_CF(CFCalendarRef, self), kCFDateFormatterStandaloneWeekdaySymbols);
}

- (NSArray<NSString *> *)shortStandaloneWeekdaySymbols {
    return NSCalendarCopySymbols(NSCALENDAR_CF(CFCalendarRef, self), kCFDateFormatterShortStandaloneWeekdaySymbols);
}

- (NSArray<NSString *> *)veryShortStandaloneWeekdaySymbols {
    return NSCalendarCopySymbols(NSCALENDAR_CF(CFCalendarRef, self), kCFDateFormatterVeryShortStandaloneWeekdaySymbols);
}

- (NSArray<NSString *> *)quarterSymbols {
    return NSCalendarCopySymbols(NSCALENDAR_CF(CFCalendarRef, self), kCFDateFormatterQuarterSymbols);
}

- (NSArray<NSString *> *)shortQuarterSymbols {
    return NSCalendarCopySymbols(NSCALENDAR_CF(CFCalendarRef, self), kCFDateFormatterShortQuarterSymbols);
}

- (NSArray<NSString *> *)standaloneQuarterSymbols {
    return NSCalendarCopySymbols(NSCALENDAR_CF(CFCalendarRef, self), kCFDateFormatterStandaloneQuarterSymbols);
}

- (NSArray<NSString *> *)shortStandaloneQuarterSymbols {
    return NSCalendarCopySymbols(NSCALENDAR_CF(CFCalendarRef, self), kCFDateFormatterShortStandaloneQuarterSymbols);
}

- (NSString *)AMSymbol {
    return NSCalendarCopySymbols(NSCALENDAR_CF(CFCalendarRef, self), kCFDateFormatterAMSymbol);
}

- (NSString *)PMSymbol {
    return NSCalendarCopySymbols(NSCALENDAR_CF(CFCalendarRef, self), kCFDateFormatterPMSymbol);
}

- (NSRange)minimumRangeOfUnit:(NSCalendarUnit)unit {
    if (unit == NSCalendarUnitNanosecond) return NSMakeRange(0, 1000000000);
    if (!NSCalendarUnitIsCoreFoundation(unit)) return NSMakeRange(NSNotFound, NSNotFound);
    return NSCalendarRangeFromCFRange(CFCalendarGetMinimumRangeOfUnit(
        NSCALENDAR_CF(CFCalendarRef, self), (CFCalendarUnit)unit));
}

- (NSRange)maximumRangeOfUnit:(NSCalendarUnit)unit {
    if (unit == NSCalendarUnitNanosecond) return NSMakeRange(0, 1000000000);
    if (!NSCalendarUnitIsCoreFoundation(unit)) return NSMakeRange(NSNotFound, NSNotFound);
    return NSCalendarRangeFromCFRange(CFCalendarGetMaximumRangeOfUnit(
        NSCALENDAR_CF(CFCalendarRef, self), (CFCalendarUnit)unit));
}

- (NSDateComponents *)components:(NSCalendarUnit)unitFlags fromDate:(NSDate *)date {
    NSDateComponents *components = [[NSDateComponents alloc] init];
    CFAbsoluteTime absoluteTime = [date timeIntervalSinceReferenceDate];
    int era = 0, year = 0, quarter = 0, month = 0, weekOfMonth = 0, weekOfYear = 0, yearForWeekOfYear = 0;
    int day = 0, weekday = 0, weekdayOrdinal = 0, hour = 0, minute = 0, second = 0;
    if (!CFCalendarDecomposeAbsoluteTime(NSCALENDAR_CF(CFCalendarRef, self), absoluteTime,
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
    return NSCalendarComponentsBetween(NSCALENDAR_CF(CFCalendarRef, self), unitFlags,
                                       [startingDate timeIntervalSinceReferenceDate],
                                       [resultDate timeIntervalSinceReferenceDate],
                                       options);
}

- (NSDate *)dateFromComponents:(NSDateComponents *)components {
    return NSCalendarMakeDate(NSCALENDAR_CF(CFCalendarRef, self), components);
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
    if (!CFCalendarAddComponents(NSCALENDAR_CF(CFCalendarRef, self), &absoluteTime,
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
    if (!CFCalendarAddComponents(NSCALENDAR_CF(CFCalendarRef, self), &absoluteTime,
                                 (CFOptionFlags)options, descriptor, (int)value)) return nil;
    return [NSDate dateWithTimeIntervalSinceReferenceDate:absoluteTime];
}

- (NSRange)rangeOfUnit:(NSCalendarUnit)smaller inUnit:(NSCalendarUnit)larger forDate:(NSDate *)date {
    CFRange range = CFCalendarGetRangeOfUnit(NSCALENDAR_CF(CFCalendarRef, self),
                                             (CFCalendarUnit)smaller, (CFCalendarUnit)larger,
                                             [date timeIntervalSinceReferenceDate]);
    /* CoreFoundation reports an unsupported pairing as kCFNotFound; NSRange
     * spells the same thing NSNotFound. */
    return NSCalendarRangeFromCFRange(range);
}

- (NSUInteger)ordinalityOfUnit:(NSCalendarUnit)smaller inUnit:(NSCalendarUnit)larger forDate:(NSDate *)date {
    CFIndex ordinality = CFCalendarGetOrdinalityOfUnit(NSCALENDAR_CF(CFCalendarRef, self),
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
    if (!CFCalendarGetTimeRangeOfUnit(NSCALENDAR_CF(CFCalendarRef, self), (CFCalendarUnit)unit,
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
        if (!CFCalendarDecomposeAbsoluteTime(NSCALENDAR_CF(CFCalendarRef, self), absoluteTime,
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
    if (!CFCalendarComposeAbsoluteTime(NSCALENDAR_CF(CFCalendarRef, self), &absoluteTime,
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
    if (!CFCalendarComposeAbsoluteTime(NSCALENDAR_CF(CFCalendarRef, self), &absoluteTime,
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
    if (!NSCalendarDecompose(NSCALENDAR_CF(CFCalendarRef, self), time1, &decomposed1) ||
        !NSCalendarDecompose(NSCALENDAR_CF(CFCalendarRef, self), time2, &decomposed2)) {
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
    if (!NSCalendarDecompose(NSCALENDAR_CF(CFCalendarRef, self), absoluteTime, &decomposed)) return NO;
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
    CFCalendarRef calendar = NSCALENDAR_CF(CFCalendarRef, self);
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
    /* NSCalendar is a CF-backed cluster: an instance is always produced by the
     * CoreFoundation constructor, so -initWithCoder: answers a fresh object
     * rather than configuring the receiver. */
    if (![coder allowsKeyedCoding]) {
        return [NSCalendar calendarWithIdentifier:NSCalendarIdentifierGregorian];
    }
    NSString *identifier = [coder decodeObjectForKey:@"NSIdentifier"];
    if (identifier == nil) identifier = NSCalendarIdentifierGregorian;
    NSCalendar *calendar = [NSCalendar calendarWithIdentifier:identifier];
    if (calendar == nil) return nil;
    if ([coder containsValueForKey:@"NSFirstWeekday"]) {
        calendar.firstWeekday = (NSUInteger)[coder decodeIntegerForKey:@"NSFirstWeekday"];
    }
    if ([coder containsValueForKey:@"NSMinimumDaysInFirstWeek"]) {
        calendar.minimumDaysInFirstWeek = (NSUInteger)[coder decodeIntegerForKey:@"NSMinimumDaysInFirstWeek"];
    }
    if ([coder containsValueForKey:@"NSLocale"]) {
        calendar.locale = [coder decodeObjectForKey:@"NSLocale"];
    }
    return calendar;
}

@end

#if DEPLOYMENT_RUNTIME_OBJC
__attribute__((constructor))
static void __NSCFCalendarBridgeInit(void) {
    _CFRuntimeBridgeClasses(CFCalendarGetTypeID(), "NSCalendar");
}
#endif
