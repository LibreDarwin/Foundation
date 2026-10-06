/*
 * Copyright (C) 2026, PureDarwin Project.
 *
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 *
 * This header mirrors Apple's NSIndexPath.h.
 */

#import <Foundation/NSObject.h>
#import <Foundation/NSRange.h>

#if !defined(__FOUNDATION_NSINDEXPATH__)
#define __FOUNDATION_NSINDEXPATH__ 1

NS_HEADER_AUDIT_BEGIN(nullability, sendability)

API_AVAILABLE(macos(10.4), ios(3.0), watchos(2.0), tvos(9.0))
@interface NSIndexPath : NSObject <NSCopying, NSSecureCoding>

+ (instancetype)indexPathWithIndex:(NSUInteger)index;
+ (instancetype)indexPathWithIndexes:(const NSUInteger *)indexes length:(NSUInteger)length;

- (instancetype)initWithIndex:(NSUInteger)index NS_DESIGNATED_INITIALIZER;
- (instancetype)initWithIndexes:(const NSUInteger *)indexes length:(NSUInteger)length NS_DESIGNATED_INITIALIZER;

+ (instancetype)indexPathWithIndex:(NSUInteger)index;
- (instancetype)initWithIndexes:(const NSUInteger *)indexes length:(NSUInteger)length;

// Convenience
- (NSIndexPath *)indexPathByAddingIndex:(NSUInteger)index;
- (NSIndexPath *)indexPathByRemovingLastIndex;

@property (readonly) NSUInteger length;
- (NSUInteger)indexAtPosition:(NSUInteger)position;

- (void)getIndexes:(NSUInteger *)indexes range:(NSRange)range API_AVAILABLE(macos(10.9), ios(7.0), watchos(2.0), tvos(9.0));

- (void)getIndexes:(NSUInteger *)indexes API_DEPRECATED("Use the range based accessor instead", macos(10.4, 10.9), ios(3.0, 7.0), watchos(2.0, 2.0), tvos(9.0, 9.0));

// comparison (sorted)
- (NSComparisonResult)compare:(NSIndexPath *)otherObject;

@end

NS_HEADER_AUDIT_END(nullability, sendability)
#endif // defined __FOUNDATION_NSINDEXPATH__