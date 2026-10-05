/*
 * Copyright (C) 2026, PureDarwin Project.
 *
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */

#ifndef NSAutoreleasePool_h
#define NSAutoreleasePool_h

#import <Foundation/NSObject.h>

NS_HEADER_AUDIT_BEGIN(nullability, sendability)

/* The layout is Apple's, unchanged: four pointer ivars, nothing appended.
 * _token is the runtime's autorelease pool page (objc_autoreleasePoolPush).
 * _reserved3 and _reserved2 are set to -1 by -drain and -release
 * respectively and are what the "double release" diagnostics test.  See
 * NSAutoreleasePool.m for why the instance -addObject: list lives outside the
 * instance. */
NS_AUTOMATED_REFCOUNT_UNAVAILABLE
@interface NSAutoreleasePool : NSObject {
@private
    void *_token;
    void *_reserved3;
    void *_reserved2;
    void *_reserved;
}

+ (void)addObject:(id)anObject;

- (void)addObject:(id)anObject;

- (void)drain;

@end

NS_HEADER_AUDIT_END(nullability, sendability)

#endif /* NSAutoreleasePool_h */