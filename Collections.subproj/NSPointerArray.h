/*
 * Copyright (C) 2026, PureDarwin Project.
 *
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 *
 * This header mirrors Apple's NSPointerArray.h.
 */

#import <Foundation/NSEnumerator.h>
#import <Foundation/NSObject.h>
#import <Foundation/NSPointerFunctions.h>

#if !defined(__FOUNDATION_NSPOINTERARRAY__)
#define __FOUNDATION_NSPOINTERARRAY__ 1

NS_HEADER_AUDIT_BEGIN(nullability, sendability)

@class NSArray<ObjectType>, NSEnumerator, NSPointerFunctions;

/* NSPointerArray is a mutable collection modeled after NSArray, but with a wider variety of possible memory use options.
   In particular, it is possible to hold objects via strong, weak, unsafe-unretained, or pure C pointers.
   Scoped to be copyable, codable, enumerable, and to support the generic array subscripting operations.
*/

API_AVAILABLE(macos(10.5), ios(6.0), watchos(2.0), tvos(9.0))
@interface NSPointerArray : NSObject <NSCopying, NSSecureCoding, NSFastEnumeration>

// conveniences

+ (NSPointerArray *)pointerArrayWithOptions:(NSPointerFunctionsOptions)options;
+ (NSPointerArray *)pointerArrayWithPointerFunctions:(NSPointerFunctions *)functions;

- (instancetype)initWithOptions:(NSPointerFunctionsOptions)options;
- (instancetype)initWithPointerFunctions:(NSPointerFunctions *)functions NS_DESIGNATED_INITIALIZER;

/* Returns the pointer functions set at initialization time.
 */
@property (readonly, copy) NSPointerFunctions *pointerFunctions;

/* Query/Set the array count.
 The count can be directly increased (a nil value will be added at the end) or decreased.
 */
@property NSUInteger count;

/* Access the pointer at the given index.
 */
- (void *)pointerAtIndex:(NSUInteger)index;

/* Add a pointer at the end of the array.
 */
- (void)addPointer:(nullable void *)pointer;

/* Remove a pointer at the given index.
 */
- (void)removePointerAtIndex:(NSUInteger)index;

/* Insert a pointer at the given index, shifting existing content to the right.
 */
- (void)insertPointer:(nullable void *)item atIndex:(NSUInteger)index;

/* Replace the pointer at the given index with a new one, releasing the old value.
 */
- (void)replacePointerAtIndex:(NSUInteger)index withPointer:(nullable void *)item;

/* Remove all NULL values from the array.
 */
- (void)compact;

@end

@interface NSPointerArray (NSPointerArrayConveniences)  // no longer recommended

+ (NSPointerArray *)strongObjectsPointerArray NS_AVAILABLE(10_8, 6_0);
+ (NSPointerArray *)weakObjectsPointerArray NS_AVAILABLE(10_8, 6_0);

@property (readonly, copy) NSArray *allObjects;

@end

NS_HEADER_AUDIT_END(nullability, sendability)
#endif // defined __FOUNDATION_NSPOINTERARRAY__