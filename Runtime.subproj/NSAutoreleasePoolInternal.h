/*
 * Copyright (C) 2026, PureDarwin Project.
 *
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */

/* Not in the umbrella, like NSCFTypeID.h: this is the debugging and
 * pre-optimization surface Apple keeps out of the SDK.  NSAutoreleasePool.m
 * still implements every selector declared here, because Apple's Foundation
 * exports them all and the pairing sweep compares the exported set. */

#ifndef NSAutoreleasePoolInternal_h
#define NSAutoreleasePoolInternal_h

#import <Foundation/NSAutoreleasePool.h>

/* -initWithCapacity: is the pre-optimization-era initializer.  It logs and
 * defers to -init. */
@interface NSAutoreleasePool (NSAutoreleasePoolPrivate)

- (instancetype)initWithCapacity:(NSUInteger)capacity;

/* All of these are inert on a modern runtime: the counters the pool used to
 * keep were removed when it became objc_autoreleasePoolPush/-Pop.  They stay
 * because callers (and Apple's own export list) still reference them. */
+ (void)showPools;
+ (void)releaseAllPools;
+ (unsigned long)autoreleasedObjectCount;
+ (NSUInteger)topAutoreleasePoolCount;
+ (BOOL)autoreleasePoolExists;
+ (void)enableRelease:(BOOL)flag;
+ (void)enableFreedObjectCheck:(BOOL)flag;
+ (unsigned long)poolCountHighWaterMark;
+ (void)setPoolCountHighWaterMark:(unsigned long)mark;
+ (unsigned long)poolCountHighWaterResolution;
+ (void)setPoolCountHighWaterResolution:(unsigned long)resolution;
+ (unsigned long)totalAutoreleasedObjects;
+ (void)resetTotalAutoreleasedObjects;

@end

/* Ruby (libruby) reads the pool's page token through these instead of the
 * ivar.  GetRubyToken answers 62 - Ruby's autorelease pool depth sentinel -
 * unconditionally on Apple's Foundation. */
void *__NSAutoreleasePoolGetRubyToken(void);
void __NSAutoreleasePoolSetRubyToken(void *token);
unsigned long _NSAutoreleasePoolCount(void);

#endif /* NSAutoreleasePoolInternal_h */