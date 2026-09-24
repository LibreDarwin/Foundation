/*
 * Copyright (C) 2026, Samuel Zormeister.
 *
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */

#ifndef NSCalendarSupport_h
#define NSCalendarSupport_h

#import <Foundation/NSDate.h>
#import <Foundation/NSCalendar.h>
#import <Foundation/NSDateComponents.h>
#include <CoreFoundation/CFCalendar.h>

/* Interpret a date components object against a calendar without going through
 * the object system.  An NSDateComponents belongs to a plain Objective-C
 * class, and NSCalendar owns the CFCalendar it was created from rather than
 * being toll-free with it, so these entry points unwrap the backing
 * CFCalendar directly.  NSDateComponents and NSCalendar use these entry
 * points instead of messaging the calendar. */
NSDate *NSCalendarDateFromComponents(NSCalendar *calendar, NSDateComponents *components);
BOOL NSCalendarDateComponentsAreValid(NSCalendar *calendar, NSDateComponents *components);

/* Return the CFCalendar an NSCalendar wraps.  The port's NSCalendar owns a
 * backing CFCalendar rather than being toll-free with CFCalendarRef, so a
 * harness can unwrap it and hand the calendar to the pure-C core. */
CFCalendarRef NSCalendarGetBackingCalendar(NSCalendar *calendar);

/* --- Pure-C search core, transposed from -nextDateAfterDate:... ---
 * Operates on a raw CFCalendarRef (the port's NSCalendar is toll-free
 * bridged with CoreFoundation's CFCalendar, so a harness can hand the core
 * the unmarshalled calendar directly) over CFAbsoluteTime.  Every field the
 * ObjC search accepts is carried in the request; unspecified fields take
 * NSDateComponentUndefined, exactly as NSDateComponents defaults them. */
typedef struct {
    NSInteger era, year, quarter, month;
    NSInteger weekOfMonth, weekOfYear, yearForWeekOfYear, day;
    NSInteger weekday, weekdayOrdinal, hour, minute, second, nanosecond;
} NSCalendarSearchRequest;

Boolean NSCalendarSearchNextDateAfterDate(CFCalendarRef calendar,
                                          CFAbsoluteTime inputTime,
                                          NSCalendarSearchRequest requested,
                                          NSCalendarOptions options,
                                          CFAbsoluteTime *outTime);

#endif /* NSCalendarSupport_h */
