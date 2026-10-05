/*
 * Copyright (C) 2026, PureDarwin Project.
 *
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */

/* NSAutoreleasePool is NS_AUTOMATED_REFCOUNT_UNAVAILABLE, so it cannot be
 * named from ARC code at all - which is the point: every caller in the wild
 * drives it from non-ARC code.  The gate harness (port_behavior.m) is ARC, so
 * the pool probes live in this MRC translation unit and the harness calls
 * port_behavior_pool().
 *
 * Diagnostics go through NSLog, which writes to stderr; the golden file is
 * stdout, so the "Do not use this instance method" and "double release"
 * lines stay out of it.  What these probes pin down is the observable
 * lifetime behavior: what gets released at which drain, and in which order. */

#import <Foundation/Foundation.h>
#import <Foundation/NSAutoreleasePoolInternal.h>
#include <objc/runtime.h>
#include <stdio.h>
#include <string.h>

static void p(const char *label, const char *value) {
    printf("%-42s | %s\n", label, value);
}

/* Dealloc order for the lifetime probes.  Tags are single digits so the
 * recorded order prints as a string. */
static char __order[64];
static int __orderLen;

static void order_reset(void) {
    __orderLen = 0;
    __order[0] = '\0';
}

@interface ARPTracked : NSObject {
    int _tag;
}
- (instancetype)initWithTag:(int)tag;
@end

@implementation ARPTracked

- (instancetype)initWithTag:(int)tag {
    self = [super init];
    if (self != nil) {
        _tag = tag;
    }
    return self;
}

- (void)dealloc {
    if (__orderLen < (int)sizeof(__order) - 1) {
        __order[__orderLen++] = (char)('0' + _tag);
        __order[__orderLen] = '\0';
    }
    [super dealloc];
}

@end

/* Apple: NSAutoreleasePool : NSObject, and the class is not toll-free - an
 * instance is always a port instance. */
static void probe_identity(void) {
    NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
    p("arp/class", class_getName([pool class]));
    p("arp/superclass", class_getName([pool superclass]));
    p("arp/retainCount", [[NSString stringWithFormat:@"%lu",
                          (unsigned long)[pool retainCount]] UTF8String]);
    p("arp/isKindOfClass:NSObject", pool == nil ? "no" : ([pool isKindOfClass:[NSObject class]] ? "yes" : "no"));
    [pool drain];
}

/* Both are NSInvalidArgumentException with a nil userInfo; the reason is the
 * literal line Apple raises with. */
static void probe_refuse_retain(void) {
    @try {
        NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
        [pool retain];
        p("arp/-retain", "no exception");
        [pool drain];
    } @catch (NSException *e) {
        p("arp/-retain", [[NSString stringWithFormat:@"%@", [e name]] UTF8String]);
        p("arp/-retain/reason", [[e reason] UTF8String]);
        p("arp/-retain/userInfo", ([e userInfo] == nil ? "nil" : "present"));
    }
}

static void probe_refuse_autorelease(void) {
    @try {
        NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
        [pool autorelease];
        p("arp/-autorelease", "no exception");
        [pool drain];
    } @catch (NSException *e) {
        p("arp/-autorelease", [[NSString stringWithFormat:@"%@", [e name]] UTF8String]);
        p("arp/-autorelease/reason", [[e reason] UTF8String]);
    }
}

/* -initWithCapacity: logs and defers to -init, so the pool is usable. */
static void probe_init_with_capacity(void) {
    NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] initWithCapacity:32];
    p("arp/-initWithCapacity:/isPool",
      pool == nil ? "nil" : ([pool isKindOfClass:[NSAutoreleasePool class]] ? "yes" : "no"));
    order_reset();
    [pool addObject:[[ARPTracked alloc] initWithTag:1]];
    p("arp/-initWithCapacity:/beforeDrain", __order);
    [pool drain];
    p("arp/-initWithCapacity:/afterDrain", __order);
}

/* -addObject: transfers the +1 the caller already holds; it does not retain.
 * The object survives until this pool drains, and comes out LIFO. */
static void probe_instance_add_object(void) {
    NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
    order_reset();

    ARPTracked *a = [[ARPTracked alloc] initWithTag:1];
    [pool addObject:a];
    [pool addObject:[[ARPTracked alloc] initWithTag:2]];
    [pool addObject:[[ARPTracked alloc] initWithTag:3]];

    p("arp/-addObject:/retainCountAfterAdd",
      [[NSString stringWithFormat:@"%lu", (unsigned long)[a retainCount]] UTF8String]);
    p("arp/-addObject:/beforeDrain", __order);
    [pool drain];
    p("arp/-addObject:/afterDrain", __order);
}

/* The binding is per pool: an object added to the inner pool is released by
 * the inner drain, and the outer pool's object is untouched by it. */
static void probe_nested_pools(void) {
    order_reset();
    NSAutoreleasePool *outer = [[NSAutoreleasePool alloc] init];
    [outer addObject:[[ARPTracked alloc] initWithTag:1]];

    NSAutoreleasePool *inner = [[NSAutoreleasePool alloc] init];
    [inner addObject:[[ARPTracked alloc] initWithTag:2]];

    p("arp/nested/afterBothAdds", __order);
    [inner drain];
    p("arp/nested/afterInnerDrain", __order);
    [outer drain];
    p("arp/nested/afterOuterDrain", __order);
}

/* +addObject: means "the current thread's top pool", so the object lands in
 * the innermost live pool and that pool's drain releases it. */
static void probe_class_add_object(void) {
    order_reset();
    NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
    [NSAutoreleasePool addObject:[[ARPTracked alloc] initWithTag:7]];
    p("arp/+addObject:/beforeDrain", __order);
    [pool drain];
    p("arp/+addObject:/afterDrain", __order);
}

/* A drained pool is spent: the add is dropped and the caller keeps the +1. */
static void probe_add_object_after_drain(void) {
    order_reset();
    NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
    [pool drain];

    ARPTracked *orphan = [[ARPTracked alloc] initWithTag:5];
    [pool addObject:orphan];
    p("arp/-addObject:/afterDrain", __order);
    [orphan release];
    p("arp/-addObject:/callerReleases", __order);
}

/* -release and -drain both pop the pool; -release is how MRC code disposes of
 * one it never drains. */
static void probe_release_drains(void) {
    order_reset();
    NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
    [pool addObject:[[ARPTracked alloc] initWithTag:6]];
    p("arp/-release/beforeRelease", __order);
    [pool release];
    p("arp/-release/afterRelease", __order);
}

/* Every debugging entry point is inert: answering 0/NO before and after the
 * setters are called is the whole of Apple's behavior on a modern runtime. */
static void probe_debug_surface(void) {
    [NSAutoreleasePool showPools];
    [NSAutoreleasePool releaseAllPools];
    [NSAutoreleasePool enableRelease:YES];
    [NSAutoreleasePool enableFreedObjectCheck:YES];
    [NSAutoreleasePool setPoolCountHighWaterMark:4096];
    [NSAutoreleasePool setPoolCountHighWaterResolution:64];
    [NSAutoreleasePool resetTotalAutoreleasedObjects];

    p("arp/+topAutoreleasePoolCount",
      [[NSString stringWithFormat:@"%lu",
        (unsigned long)[NSAutoreleasePool topAutoreleasePoolCount]] UTF8String]);
    p("arp/+autoreleasePoolExists", [NSAutoreleasePool autoreleasePoolExists] ? "YES" : "NO");
    p("arp/+autoreleasedObjectCount",
      [[NSString stringWithFormat:@"%lu",
        (unsigned long)[NSAutoreleasePool autoreleasedObjectCount]] UTF8String]);
    p("arp/+poolCountHighWaterMark",
      [[NSString stringWithFormat:@"%lu",
        (unsigned long)[NSAutoreleasePool poolCountHighWaterMark]] UTF8String]);
    p("arp/+poolCountHighWaterResolution",
      [[NSString stringWithFormat:@"%lu",
        (unsigned long)[NSAutoreleasePool poolCountHighWaterResolution]] UTF8String]);
    p("arp/+totalAutoreleasedObjects",
      [[NSString stringWithFormat:@"%lu",
        (unsigned long)[NSAutoreleasePool totalAutoreleasedObjects]] UTF8String]);

    p("arp/_NSAutoreleasePoolCount",
      [[NSString stringWithFormat:@"%lu", _NSAutoreleasePoolCount()] UTF8String]);
    p("arp/__NSAutoreleasePoolGetRubyToken",
      [[NSString stringWithFormat:@"%lu",
        (unsigned long)(uintptr_t)__NSAutoreleasePoolGetRubyToken()] UTF8String]);
    __NSAutoreleasePoolSetRubyToken(NULL);
    p("arp/__NSAutoreleasePoolSetRubyToken", "ok");
}

void port_behavior_pool(void);
void port_behavior_pool(void) {
    probe_identity();
    probe_refuse_retain();
    probe_refuse_autorelease();
    probe_init_with_capacity();
    probe_instance_add_object();
    probe_nested_pools();
    probe_class_add_object();
    probe_add_object_after_drain();
    probe_release_drains();
    probe_debug_surface();
}