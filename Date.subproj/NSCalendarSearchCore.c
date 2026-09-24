/* NSCalendarSearchCore.c
 *
 * Pure-C search core for -nextDateAfterDate:matchingComponents:options:, a
 * faithful transposition of the port's own search algorithm.  Operates on a
 * raw CFCalendarRef over CFAbsoluteTime with the requested fields carried in
 * a plain NSCalendarSearchRequest struct, so the behavioral-gate harness can
 * drive this core through a raw CoreFoundation calendar (no ObjC dispatch).
 *
 * Descriptor literals and composition defaulting are taken byte-for-byte from
 * the port's NSCalendar.m (NSCalendarDecompose line 98, NSCalendarMakeDate
 * line 335) so the probe output stays byte-identical to the frozen golden.
 *
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0.
 */

#include "NSCalendarSupport.h"
#include <math.h>
#include <stdio.h>
#include <string.h>

/* --- unit ordering, mirroring NSCalendarUnitRank in NSCalendar.m --- */
static int NSCalendarSearchUnitRank(NSCalendarUnit unit) {
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
        default: return 11;
    }
}

/* --- step unit for a rank, mirroring NSCalendarUnitStepForRank --- */
static NSCalendarUnit NSCalendarSearchUnitStepForRank(int rank) {
    switch (rank) {
        case 0: return NSCalendarUnitYear;
        case 1: return NSCalendarUnitYear;
        case 2: return NSCalendarUnitYear;
        case 3: return NSCalendarUnitYear;
        case 4: return NSCalendarUnitYear;
        case 5: return NSCalendarUnitYear;
        case 6: return NSCalendarUnitMonth;
        case 7: return NSCalendarUnitDay;
        case 8: return NSCalendarUnitDay;
        case 9: return NSCalendarUnitHour;
        case 10: return NSCalendarUnitSecond;
        default: return NSCalendarUnitSecond;
    }
}

/* --- base value for an unspecified fine unit, mirroring NSCalendarUnitBaseValue --- */
static NSInteger NSCalendarSearchUnitBaseValue(NSCalendarUnit unit) {
    switch (unit) {
        case NSCalendarUnitQuarter:
        case NSCalendarUnitMonth:
        case NSCalendarUnitDay:
        case NSCalendarUnitWeekOfMonth:
        case NSCalendarUnitWeekOfYear:
        case NSCalendarUnitWeekday:
        case NSCalendarUnitEra: return 1;
        default: return 0;
    }
}

/* --- decomposition, mirroring NSCalendarDecompose (NSCalendar.m:98) --- */
static const char NSCalendarSearchDecomposeDescriptor[] = "GyQMWwYdDEFHms";

/* Variadic-proof decomposed record: field order matters and must match the
 * descriptor, exactly as NSCalendarDecomposed does in the port.  The record is
 * zeroed before each CFCalendarDecomposeAbsoluteTime call because that API
 * writes 4-byte ints into these 8-byte NSInteger slots; the port relies on the
 * same layout (its NSCalendarDecomposed uses int fields and is only compared
 * field-wise, whereas this record must also carry the NSDateComponentUndefined
 * sentinel for composition, so the wider slots are kept). */
typedef struct {
    NSInteger era, year, quarter, month;
    NSInteger weekOfMonth, weekOfYear, yearForWeekOfYear, day;
    NSInteger dayOfYear, weekday, weekdayOrdinal, hour;
    NSInteger minute, second;
} NSCalendarSearchDecomposed;

static Boolean NSCalendarSearchDecompose(CFCalendarRef calendar,
                                         CFAbsoluteTime absoluteTime,
                                         NSCalendarSearchDecomposed *components) {
    memset(components, 0, sizeof(*components));
    return CFCalendarDecomposeAbsoluteTime(calendar, absoluteTime,
                                           NSCalendarSearchDecomposeDescriptor,
                                           &components->era, &components->year,
                                           &components->quarter, &components->month,
                                           &components->weekOfMonth, &components->weekOfYear,
                                           &components->yearForWeekOfYear, &components->day,
                                           &components->dayOfYear, &components->weekday,
                                           &components->weekdayOrdinal, &components->hour,
                                           &components->minute, &components->second);
}

/* --- nanosecond helper, mirroring NSCalendarNanosecond --- */
static NSInteger NSCalendarSearchNanosecond(CFAbsoluteTime absoluteTime) {
    return (NSInteger)((absoluteTime - floor(absoluteTime)) * 1000000000.0);
}

/* --- apply a requested nanosecond shift, mirroring NSCalendarDateByAddingNanoseconds --- */
static CFAbsoluteTime NSCalendarSearchAddNanoseconds(CFAbsoluteTime time, NSInteger nanoseconds) {
    if (nanoseconds == NSDateComponentUndefined || nanoseconds == 0) return time;
    return time + (CFAbsoluteTime)nanoseconds / 1000000000.0;
}

/* --- composition, mirroring NSCalendarMakeDate (NSCalendar.m:335-366) ---
 * The week path ("GwYEHms") is taken exactly when any of yearForWeekOfYear,
 * weekOfYear or weekday is set; era/week/year default to 1, h/m/s to 0. */
static Boolean NSCalendarSearchMakeDate(CFCalendarRef calendar,
                                        const NSCalendarSearchDecomposed *d,
                                        NSInteger nanosecondRequested,
                                        CFAbsoluteTime *outTime) {
    CFAbsoluteTime absoluteTime = 0;
    if (d->yearForWeekOfYear != NSDateComponentUndefined ||
        d->weekOfYear != NSDateComponentUndefined ||
        d->weekday != NSDateComponentUndefined) {
        int era   = d->era != NSDateComponentUndefined ? (int)d->era : 1;
        int year  = d->yearForWeekOfYear != NSDateComponentUndefined ? (int)d->yearForWeekOfYear
                                                                     : (int)d->year;
        int week  = d->weekOfYear != NSDateComponentUndefined ? (int)d->weekOfYear : 1;
        int weekday = d->weekday != NSDateComponentUndefined ? (int)d->weekday : 1;
        int hour  = d->hour != NSDateComponentUndefined ? (int)d->hour : 0;
        int minute = d->minute != NSDateComponentUndefined ? (int)d->minute : 0;
        int second = d->second != NSDateComponentUndefined ? (int)d->second : 0;
        if (!CFCalendarComposeAbsoluteTime(calendar, &absoluteTime, "GwYEHms",
                                           era, week, year, weekday,
                                           hour, minute, second)) return false;
    } else {
        int era   = d->era != NSDateComponentUndefined ? (int)d->era : 1;
        int year  = d->year != NSDateComponentUndefined ? (int)d->year : 1;
        int month = d->month != NSDateComponentUndefined ? (int)d->month : 1;
        int day   = d->day != NSDateComponentUndefined ? (int)d->day : 1;
        int hour  = d->hour != NSDateComponentUndefined ? (int)d->hour : 0;
        int minute = d->minute != NSDateComponentUndefined ? (int)d->minute : 0;
        int second = d->second != NSDateComponentUndefined ? (int)d->second : 0;
        if (!CFCalendarComposeAbsoluteTime(calendar, &absoluteTime, "GyMdHms",
                                           era, year, month, day,
                                           hour, minute, second)) return false;
    }
    *outTime = NSCalendarSearchAddNanoseconds(absoluteTime, nanosecondRequested);
    return true;
}

/* --- field matching, mirroring -date:matchesComponents: --- */
static Boolean NSCalendarSearchFieldMatches(NSInteger requested, NSInteger candidate) {
    return requested == NSDateComponentUndefined || requested == candidate;
}

static Boolean NSCalendarSearchMatches(const NSCalendarSearchRequest *requested,
                                       const NSCalendarSearchDecomposed *candidate) {
    return NSCalendarSearchFieldMatches(requested->era, candidate->era) &&
           NSCalendarSearchFieldMatches(requested->year, candidate->year) &&
           NSCalendarSearchFieldMatches(requested->quarter, candidate->quarter) &&
           NSCalendarSearchFieldMatches(requested->month, candidate->month) &&
           NSCalendarSearchFieldMatches(requested->weekOfMonth, candidate->weekOfMonth) &&
           NSCalendarSearchFieldMatches(requested->weekOfYear, candidate->weekOfYear) &&
           NSCalendarSearchFieldMatches(requested->yearForWeekOfYear, candidate->yearForWeekOfYear) &&
           NSCalendarSearchFieldMatches(requested->day, candidate->day) &&
           NSCalendarSearchFieldMatches(requested->weekday, candidate->weekday) &&
           NSCalendarSearchFieldMatches(requested->weekdayOrdinal, candidate->weekdayOrdinal) &&
NSCalendarSearchFieldMatches(requested->hour, candidate->hour) &&
            NSCalendarSearchFieldMatches(requested->minute, candidate->minute) &&
            NSCalendarSearchFieldMatches(requested->second, candidate->second);
}

static Boolean NSCalendarSearchRequestIsEmpty(const NSCalendarSearchRequest *r) {
    return r->era == NSDateComponentUndefined && r->year == NSDateComponentUndefined &&
           r->quarter == NSDateComponentUndefined && r->month == NSDateComponentUndefined &&
           r->weekOfMonth == NSDateComponentUndefined && r->weekOfYear == NSDateComponentUndefined &&
           r->yearForWeekOfYear == NSDateComponentUndefined && r->day == NSDateComponentUndefined &&
           r->weekday == NSDateComponentUndefined && r->weekdayOrdinal == NSDateComponentUndefined &&
           r->hour == NSDateComponentUndefined && r->minute == NSDateComponentUndefined &&
           r->second == NSDateComponentUndefined && r->nanosecond == NSDateComponentUndefined;
}

/* --- the search, transposed from -nextDateAfterDate:... --- */
Boolean NSCalendarSearchNextDateAfterDate(CFCalendarRef calendar,
                                          CFAbsoluteTime inputTime,
                                          NSCalendarSearchRequest requested,
                                          NSCalendarOptions options,
                                          CFAbsoluteTime *outTime) {
    if (calendar == NULL || NSCalendarSearchRequestIsEmpty(&requested)) return false;

    NSCalendarUnit highest = 0;
    Boolean any = false;
    Boolean usesWeekPath = false;
#define NSCALENDAR_HIGHEST(cond, unit)                                          \
    if (cond) {                                                                 \
        if (!any || NSCalendarSearchUnitRank(unit) < NSCalendarSearchUnitRank(highest)) { \
            highest = unit;                                                     \
        }                                                                       \
        any = true;                                                             \
        if (unit == NSCalendarUnitWeekday || unit == NSCalendarUnitWeekOfYear || \
            unit == NSCalendarUnitYearForWeekOfYear) {                          \
            usesWeekPath = true;                                                \
        }                                                                       \
    }
    NSCALENDAR_HIGHEST(requested.era != NSDateComponentUndefined, NSCalendarUnitEra)
    NSCALENDAR_HIGHEST(requested.year != NSDateComponentUndefined, NSCalendarUnitYear)
    NSCALENDAR_HIGHEST(requested.quarter != NSDateComponentUndefined, NSCalendarUnitQuarter)
    NSCALENDAR_HIGHEST(requested.month != NSDateComponentUndefined, NSCalendarUnitMonth)
    NSCALENDAR_HIGHEST(requested.yearForWeekOfYear != NSDateComponentUndefined, NSCalendarUnitYearForWeekOfYear)
    NSCALENDAR_HIGHEST(requested.weekOfYear != NSDateComponentUndefined, NSCalendarUnitWeekOfYear)
    NSCALENDAR_HIGHEST(requested.weekOfMonth != NSDateComponentUndefined, NSCalendarUnitWeekOfMonth)
    NSCALENDAR_HIGHEST(requested.day != NSDateComponentUndefined, NSCalendarUnitDay)
    NSCALENDAR_HIGHEST(requested.weekday != NSDateComponentUndefined, NSCalendarUnitWeekday)
    NSCALENDAR_HIGHEST(requested.hour != NSDateComponentUndefined, NSCalendarUnitHour)
    NSCALENDAR_HIGHEST(requested.minute != NSDateComponentUndefined, NSCalendarUnitMinute)
    NSCALENDAR_HIGHEST(requested.second != NSDateComponentUndefined, NSCalendarUnitSecond)
#undef NSCALENDAR_HIGHEST
    if (!any) return false;

    int highestRank = NSCalendarSearchUnitRank(highest);
    NSCalendarUnit stepUnit = NSCalendarSearchUnitStepForRank(highestRank);

    CFAbsoluteTime probe = inputTime;
    CFAbsoluteTime firstCandidateOfYearTime = 0;
    Boolean haveFirstCandidateOfYear = false;
    NSInteger lastProbeYear = NSDateComponentUndefined;
    const int strictLimit = 10000;

    for (int iteration = 0; iteration < strictLimit; iteration++) {
        NSCalendarSearchDecomposed d;
        if (!NSCalendarSearchDecompose(calendar, probe, &d)) return false;

        NSCalendarSearchDecomposed fill = d;
        if (requested.era != NSDateComponentUndefined) fill.era = requested.era;
        if (requested.year != NSDateComponentUndefined) fill.year = requested.year;
        if (requested.quarter != NSDateComponentUndefined) fill.quarter = requested.quarter;
        if (requested.month != NSDateComponentUndefined) {
            fill.month = requested.month;
        } else if (requested.quarter != NSDateComponentUndefined) {
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

#define NSCALENDAR_COLLAPSE(cond, unit, field)                                    \
        if (cond == NSDateComponentUndefined &&                                   \
            NSCalendarSearchUnitRank(unit) > highestRank) {                       \
            fill.field = NSCalendarSearchUnitBaseValue(unit);                     \
        }
        NSCALENDAR_COLLAPSE(requested.year, NSCalendarUnitYear, year)
        NSCALENDAR_COLLAPSE(requested.quarter, NSCalendarUnitQuarter, quarter)
        if (requested.month == NSDateComponentUndefined &&
            requested.quarter == NSDateComponentUndefined &&
            NSCalendarSearchUnitRank(NSCalendarUnitMonth) > highestRank) {
            fill.month = NSCalendarSearchUnitBaseValue(NSCalendarUnitMonth);
        }
        NSCALENDAR_COLLAPSE(requested.weekOfMonth, NSCalendarUnitWeekOfMonth, weekOfMonth)
        NSCALENDAR_COLLAPSE(requested.weekOfYear, NSCalendarUnitWeekOfYear, weekOfYear)
        NSCALENDAR_COLLAPSE(requested.yearForWeekOfYear, NSCalendarUnitYearForWeekOfYear, yearForWeekOfYear)
        NSCALENDAR_COLLAPSE(requested.day, NSCalendarUnitDay, day)
        NSCALENDAR_COLLAPSE(requested.weekday, NSCalendarUnitWeekday, weekday)
        NSCALENDAR_COLLAPSE(requested.hour, NSCalendarUnitHour, hour)
        NSCALENDAR_COLLAPSE(requested.minute, NSCalendarUnitMinute, minute)
        NSCALENDAR_COLLAPSE(requested.second, NSCalendarUnitSecond, second)
#undef NSCALENDAR_COLLAPSE

        if (!usesWeekPath) {
            fill.weekOfYear = NSDateComponentUndefined;
            fill.yearForWeekOfYear = NSDateComponentUndefined;
            fill.weekday = NSDateComponentUndefined;
        }

        CFAbsoluteTime candidate = 0;
        if (!NSCalendarSearchMakeDate(calendar, &fill, requested.nanosecond, &candidate)) return false;

        NSCalendarSearchDecomposed py;
        if (!NSCalendarSearchDecompose(calendar, probe, &py)) return false;
        if (candidate > inputTime) {
            NSCalendarSearchDecomposed c;
            if (!NSCalendarSearchDecompose(calendar, candidate, &c)) return false;
            if (NSCalendarSearchMatches(&requested, &c)) {
                *outTime = candidate;
                return true;
            }
            if (!(options & NSCalendarMatchStrictly)) {
                *outTime = candidate;
                return true;
            }
        }

        /* Freeze detection: a repeated candidate only dead-ends once the probe
         * has crossed into a new calendar year. */
        if (py.year != lastProbeYear) {
            if (haveFirstCandidateOfYear && candidate == firstCandidateOfYearTime) return false;
            firstCandidateOfYearTime = candidate;
            haveFirstCandidateOfYear = true;
            lastProbeYear = py.year;
        }

        CFAbsoluteTime next = probe;
        Boolean ok;
        switch (stepUnit) {
            case NSCalendarUnitYear:   ok = CFCalendarAddComponents(calendar, &next, 0, "y", 1); break;
            case NSCalendarUnitMonth:  ok = CFCalendarAddComponents(calendar, &next, 0, "M", 1); break;
            case NSCalendarUnitDay:    ok = CFCalendarAddComponents(calendar, &next, 0, "d", 1); break;
            case NSCalendarUnitHour:   ok = CFCalendarAddComponents(calendar, &next, 0, "H", 1); break;
            case NSCalendarUnitMinute: ok = CFCalendarAddComponents(calendar, &next, 0, "m", 1); break;
            case NSCalendarUnitSecond: ok = CFCalendarAddComponents(calendar, &next, 0, "s", 1); break;
            default:                   ok = false; break;
        }
        next = (ok ? next : probe + 1.0);
        if (next <= probe) return false;
        probe = next;
    }
    return false;
}
