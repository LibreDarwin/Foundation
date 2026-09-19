/*
 * Copyright (C) 2026, Samuel Zormeister.
 *
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */

#if !defined(__FOUNDATION_NSTIMER__)
#define __FOUNDATION_NSTIMER__ 1

#import <Foundation/NSObjCRuntime.h>
#import <Foundation/NSObject.h>
#import <Foundation/NSDate.h>

/* An NSTimer is a CFRunLoopTimer: the instance handed back by the constructors
 * is a CoreFoundation timer whose class has been bridged to __NSCFTimer, so it
 * can be scheduled with either the NSRunLoop or the CFRunLoop API.
 *
 * The constructors that take an NSInvocation, and the block-based ones, are
 * not declared here: this port has no NSInvocation, and the Objective-C side of
 * it does not build against the Blocks runtime. */
@interface NSTimer : NSObject

+ (NSTimer *)timerWithTimeInterval:(NSTimeInterval)ti target:(id)aTarget
                          selector:(SEL)aSelector userInfo:(id)userInfo
                           repeats:(BOOL)yesOrNo;
+ (NSTimer *)scheduledTimerWithTimeInterval:(NSTimeInterval)ti target:(id)aTarget
                                   selector:(SEL)aSelector userInfo:(id)userInfo
                                    repeats:(BOOL)yesOrNo;

- (void)fire;

- (NSDate *)fireDate;
- (void)setFireDate:(NSDate *)date;

- (NSTimeInterval)timeInterval;

- (NSTimeInterval)tolerance;
- (void)setTolerance:(NSTimeInterval)tolerance;

- (void)invalidate;
- (BOOL)isValid;

- (id)userInfo;

@end

#endif /* ! __FOUNDATION_NSTIMER__ */
