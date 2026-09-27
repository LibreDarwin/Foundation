/*
 * Copyright (C) 2026, PureDarwin Project.
 *
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */

#ifndef NSNull_h
#define NSNull_h

#import <Foundation/NSObject.h>
#import <Foundation/NSObjCRuntime.h>

@class NSCoder;

@interface NSNull : NSObject <NSCopying, NSSecureCoding>

/* CoreFoundation owns the null behind this Foundation type on a host that
 * has Apple's Foundation loaded, so +class is overridden to report the
 * runtime's class and isKindOfClass: agrees.  See NSString.h. */
+ (Class)class;

+ (NSNull *)null;

- (id)copyWithZone:(NSZone *)zone;
- (void)encodeWithCoder:(NSCoder *)coder;
- (instancetype)initWithCoder:(NSCoder *)coder;
+ (BOOL)supportsSecureCoding;

@end

#endif /* NSNull_h */
