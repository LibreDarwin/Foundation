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

/* Interpret a date components object against a calendar without going through
 * the object system. An NSDateComponents belongs to a plain Objective-C class,
 * but the calendar it points at is a CFCalendar-backed cluster instance whose
 * isa may be the CoreFoundation-bridged class, so a message send to it is not
 * guaranteed to reach our implementation. NSDateComponents and NSCalendar use
 * these entry points instead. */
NSDate *NSCalendarDateFromComponents(NSCalendar *calendar, NSDateComponents *components);
BOOL NSCalendarDateComponentsAreValid(NSCalendar *calendar, NSDateComponents *components);

#endif /* NSCalendarSupport_h */
