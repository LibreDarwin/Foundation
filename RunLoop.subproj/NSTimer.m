/*
 * Copyright (C) 2026, Samuel Zormeister.
 *
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */

#import <Foundation/NSTimer.h>
#import <Foundation/NSRunLoop.h>
#import <Foundation/NSDate.h>
#import <Foundation/NSException.h>

#include <CoreFoundation/CFRunLoop.h>
#include <CoreFoundation/CFDate.h>

#include <stdlib.h>
#include <string.h>

/* See NSRunLoop.m: the subtree builds with and without ARC, so the crossings
 * of the CF boundary are hidden behind one pair of macros. */
#if __has_feature(objc_arc)
#define NS_CF_BRIDGE(type, object) ((__bridge type)(object))
/* The record below is allocated with calloc, so ARC has no place to keep an
 * ownership qualifier for its fields; they are managed by hand with
 * CFRetain/CFRelease. */
#define NS_UNRETAINED __unsafe_unretained
#else
#define NS_CF_BRIDGE(type, object) ((type)(object))
#define NS_UNRETAINED
#endif

/* _CFRuntimeBridgeClasses() is declared in NSObjCRuntime.h for the whole tree;
 * the calls that use it are gated on DEPLOYMENT_RUNTIME_OBJC, the CoreFoundation
 * deployment that has a class table of its own. */

/* What the timer was asked for. The CF timer keeps its own fire date, interval,
 * validity and tolerance; this record carries the pieces CF has no accessor for
 * - the target, selector and user info - and the fire date, which the
 * Objective-C dispatch path has to answer without calling back into the timer it
 * is being asked about.
 *
 * CoreFoundation keeps two references to this record: one from the timer's
 * context, which it gives up when the timer is invalidated, and one it takes
 * around each callout and gives up afterwards. They overlap, so the record
 * carries a count and is freed when the last one goes.
 *
 * target and userInfo are held with CFRetain/CFRelease rather than by ARC, so
 * that the same code is correct whether or not the translation unit is
 * compiled with ARC. */
typedef struct {
    NS_UNRETAINED id target;
    SEL selector;
    NS_UNRETAINED id userInfo;
    CFAbsoluteTime nextFireDate;
    CFIndex refCount;
    BOOL repeats;
} _NSTimerInfo;

static const void *__NSTimerInfoRetain(const void *info) {
    _NSTimerInfo *timerInfo = (_NSTimerInfo *)info;
    if (timerInfo != NULL) {
        timerInfo->refCount++;
    }
    return info;
}

static void __NSTimerInfoRelease(const void *info) {
    _NSTimerInfo *timerInfo = (_NSTimerInfo *)info;
    if (timerInfo == NULL) {
        return;
    }
    if (--timerInfo->refCount > 0) {
        return;
    }
    if (timerInfo->target != nil) {
        CFRelease(NS_CF_BRIDGE(CFTypeRef, timerInfo->target));
    }
    if (timerInfo->userInfo != nil) {
        CFRelease(NS_CF_BRIDGE(CFTypeRef, timerInfo->userInfo));
    }
    free(timerInfo);
}

static _NSTimerInfo *__NSTimerInfoFor(CFRunLoopTimerRef timer) {
    CFRunLoopTimerContext context;
    memset(&context, 0, sizeof(context));
    CFRunLoopTimerGetContext(timer, &context);
    return (_NSTimerInfo *)context.info;
}

/* The callout CF invokes for the timer. The selector is sent the timer, which
 * is what a target declared as taking an NSTimer expects to receive. */
static void __NSTimerCallout(CFRunLoopTimerRef timer, void *info) {
    _NSTimerInfo *timerInfo = (_NSTimerInfo *)info;
    if (timerInfo == NULL) {
        return;
    }

    /* For a repeating timer CF has already moved the fire date on to the next
     * occurrence by the time the callout runs. */
    timerInfo->nextFireDate = CFRunLoopTimerGetNextFireDate(timer);

    id target = timerInfo->target;
    SEL selector = timerInfo->selector;
    BOOL repeats = timerInfo->repeats;
    if ((target != nil) && (selector != NULL)) {
        [target performSelector:selector withObject:NS_CF_BRIDGE(id, timer)];
    }

    /* A one-shot timer is consumed by firing. CoreFoundation only invalidates a
     * timer on its own when its period is zero, and this one carries the
     * interval it reports, so consuming it here is what makes it one-shot. The
     * record survives the call: CoreFoundation holds a reference of its own
     * across the callout and it is the release of that reference which frees
     * the record. */
    if (!repeats) {
        CFRunLoopTimerInvalidate(timer);
    }
}

static NSTimer *__NSTimerCreate(NSTimeInterval interval, id target, SEL selector,
                                id userInfo, BOOL repeats) {
    _NSTimerInfo *timerInfo = (_NSTimerInfo *)calloc(1, sizeof(_NSTimerInfo));
    if (timerInfo == NULL) {
        [NSException raise:NSMallocException format:@"-[NSTimer timerWithTimeInterval:...]: "
                                                      @"could not allocate the timer record"];
    }

    /* userInfo is optional; target and selector are not, which the constructors
     * above enforce. CFRetain() refuses a null argument, so the optional one is
     * held only when it is there. */
    if (target != nil) {
        timerInfo->target = NS_CF_BRIDGE(id, CFRetain(NS_CF_BRIDGE(CFTypeRef, target)));
    }
    timerInfo->selector = selector;
    if (userInfo != nil) {
        timerInfo->userInfo = NS_CF_BRIDGE(id, CFRetain(NS_CF_BRIDGE(CFTypeRef, userInfo)));
    }
    timerInfo->repeats = repeats;
    timerInfo->refCount = 1;
    timerInfo->nextFireDate = CFAbsoluteTimeGetCurrent() + interval;

    CFRunLoopTimerContext context;
    memset(&context, 0, sizeof(context));
    context.info = timerInfo;
    context.retain = __NSTimerInfoRetain;
    context.release = __NSTimerInfoRelease;

    /* The interval goes through as given - it is what -timeInterval reports, and
     * what CoreFoundation uses as the period between firings. A timer that does
     * not repeat is made one-shot by the callout invalidating it, not by a
     * period of zero. */
    CFRunLoopTimerRef timer = CFRunLoopTimerCreate(kCFAllocatorDefault,
                                                   timerInfo->nextFireDate,
                                                   (CFTimeInterval)interval,
                                                   0, 0, __NSTimerCallout, &context);
    /* The constructors hand back a timer that is not owned by the caller, like
     * every other convenience constructor in the port. */
    return NS_CF_BRIDGE(NSTimer *, CFAutorelease(timer));
}

/* The class CoreFoundation hands back: the timer's storage is CF's, and the
 * class only supplies the Objective-C surface. */
@interface __NSCFTimer : NSTimer
@end

/* CoreFoundation owns a bridged timer's storage, so its -dealloc below
 * deliberately does not chain to NSObject's. */
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wobjc-missing-super-calls"

@implementation __NSCFTimer

- (CFTypeID)_cfTypeID {
    return CFRunLoopTimerGetTypeID();
}

- (void)fire {
    _NSTimerInfo *timerInfo = __NSTimerInfoFor(NS_CF_BRIDGE(CFRunLoopTimerRef, self));
    if (timerInfo == NULL) {
        return;
    }
    /* The callout sends the message and, for a timer that does not repeat,
     * consumes the timer. An invalidated timer has no record and returns above,
     * so firing one twice is a no-op and not a second free. */
    __NSTimerCallout(NS_CF_BRIDGE(CFRunLoopTimerRef, self), timerInfo);
}

- (NSDate *)fireDate {
    CFAbsoluteTime fireDate = CFRunLoopTimerGetNextFireDate(NS_CF_BRIDGE(CFRunLoopTimerRef, self));
    if (fireDate == 0.0) {
        /* An invalidated timer has no fire date; the distant past is what the
         * CF side reports for one as well. */
        return [NSDate distantPast];
    }
    return [NSDate dateWithTimeIntervalSinceReferenceDate:fireDate];
}

- (void)setFireDate:(NSDate *)date {
    if (![self isValid]) {
        [NSException raise:NSInvalidArgumentException
                    format:@"-[NSTimer setFireDate:]: timer %@ is not valid", self];
    }

    _NSTimerInfo *timerInfo = __NSTimerInfoFor(NS_CF_BRIDGE(CFRunLoopTimerRef, self));
    CFAbsoluteTime fireDate = (date != nil) ? [date timeIntervalSinceReferenceDate] : 0.0;
    if (timerInfo != NULL) {
        timerInfo->nextFireDate = fireDate;
    }
    CFRunLoopTimerSetNextFireDate(NS_CF_BRIDGE(CFRunLoopTimerRef, self), fireDate);
}

- (NSTimeInterval)timeInterval {
    return (NSTimeInterval)CFRunLoopTimerGetInterval(NS_CF_BRIDGE(CFRunLoopTimerRef, self));
}

- (NSTimeInterval)tolerance {
    return (NSTimeInterval)CFRunLoopTimerGetTolerance(NS_CF_BRIDGE(CFRunLoopTimerRef, self));
}

- (void)setTolerance:(NSTimeInterval)tolerance {
    /* CoreFoundation clamps the value it is given, so this does not have to. */
    CFRunLoopTimerSetTolerance(NS_CF_BRIDGE(CFRunLoopTimerRef, self), (CFTimeInterval)tolerance);
}

- (void)invalidate {
    CFRunLoopTimerInvalidate(NS_CF_BRIDGE(CFRunLoopTimerRef, self));
}

- (BOOL)isValid {
    return CFRunLoopTimerIsValid(NS_CF_BRIDGE(CFRunLoopTimerRef, self)) ? YES : NO;
}

- (id)userInfo {
    _NSTimerInfo *timerInfo = __NSTimerInfoFor(NS_CF_BRIDGE(CFRunLoopTimerRef, self));
    return (timerInfo != NULL) ? timerInfo->userInfo : nil;
}

/* Asked for by CoreFoundation when it needs the fire date of an Objective-C
 * NSTimer that is not one of its own bridged instances. It is answered from
 * the record rather than by calling CFRunLoopTimerGetNextFireDate, because for
 * such an object that call would come straight back here. */
- (CFAbsoluteTime)_cffireTime {
    _NSTimerInfo *timerInfo = __NSTimerInfoFor(NS_CF_BRIDGE(CFRunLoopTimerRef, self));
    if (timerInfo != NULL) {
        return timerInfo->nextFireDate;
    }
    return CFRunLoopTimerGetNextFireDate(NS_CF_BRIDGE(CFRunLoopTimerRef, self));
}

#if !__has_feature(objc_arc)
/* A bridged timer lives in CoreFoundation's storage, which does not have an
 * Objective-C retain count to adjust; sending the object to NSObject's
 * implementations would scribble over fields CF owns. CoreFoundation never
 * sends these to its bridged class - it treats it as a CF type - so they exist
 * for the benefit of code compiled without ARC. */
- (id)retain {
    return (id)CFRetain(NS_CF_BRIDGE(CFTypeRef, self));
}

- (oneway void)release {
    CFRelease(NS_CF_BRIDGE(CFTypeRef, self));
}

- (NSUInteger)retainCount {
    return (NSUInteger)CFGetRetainCount(NS_CF_BRIDGE(CFTypeRef, self));
}

- (void)dealloc {
    /* CoreFoundation frees the timer once its own count reaches zero. */
}
#endif

@end

#pragma clang diagnostic pop

/* NSTimer is abstract. Its instance surface is answered by the bridged subclass
 * above - the same division PureFoundation draws - so this implementation holds
 * only the constructors. */
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wincomplete-implementation"

@implementation NSTimer

+ (NSTimer *)timerWithTimeInterval:(NSTimeInterval)ti target:(id)aTarget
                          selector:(SEL)aSelector userInfo:(id)userInfo
                           repeats:(BOOL)yesOrNo {
    if (ti < 0.0) {
        [NSException raise:NSInvalidArgumentException
                    format:@"-[NSTimer timerWithTimeInterval:...]: interval %g is negative", ti];
    }
    if ((aTarget == nil) || (aSelector == NULL)) {
        [NSException raise:NSInvalidArgumentException
                    format:@"-[NSTimer timerWithTimeInterval:...]: a target and a selector "
                           @"are both required"];
    }

    return __NSTimerCreate(ti, aTarget, aSelector, userInfo, yesOrNo);
}

+ (NSTimer *)scheduledTimerWithTimeInterval:(NSTimeInterval)ti target:(id)aTarget
                                   selector:(SEL)aSelector userInfo:(id)userInfo
                                    repeats:(BOOL)yesOrNo {
    NSTimer *timer = [self timerWithTimeInterval:ti target:aTarget selector:aSelector
                                        userInfo:userInfo repeats:yesOrNo];
    [[NSRunLoop currentRunLoop] addTimer:timer forMode:NSDefaultRunLoopMode];
    return timer;
}

@end

#pragma clang diagnostic pop

#if DEPLOYMENT_RUNTIME_OBJC
/* Runs before main, so that a CFRunLoopTimer created by any constructor below
 * comes back as an __NSCFTimer rather than as a bare CF type. */
__attribute__((constructor)) static void __NSCFTimerBridgeInit(void) {
    _CFRuntimeBridgeClasses(CFRunLoopTimerGetTypeID(), "__NSCFTimer");
}
#endif
