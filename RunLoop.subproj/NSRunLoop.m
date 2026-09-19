/*
 * Copyright (C) 2026, Samuel Zormeister.
 *
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */

#import <Foundation/NSRunLoop.h>
#import <Foundation/NSTimer.h>
#import <Foundation/NSDate.h>
#import <Foundation/NSArray.h>
#import <Foundation/NSException.h>

#include <CoreFoundation/CFRunLoop.h>
#include <CoreFoundation/ForFoundationOnly.h>

#include <pthread.h>

/* The subtree builds both with and without ARC depending on the target, so
 * every crossing of the CF boundary goes through one pair of macros instead of
 * a cast that only one of the two modes accepts. */
#if __has_feature(objc_arc)
#define NS_CF_BRIDGE(type, object) ((__bridge type)(object))
#define NS_RETAIN(object) (object)
#define NS_RELEASE(object) ((void)0)
#else
#define NS_CF_BRIDGE(type, object) ((type)(object))
#define NS_RETAIN(object) [(object) retain]
#define NS_RELEASE(object) [(object) release]
#endif

/* Foundation's own constants carry the same text as CoreFoundation's. Mode
 * lookup compares the strings, so a mode spelled here finds the sources and
 * timers scheduled under the CF spelling. */
NSRunLoopMode const NSDefaultRunLoopMode = @"kCFRunLoopDefaultMode";
NSRunLoopMode const NSRunLoopCommonModes = @"kCFRunLoopCommonModes";

/* One pending performSelector:withObject:afterDelay: request. The timer that
 * fires it is one-shot, so the request is live exactly as long as the timer is
 * valid. */
@interface _NSDelayedPerform : NSObject {
    id _target;
    SEL _selector;
    id _argument;
    NSTimer *_timer;
}

- (id)initWithTarget:(id)target selector:(SEL)selector argument:(id)argument;
- (void)setTimer:(NSTimer *)timer;
- (BOOL)matchesTarget:(id)target selector:(SEL)selector argument:(id)argument
           targetOnly:(BOOL)targetOnly;
- (BOOL)isPending;
- (void)cancel;
- (void)fire;

@end

@implementation _NSDelayedPerform

- (id)initWithTarget:(id)target selector:(SEL)selector argument:(id)argument {
    if ((self = [super init])) {
        _target = NS_RETAIN(target);
        _selector = selector;
        _argument = NS_RETAIN(argument);
    }
    return self;
}

- (void)dealloc {
    NS_RELEASE(_target);
    NS_RELEASE(_argument);
    NS_RELEASE(_timer);
#if !__has_feature(objc_arc)
    [super dealloc];
#endif
}

- (void)setTimer:(NSTimer *)timer {
    if (_timer == timer) {
        return;
    }
    NS_RELEASE(_timer);
    _timer = NS_RETAIN(timer);
}

- (BOOL)matchesTarget:(id)target selector:(SEL)selector argument:(id)argument
           targetOnly:(BOOL)targetOnly {
    if (_target != target) {
        return NO;
    }
    if (targetOnly) {
        return YES;
    }
    if (_selector != selector) {
        return NO;
    }
    /* The argument is compared by pointer, as Apple's documentation describes
     * for cancelPreviousPerformRequestsWithTarget:selector:object:. */
    return _argument == argument;
}

- (BOOL)isPending {
    return (_timer != nil) && [_timer isValid];
}

- (void)cancel {
    [_timer invalidate];
    [self setTimer:nil];
}

- (void)fire {
    [_target performSelector:_selector withObject:_argument];
    /* A non-repeating timer invalidates itself once it has fired, but firing
     * explicitly (-fire) must clean up the same way. */
    [_timer invalidate];
}

@end

@interface NSRunLoop ()

+ (NSRunLoop *)_runLoopForCFRunLoop:(CFRunLoopRef)rl;
- (id)_initWithCFRunLoop:(CFRunLoopRef)rl;
- (void)_rememberTimer:(NSTimer *)timer forMode:(NSRunLoopMode)mode;
- (void)_schedulePerform:(id)target selector:(SEL)selector argument:(id)argument
                   delay:(NSTimeInterval)delay modes:(NSArray *)modes;
- (void)_cancelPerformsWithTarget:(id)target selector:(SEL)selector
                         argument:(id)argument targetOnly:(BOOL)targetOnly;
- (void)_pruneDelayedPerforms;
- (CFRunLoopRunResult)_runMode:(NSRunLoopMode)mode beforeDate:(NSDate *)limitDate
       returnAfterSourceHandled:(BOOL)returnAfterSourceHandled;

@end

/* Every NSRunLoop the process has handed out, keyed by the CFRunLoopRef it
 * wraps. The keys are compared by pointer: a run loop is never copied and its
 * address identifies it.
 *
 * CFRunLoopGetCurrent() returns the same run loop for the main thread as
 * CFRunLoopGetMain(), so +currentRunLoop and +mainRunLoop share one object. */
static CFMutableDictionaryRef __NSRunLoopForCFRunLoop = NULL;
static pthread_mutex_t __NSRunLoopLock = PTHREAD_MUTEX_INITIALIZER;

@implementation NSRunLoop

+ (NSRunLoop *)currentRunLoop {
    return [self _runLoopForCFRunLoop:CFRunLoopGetCurrent()];
}

+ (NSRunLoop *)mainRunLoop {
    return [self _runLoopForCFRunLoop:CFRunLoopGetMain()];
}

+ (NSRunLoop *)_runLoopForCFRunLoop:(CFRunLoopRef)rl {
    if (rl == NULL) {
        return nil;
    }

    pthread_mutex_lock(&__NSRunLoopLock);
    if (__NSRunLoopForCFRunLoop == NULL) {
        __NSRunLoopForCFRunLoop = CFDictionaryCreateMutable(kCFAllocatorDefault, 0,
                                                            NULL,
                                                            &kCFTypeDictionaryValueCallBacks);
    }
    NSRunLoop *loop = (NSRunLoop *)CFDictionaryGetValue(__NSRunLoopForCFRunLoop, rl);
    if (loop == nil) {
        loop = [[self alloc] _initWithCFRunLoop:rl];
        CFDictionarySetValue(__NSRunLoopForCFRunLoop, rl, NS_CF_BRIDGE(const void *, loop));
        NS_RELEASE(loop);
    }
    pthread_mutex_unlock(&__NSRunLoopLock);

    return loop;
}

- (id)_initWithCFRunLoop:(CFRunLoopRef)rl {
    if ((self = [super init])) {
        _rl = (CFRunLoopRef)CFRetain(rl);
        _dperf = CFArrayCreateMutable(kCFAllocatorDefault, 0, &kCFTypeArrayCallBacks);
        _modes = CFDictionaryCreateMutable(kCFAllocatorDefault, 0,
                                          &kCFTypeDictionaryKeyCallBacks,
                                          &kCFTypeDictionaryValueCallBacks);
    }
    return self;
}

- (void)dealloc {
    if (_modes != NULL) {
        CFRelease(_modes);
    }
    if (_dperf != NULL) {
        CFRelease(_dperf);
    }
    if (_rl != NULL) {
        CFRelease(_rl);
    }
#if !__has_feature(objc_arc)
    [super dealloc];
#endif
}

- (CFRunLoopRef)getCFRunLoop {
    return _rl;
}

- (NSRunLoopMode)currentMode {
    CFRunLoopMode mode = CFRunLoopCopyCurrentMode(_rl);
    if (mode == NULL) {
        return nil;
    }
    return NS_CF_BRIDGE(NSRunLoopMode, CFAutorelease(mode));
}

- (void)addTimer:(NSTimer *)timer forMode:(NSRunLoopMode)mode {
    if (timer == nil || mode == nil) {
        [NSException raise:NSInvalidArgumentException
                    format:@"-[NSRunLoop addTimer:forMode:]: timer (%@) and mode (%@) "
                           @"must not be nil", timer, mode];
    }

    CFRunLoopAddTimer(_rl, NS_CF_BRIDGE(CFRunLoopTimerRef, timer),
                      NS_CF_BRIDGE(CFRunLoopMode, mode));
    [self _rememberTimer:timer forMode:mode];
}

- (void)_rememberTimer:(NSTimer *)timer forMode:(NSRunLoopMode)mode {
    CFMutableArrayRef timers = (CFMutableArrayRef)CFDictionaryGetValue(_modes,
                                                                       NS_CF_BRIDGE(const void *, mode));
    if (timers == NULL) {
        timers = CFArrayCreateMutable(kCFAllocatorDefault, 0, &kCFTypeArrayCallBacks);
        CFDictionarySetValue(_modes, NS_CF_BRIDGE(const void *, mode), timers);
        CFRelease(timers);
    }

    CFIndex count = CFArrayGetCount(timers);
    if (!CFArrayContainsValue(timers, CFRangeMake(0, count),
                              NS_CF_BRIDGE(const void *, timer))) {
        CFArrayAppendValue(timers, NS_CF_BRIDGE(const void *, timer));
    }
}

- (NSDate *)limitDateForMode:(NSRunLoopMode)mode {
    CFAbsoluteTime earliest = 0.0;
    BOOL found = NO;

    if (mode != nil) {
        CFArrayRef timers = (CFArrayRef)CFDictionaryGetValue(_modes,
                                                             NS_CF_BRIDGE(const void *, mode));
        if (timers != NULL) {
            CFIndex i, count = CFArrayGetCount(timers);
            for (i = 0; i < count; i++) {
                NSTimer *timer = (NSTimer *)CFArrayGetValueAtIndex(timers, i);
                if (![timer isValid]) {
                    continue;
                }
                CFAbsoluteTime fireDate = CFRunLoopTimerGetNextFireDate(
                                              NS_CF_BRIDGE(CFRunLoopTimerRef, timer));
                /* An invalidated timer reports a fire date of zero; those are
                 * skipped above, but a timer that has not been scheduled yet
                 * is treated the same way. */
                if (fireDate == 0.0) {
                    continue;
                }
                if (!found || fireDate < earliest) {
                    earliest = fireDate;
                    found = YES;
                }
            }
        }
    }

    if (!found) {
        return [NSDate distantFuture];
    }
    return [NSDate dateWithTimeIntervalSinceReferenceDate:earliest];
}

- (void)acceptInputForMode:(NSRunLoopMode)mode beforeDate:(NSDate *)limitDate {
    [self _runMode:mode beforeDate:limitDate returnAfterSourceHandled:YES];
}

- (BOOL)runMode:(NSRunLoopMode)mode beforeDate:(NSDate *)limitDate {
    if (mode == nil) {
        return NO;
    }
    CFRunLoopRunResult result = [self _runMode:mode beforeDate:limitDate
                      returnAfterSourceHandled:YES];
    /* -runMode:beforeDate: answers whether the receiver processed input, which
     * is exactly "the run loop neither ran dry nor timed out". */
    return (result != kCFRunLoopRunFinished) && (result != kCFRunLoopRunTimedOut);
}

- (CFRunLoopRunResult)_runMode:(NSRunLoopMode)mode beforeDate:(NSDate *)limitDate
                      returnAfterSourceHandled:(BOOL)returnAfterSourceHandled {
    CFTimeInterval seconds = 0.0;
    if (limitDate != nil) {
        seconds = [limitDate timeIntervalSinceReferenceDate] - CFAbsoluteTimeGetCurrent();
        if (seconds < 0.0) {
            seconds = 0.0;
        }
    }

    CFRunLoopRunResult result = CFRunLoopRunInMode(NS_CF_BRIDGE(CFRunLoopMode, mode),
                                                   seconds, returnAfterSourceHandled);
    if (result == kCFRunLoopRunFinished) {
        /* The run loop keeps the "finished" state until it is told that this
         * pass is over; without this a run loop whose sources were all removed
         * could never be run again. */
        _CFRunLoopFinished(_rl, NS_CF_BRIDGE(CFStringRef, mode));
    }
    return result;
}

- (void)run {
    /* -run processes sources until the run loop has none left to service. A
     * pass that handled a source means there may be more work, so the loop
     * goes around again. */
    CFRunLoopRunResult result;
    do {
        result = CFRunLoopRunInMode(kCFRunLoopDefaultMode, 1.0e10, false);
        if (result == kCFRunLoopRunFinished) {
            _CFRunLoopFinished(_rl, kCFRunLoopDefaultMode);
        }
    } while (result == kCFRunLoopRunHandledSource);
}

- (void)runUntilDate:(NSDate *)limitDate {
    if (limitDate == nil) {
        return;
    }
    CFAbsoluteTime limit = [limitDate timeIntervalSinceReferenceDate];
    while ([self runMode:NSDefaultRunLoopMode beforeDate:limitDate]
           && (limit > CFAbsoluteTimeGetCurrent())) {
        /* runMode:beforeDate: blocks until the limit date or until input was
         * processed; the loop ends when either the date passed or the run loop
         * has nothing left to give. */
    }
}

- (BOOL)runBeforeDate:(NSDate *)limitDate {
    if (limitDate == nil) {
        return NO;
    }
    CFRunLoopRunResult result = [self _runMode:NSDefaultRunLoopMode beforeDate:limitDate
                      returnAfterSourceHandled:YES];
    return (result != kCFRunLoopRunFinished) && (result != kCFRunLoopRunTimedOut);
}

- (void)_pruneDelayedPerforms {
    if (_dperf == NULL) {
        return;
    }
    CFIndex i = 0;
    while (i < CFArrayGetCount(_dperf)) {
        _NSDelayedPerform *perform = (_NSDelayedPerform *)CFArrayGetValueAtIndex(_dperf, i);
        if ([perform isPending]) {
            i++;
        } else {
            CFArrayRemoveValueAtIndex(_dperf, i);
        }
    }
}

- (void)_schedulePerform:(id)target selector:(SEL)selector argument:(id)argument
                   delay:(NSTimeInterval)delay modes:(NSArray *)modes {
    [self _pruneDelayedPerforms];

    if (delay < 0.0) {
        delay = 0.0;
    }

    _NSDelayedPerform *perform = [[_NSDelayedPerform alloc] initWithTarget:target
                                                                  selector:selector
                                                                  argument:argument];
    NSTimer *timer = [NSTimer timerWithTimeInterval:delay target:perform
                                           selector:@selector(fire) userInfo:nil repeats:NO];
    [perform setTimer:timer];

    if ((modes == nil) || ([modes count] == 0)) {
        [self addTimer:timer forMode:NSDefaultRunLoopMode];
    } else {
        NSUInteger i, count = [modes count];
        for (i = 0; i < count; i++) {
            [self addTimer:timer forMode:[modes objectAtIndex:i]];
        }
    }

    CFArrayAppendValue(_dperf, NS_CF_BRIDGE(const void *, perform));
    NS_RELEASE(perform);
}

- (void)_cancelPerformsWithTarget:(id)target selector:(SEL)selector
                         argument:(id)argument targetOnly:(BOOL)targetOnly {
    [self _pruneDelayedPerforms];

    CFIndex i = 0;
    while (i < CFArrayGetCount(_dperf)) {
        _NSDelayedPerform *perform = (_NSDelayedPerform *)CFArrayGetValueAtIndex(_dperf, i);
        if ([perform matchesTarget:target selector:selector argument:argument
                        targetOnly:targetOnly]) {
            [perform cancel];
            CFArrayRemoveValueAtIndex(_dperf, i);
        } else {
            i++;
        }
    }
}

@end

@implementation NSObject (NSDelayedPerforming)

- (void)performSelector:(SEL)aSelector withObject:(id)anArgument
             afterDelay:(NSTimeInterval)delay {
    [[NSRunLoop currentRunLoop] _schedulePerform:self selector:aSelector
                                        argument:anArgument delay:delay modes:nil];
}

- (void)performSelector:(SEL)aSelector withObject:(id)anArgument
             afterDelay:(NSTimeInterval)delay inModes:(NSArray *)modes {
    [[NSRunLoop currentRunLoop] _schedulePerform:self selector:aSelector
                                        argument:anArgument delay:delay modes:modes];
}

+ (void)cancelPreviousPerformRequestsWithTarget:(id)aTarget
                                       selector:(SEL)aSelector
                                         object:(id)anArgument {
    [[NSRunLoop currentRunLoop] _cancelPerformsWithTarget:aTarget selector:aSelector
                                                 argument:anArgument targetOnly:NO];
}

+ (void)cancelPreviousPerformRequestsWithTarget:(id)aTarget {
    [[NSRunLoop currentRunLoop] _cancelPerformsWithTarget:aTarget selector:NULL
                                                 argument:nil targetOnly:YES];
}

@end
