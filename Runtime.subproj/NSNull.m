/*
 * Copyright (C) 2026, PureDarwin Project.
 *
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */

#import <Foundation/NSNull.h>
#import <Foundation/NSCoder.h>
#import <Foundation/NSString.h>
#include <CoreFoundation/CFString.h>

@implementation NSNull

/* NSNull is a singleton; equality is identity, so every path that could hand
 * back an instance hands back the shared one. */
+ (NSNull *)null {
    static NSNull *shared = nil;
    if (shared == nil) {
        shared = [[self alloc] init];
    }
    return shared;
}

- (NSString *)description {
    return (NSString *)CFSTR("<null>");
}

- (id)copyWithZone:(NSZone *)zone {
    (void)zone;
    return self;
}

/* The null placeholder carries no state: its archive is empty and both the
 * keyed and unkeyed decoders resolve to the singleton. */
- (void)encodeWithCoder:(NSCoder *)coder {
    (void)coder;
}

- (instancetype)initWithCoder:(NSCoder *)coder {
    (void)coder;
    return [[self class] null];
}

+ (BOOL)supportsSecureCoding {
    return YES;
}

@end
