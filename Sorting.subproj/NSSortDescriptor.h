/*
 * Copyright (C) 2026, Samuel Zormeister.
 *
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */

#ifndef NSSortDescriptor_h
#define NSSortDescriptor_h

#import <Foundation/NSObject.h>
#import <Foundation/NSObjCRuntime.h>
#import <Foundation/NSCoder.h>

@interface NSSortDescriptor : NSObject <NSSecureCoding, NSCopying> {
    NSString *_key;
    BOOL _ascending;
    SEL _selector;
    NSComparator _selectorOrBlock;
    unsigned int _reverseNullOrder : 1;
    unsigned int _explicitSelector : 1;
}

+ (instancetype)sortDescriptorWithKey:(nullable NSString *)key ascending:(BOOL)ascending;
+ (instancetype)sortDescriptorWithKey:(nullable NSString *)key ascending:(BOOL)ascending selector:(SEL)selector;
+ (instancetype)sortDescriptorWithKey:(nullable NSString *)key ascending:(BOOL)ascending comparator:(NSComparator)comparator;

- (instancetype)initWithKey:(nullable NSString *)key ascending:(BOOL)ascending;
- (instancetype)initWithKey:(nullable NSString *)key ascending:(BOOL)ascending selector:(SEL)selector;
- (instancetype)initWithKey:(nullable NSString *)key ascending:(BOOL)ascending comparator:(NSComparator)comparator;

@property (nullable, readonly, copy) NSString *key;
@property (readonly) BOOL ascending;
@property (nullable, readonly) SEL selector;
@property (nullable, readonly) NSComparator comparator;

- (void)allowEvaluation;
- (BOOL)reverseNullOrder;
- (NSComparisonResult)compareObject:(nullable id)object1 toObject:(nullable id)object2;
- (instancetype)reversedSortDescriptor;

- (void)encodeWithCoder:(NSCoder *)coder;
- (instancetype)initWithCoder:(NSCoder *)coder;
+ (BOOL)supportsSecureCoding;

@end

#endif /* NSSortDescriptor_h */