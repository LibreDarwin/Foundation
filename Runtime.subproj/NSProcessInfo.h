/*
 * Copyright (C) 2026, PureDarwin Project.
 *
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */

#ifndef NSProcessInfo_h
#define NSProcessInfo_h

#import <Foundation/NSObject.h>
#import <Foundation/NSObjCRuntime.h>

#import <Foundation/NSArray.h>
#import <Foundation/NSDictionary.h>
#import <Foundation/NSString.h>

/*
 * Properties, as Foundation declares them, rather than methods: the
 * Objective-C calls are the same either way, but Swift imports a class
 * method returning the class as an initializer, so +processInfo came
 * through as an unusable init() and ProcessInfo.processInfo did not
 * exist.  And nonnull, as Foundation's are: without it environment is
 * an Optional in Swift, and environment["X"] does not compile.
 */
@interface NSProcessInfo : NSObject

@property (class, readonly, strong, nonnull) NSProcessInfo *processInfo;

@property (readonly, copy, nonnull) NSDictionary<NSString *, NSString *> *environment;
@property (readonly, copy, nonnull) NSArray<NSString *> *arguments;
@property (readonly, copy, nonnull) NSString *hostName;
@property (copy, nonnull) NSString *processName;
@property (readonly) int processIdentifier;
@property (readonly) NSUInteger processorCount;
@property (readonly) unsigned long long physicalMemory;

@end

#endif /* NSProcessInfo_h */
