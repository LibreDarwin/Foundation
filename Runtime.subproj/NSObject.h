/*
 * Copyright (C) 2026, Samuel Zormeister.
 *
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */

#if !defined(__FOUNDATION_NSOBJECT__)
#define __FOUNDATION_NSOBJECT__ 1

#import <objc/NSObject.h>
#import <Foundation/NSObjCRuntime.h>
#import <Foundation/NSZone.h>
#include <CoreFoundation/CFBase.h>

@class NSCoder;

/* The two bridging casts ARC code uses to hand an object to CoreFoundation and
 * back. They are inlines rather than functions so the __bridge_retained and
 * __bridge_transfer casts happen in the caller, where ARC can see them. */
static inline CFTypeRef _Nullable CFBridgingRetain(id _Nullable object) {
    return (__bridge_retained CFTypeRef)object;
}

static inline id _Nullable CFBridgingRelease(CFTypeRef CF_RELEASES_ARGUMENT _Nullable value) {
    return (__bridge_transfer id)value;
}

@protocol NSCopying
- (id)copyWithZone:(NSZone *)zone;
@end

@protocol NSMutableCopying
- (id)mutableCopyWithZone:(NSZone *)zone;
@end

@protocol NSCoding
- (void)encodeWithCoder:(NSCoder *)coder;
- (instancetype _Nullable)initWithCoder:(NSCoder *)coder;
@end

/* A secure coder will not instantiate a class that does not adopt this, and
 * checks every object it decodes against a list of allowed classes.  A
 * subclass that overrides -initWithCoder: has to re-answer +supportsSecureCoding
 * for itself; inheriting the superclass's YES would vouch for code the
 * superclass never saw. */
@protocol NSSecureCoding <NSCoding>
@required
@property (class, readonly) BOOL supportsSecureCoding;
@end

/* Fast enumeration: the runtime-and-ABI contract between a collection and a
 * for-in loop.  It lives here (GNUstep keeps it in NSObject.h too) rather
 * than in NSEnumerator.h because every class that conforms imports
 * NSObject.h, and the generated umbrella includes headers in name order, so
 * this block has to be seen before NSArray.h's interface.
 *
 * state->state is the cursor across calls; the runtime zeroes it once at the
 * head of a fresh loop and preserves it between chunk calls.  state->itemsPtr
 * is the buffer the collection fills and state->mutationsPtr a stable
 * location whose value must not change between calls - point it at
 * state->extra[0] and never write there.  Returning a full buffer (len)
 * means more chunks are coming; returning a short count or zero ends the
 * loop. */
typedef struct {
    unsigned long state;
    id __unsafe_unretained _Nullable *_Nonnull itemsPtr;
    unsigned long *_Nullable mutationsPtr;
    unsigned long extra[5];
} NSFastEnumerationState;

@protocol NSFastEnumeration
- (NSUInteger)countByEnumeratingWithState:(NSFastEnumerationState *)state
                                  objects:(id __unsafe_unretained _Nullable[_Nonnull])stackbuf
                                    count:(NSUInteger)len;
@end

#endif /* ! __FOUNDATION_NSOBJECT__ */
