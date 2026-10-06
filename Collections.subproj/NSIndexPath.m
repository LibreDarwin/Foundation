/*
 * Copyright (C) 2026, PureDarwin Project.
 *
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 *
 * NSIndexPath mirrors Apple's immutable index-path class: a malloc-backed
 * NSUInteger row of depth `length`, depth-first compare, range-checked
 * accessors that raise NSRangeException on out-of-bounds positions, and
 * NSSecureCoding.  Paths are immutable, so copy returns self.
 */

#import <Foundation/NSIndexPath.h>
#import <Foundation/NSArray.h>
#import <Foundation/NSNumber.h>
#import <Foundation/NSCoder.h>
#import <Foundation/NSException.h>
#import <Foundation/NSString.h>

#include <stdlib.h>
#include <string.h>

@implementation NSIndexPath {
    NSUInteger *_indexes;
    NSUInteger _length;
}

+ (BOOL)supportsSecureCoding {
    return YES;
}

+ (instancetype)indexPathWithIndex:(NSUInteger)index {
    return [(NSIndexPath *)[self alloc] initWithIndex:index];
}

+ (instancetype)indexPathWithIndexes:(const NSUInteger *)indexes length:(NSUInteger)length {
    return [(NSIndexPath *)[self alloc] initWithIndexes:indexes length:length];
}

- (instancetype)initWithIndex:(NSUInteger)index {
    return [self initWithIndexes:&index length:1];
}

- (instancetype)initWithIndexes:(const NSUInteger *)indexes length:(NSUInteger)length {
    self = [super init];
    if (self) {
        if (length > 0) {
            _indexes = malloc(length * sizeof(NSUInteger));
            memcpy(_indexes, indexes, length * sizeof(NSUInteger));
        }
        _length = length;
    }
    return self;
}

- (void)dealloc {
    if (_indexes) {
        free(_indexes);
    }
}

- (NSIndexPath *)indexPathByAddingIndex:(NSUInteger)index {
    NSUInteger *newIndexes = malloc((_length + 1) * sizeof(NSUInteger));
    if (_length > 0) memcpy(newIndexes, _indexes, _length * sizeof(NSUInteger));
    newIndexes[_length] = index;
    NSIndexPath *result = [(NSIndexPath *)[NSIndexPath alloc] initWithIndexes:newIndexes length:(_length + 1)];
    free(newIndexes);
    return result;
}

- (NSIndexPath *)indexPathByRemovingLastIndex {
    if (_length == 0) {
        return [(NSIndexPath *)[NSIndexPath alloc] initWithIndexes:_indexes length:0];
    }
    return [(NSIndexPath *)[NSIndexPath alloc] initWithIndexes:_indexes length:(_length - 1)];
}

- (NSUInteger)length {
    return _length;
}

- (NSUInteger)indexAtPosition:(NSUInteger)position {
    if (position >= _length) {
        return NSNotFound;
    }
    return _indexes[position];
}

- (void)getIndexes:(NSUInteger *)indexes range:(NSRange)range {
    if (range.location > _length || NSMaxRange(range) > _length) {
        [NSException raise:NSRangeException format:@"range {%lu,%lu} beyond path length %lu",
                    (unsigned long)range.location, (unsigned long)range.length, (unsigned long)_length];
    }
    memcpy(indexes, _indexes + range.location, range.length * sizeof(NSUInteger));
}

- (void)getIndexes:(NSUInteger *)indexes {
    memcpy(indexes, _indexes, _length * sizeof(NSUInteger));
}

- (NSComparisonResult)compare:(NSIndexPath *)otherObject {
    NSUInteger common = (_length < otherObject->_length) ? _length : otherObject->_length;
    for (NSUInteger i = 0; i < common; i++) {
        if (_indexes[i] < otherObject->_indexes[i]) return NSOrderedAscending;
        if (_indexes[i] > otherObject->_indexes[i]) return NSOrderedDescending;
    }
    if (_length < otherObject->_length) return NSOrderedAscending;
    if (_length > otherObject->_length) return NSOrderedDescending;
    return NSOrderedSame;
}

- (BOOL)isEqual:(id)object {
    if (self == object) return YES;
    if (![object isKindOfClass:[NSIndexPath class]]) return NO;
    NSIndexPath *other = (NSIndexPath *)object;
    if (_length != other->_length) return NO;
    return (memcmp(_indexes, other->_indexes, _length * sizeof(NSUInteger)) == 0);
}

- (NSUInteger)hash {
    NSUInteger hash = _length * 2654435761u;
    for (NSUInteger i = 0; i < _length; i++) {
        hash = hash * 31 + _indexes[i];
    }
    return hash;
}

- (id)copyWithZone:(NSZone *)zone {
    return self;
}

- (instancetype)initWithCoder:(NSCoder *)coder {
    NSArray *indexes = [coder decodeObjectOfClass:[NSArray class] forKey:@"indexes"];
    NSUInteger length = [indexes count];
    NSUInteger *values = NULL;
    if (length > 0) {
        values = malloc(length * sizeof(NSUInteger));
        for (NSUInteger i = 0; i < length; i++) {
            values[i] = [[indexes objectAtIndex:i] unsignedIntegerValue];
        }
    }
    self = [self initWithIndexes:values length:length];
    if (values) free(values);
    return self;
}

- (void)encodeWithCoder:(NSCoder *)coder {
    NSMutableArray *indexes = [NSMutableArray arrayWithCapacity:_length];
    for (NSUInteger i = 0; i < _length; i++) {
        [indexes addObject:[NSNumber numberWithUnsignedInteger:_indexes[i]]];
    }
    [coder encodeObject:indexes forKey:@"indexes"];
}

- (NSString *)description {
    NSMutableString *path = [NSMutableString stringWithCapacity:_length * 4];
    for (NSUInteger i = 0; i < _length; i++) {
        if (i > 0) [path appendString:@" - "];
        [path appendFormat:@"%lu", (unsigned long)_indexes[i]];
    }
    return [NSString stringWithFormat:@"<NSIndexPath: %p> {length = %lu, path = %@}",
            self, (unsigned long)_length, path];
}

@end