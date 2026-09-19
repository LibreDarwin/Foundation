/*
 * Copyright (C) 2026, Samuel Zormeister.
 *
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */

#if !defined(__FOUNDATION_NSRUNLOOP__)
#define __FOUNDATION_NSRUNLOOP__ 1

#import <Foundation/NSObjCRuntime.h>
#import <Foundation/NSObject.h>
#import <Foundation/NSDate.h>
#import <Foundation/NSArray.h>
#include <CoreFoundation/CFRunLoop.h>

@class NSTimer;

typedef NSString *NSRunLoopMode;

FOUNDATION_EXPORT NSRunLoopMode const NSDefaultRunLoopMode;
FOUNDATION_EXPORT NSRunLoopMode const NSRunLoopCommonModes;

/* NSRunLoop wraps a CFRunLoopRef rather than bridging to it. A CFRunLoop is a
 * CF type with storage of its own, so making it carry Objective-C ivars would
 * overlay the run loop's own fields. One NSRunLoop is created for each
 * CFRunLoopRef the first time it is asked for, and it holds the CF object for
 * as long as it lives.
 *
 * _modes records, per mode, the timers that have been added to the receiver.
 * CoreFoundation has no "when is the next timer in this mode" query, so
 * -limitDateForMode: answers from that bookkeeping.
 *
 * _dperf holds one _NSDelayedPerform for each pending
 * performSelector:withObject:afterDelay: request, which is what lets
 * cancelPreviousPerformRequestsWithTarget:... find and invalidate them.
 */
@interface NSRunLoop : NSObject {
    CFRunLoopRef _rl;
    CFMutableArrayRef _dperf;
    CFMutableDictionaryRef _modes;
    void *_reserved[4];
}

+ (NSRunLoop *)currentRunLoop;
+ (NSRunLoop *)mainRunLoop;

- (CFRunLoopRef)getCFRunLoop;
- (NSRunLoopMode)currentMode;

- (void)addTimer:(NSTimer *)timer forMode:(NSRunLoopMode)mode;
- (NSDate *)limitDateForMode:(NSRunLoopMode)mode;
- (void)acceptInputForMode:(NSRunLoopMode)mode beforeDate:(NSDate *)limitDate;

- (BOOL)runMode:(NSRunLoopMode)mode beforeDate:(NSDate *)limitDate;
- (void)run;
- (void)runUntilDate:(NSDate *)limitDate;
- (BOOL)runBeforeDate:(NSDate *)limitDate;

@end

/* Delayed performs belong to the run loop that was current when they were
 * scheduled, so they are declared next to it rather than on their own. */
@interface NSObject (NSDelayedPerforming)

- (void)performSelector:(SEL)aSelector withObject:(id)anArgument
             afterDelay:(NSTimeInterval)delay;
- (void)performSelector:(SEL)aSelector withObject:(id)anArgument
             afterDelay:(NSTimeInterval)delay inModes:(NSArray *)modes;

+ (void)cancelPreviousPerformRequestsWithTarget:(id)aTarget
                                       selector:(SEL)aSelector
                                         object:(id)anArgument;
+ (void)cancelPreviousPerformRequestsWithTarget:(id)aTarget;

@end

#endif /* ! __FOUNDATION_NSRUNLOOP__ */
