/*
 * Copyright (C) 2026, PureDarwin Project.
 *
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 *
 * The API and range-list algorithms were adapted from Cocotron Foundation's
 * NSIndexSet implementation by Christopher J. W. Lloyd and contributors,
 * used under its MIT license.  The storage here is a plain malloc-backed
 * array of sorted, disjoint NSRanges instead of Cocotron's NSZone
 * allocation, and the set-union live-buffer queries follow Apple's
 * documented -getIndexes:maxCount:inIndexRange: semantics.
 */

#import <Foundation/NSIndexSet.h>
#import <Foundation/NSString.h>
#import <Foundation/NSCoder.h>

#include <stdlib.h>
#include <string.h>

/* ---- static helpers over the sorted, disjoint range array ---- */

/* Index of the LAST range whose location is at or below `location`, or
 * NSNotFound when every range starts above it. */
static NSUInteger NSISPositionLessThanOrEqualToLocation(NSRange *ranges, NSUInteger length, NSUInteger location) {
    NSInteger i = (NSInteger)length;
    while (--i >= 0) {
        if (ranges[i].location <= location) {
            return (NSUInteger)i;
        }
    }
    return NSNotFound;
}

/* Index of the FIRST range whose span reaches (not necessarily contains)
 * `location`, or NSNotFound when every range ends at or below it. */
static NSUInteger NSISPositionReachingLocation(NSRange *ranges, NSUInteger length, NSUInteger location) {
    for (NSUInteger i = 0; i < length; i++) {
        if (location < NSMaxRange(ranges[i])) {
            return i;
        }
    }
    return NSNotFound;
}

/* Shift the trailing part of the array left over `position`. */
static void NSISRemoveRangeAtPosition(NSRange *ranges, NSUInteger position, NSUInteger length) {
    NSUInteger i;
    for (i = position; i + 1 < length; i++) {
        ranges[i] = ranges[i + 1];
    }
}

static NSRange *NSISEnsureCapacity(NSRange *ranges, NSUInteger *capacity, NSUInteger needed) {
    if (needed <= *capacity) {
        return ranges;
    }
    NSUInteger newCapacity = *capacity ? *capacity : 1;
    while (newCapacity < needed) {
        newCapacity *= 2;
    }
    ranges = (NSRange *)realloc(ranges, sizeof(NSRange) * newCapacity);
    *capacity = newCapacity;
    return ranges;
}

/* Fold any overlapping or adjacent ranges left into one canonical list. */
static void NSISMergeAdjacent(NSRange *ranges, NSUInteger *length) {
    NSUInteger out = 0;
    for (NSUInteger i = 0; i < *length; i++) {
        NSRange r = ranges[i];
        if (out > 0 && r.location <= NSMaxRange(ranges[out - 1])) {
            NSUInteger cur = NSMaxRange(ranges[out - 1]);
            NSUInteger end = NSMaxRange(r);
            if (end > cur) {
                ranges[out - 1].length = end - ranges[out - 1].location;
            }
        } else {
            ranges[out++] = r;
        }
    }
    *length = out;
}

/* Core enumeration.  `rangePtr` bounds the visited indexes to [location,
 * location+length); pass NULL to visit the whole set.  `top` must be the
 * first index below the enumeration window and `end` one past the last. */
static void NSISEnumerate(NSIndexSet *self, NSRange *ranges, NSUInteger length,
                          NSUInteger top, NSUInteger end, BOOL reverse,
                          void (^block)(NSUInteger idx, BOOL *stop)) {
    BOOL stop = NO;
    if (reverse) {
        for (NSInteger p = (NSInteger)length - 1; p >= 0 && !stop; p--) {
            NSRange stored = ranges[p];
            NSUInteger storedMax = NSMaxRange(stored);
            if (storedMax <= top) {
                break;
            }
            NSUInteger lo = stored.location > top ? stored.location : top;
            NSUInteger hi = storedMax < end ? storedMax : end;
            for (NSUInteger i = hi; i-- > lo && !stop;) {
                block(i, &stop);
            }
        }
    } else {
        for (NSUInteger p = 0; p < length && !stop; p++) {
            NSRange stored = ranges[p];
            if (stored.location >= end) {
                break;
            }
            NSUInteger lo = stored.location > top ? stored.location : top;
            NSUInteger hi = NSMaxRange(stored) < end ? NSMaxRange(stored) : end;
            for (NSUInteger i = lo; i < hi && !stop; i++) {
                block(i, &stop);
            }
        }
    }
}

/* ---- NSIndexSet ---- */

@implementation NSIndexSet {
}
- (void)dealloc {
    free(_ranges);
}

- (instancetype)init {
    return [self initWithIndexesInRange:NSMakeRange(0, 0)];
}

- (instancetype)initWithIndex:(NSUInteger)value {
    return [self initWithIndexesInRange:NSMakeRange(value, 1)];
}

- (instancetype)initWithIndexesInRange:(NSRange)range {
    self = [super init];
    if (self) {
        _capacity = 1;
        _ranges = (NSRange *)calloc(_capacity, sizeof(NSRange));
        if (range.length == 0) {
            _length = 0;
        } else {
            _length = 1;
            _ranges[0] = range;
        }
    }
    return self;
}

- (instancetype)initWithIndexSet:(NSIndexSet *)indexSet {
    self = [super init];
    if (self) {
        _length = indexSet->_length;
        _capacity = _length ? _length : 1;
        _ranges = (NSRange *)calloc(_capacity, sizeof(NSRange));
        for (NSUInteger i = 0; i < _length; i++) {
            _ranges[i] = indexSet->_ranges[i];
        }
    }
    return self;
}

+ (instancetype)indexSet {
    return [[self alloc] init];
}

+ (instancetype)indexSetWithIndex:(NSUInteger)value {
    return [[self alloc] initWithIndex:value];
}

+ (instancetype)indexSetWithIndexesInRange:(NSRange)range {
    return [[self alloc] initWithIndexesInRange:range];
}

- (id)copyWithZone:(NSZone *)zone {
    (void)zone;
    return self;
}

- (id)mutableCopyWithZone:(NSZone *)zone {
    (void)zone;
    return [[NSMutableIndexSet alloc] initWithIndexSet:self];
}

- (BOOL)isEqualToIndexSet:(NSIndexSet *)indexSet {
    if (self == indexSet) {
        return YES;
    }
    if (!indexSet || _length != indexSet->_length) {
        return NO;
    }
    for (NSUInteger i = 0; i < _length; i++) {
        if (!NSEqualRanges(_ranges[i], indexSet->_ranges[i])) {
            return NO;
        }
    }
    return YES;
}

- (BOOL)isEqual:(id)object {
    return [object isKindOfClass:[NSIndexSet class]] && [self isEqualToIndexSet:object];
}

- (NSUInteger)hash {
    NSUInteger result = 0;
    for (NSUInteger i = 0; i < _length; i++) {
        result ^= _ranges[i].location + (_ranges[i].length << 1);
    }
    return result ^ self.count;
}

- (NSUInteger)count {
    NSUInteger result = 0;
    for (NSUInteger i = 0; i < _length; i++) {
        result += _ranges[i].length;
    }
    return result;
}

- (NSUInteger)firstIndex {
    return _length > 0 ? _ranges[0].location : NSNotFound;
}

- (NSUInteger)lastIndex {
    return _length > 0 ? NSMaxRange(_ranges[_length - 1]) - 1 : NSNotFound;
}

- (NSUInteger)indexGreaterThanIndex:(NSUInteger)value {
    NSUInteger first = NSISPositionReachingLocation(_ranges, _length, value);
    if (first == NSNotFound) {
        return NSNotFound;
    }
    if (value < _ranges[first].location) {
        return _ranges[first].location;
    }
    if (value + 1 < NSMaxRange(_ranges[first])) {
        return value + 1;
    }
    first++;
    if (first < _length) {
        return _ranges[first].location;
    }
    return NSNotFound;
}

- (NSUInteger)indexGreaterThanOrEqualToIndex:(NSUInteger)value {
    NSUInteger first = NSISPositionReachingLocation(_ranges, _length, value);
    if (first == NSNotFound) {
        return NSNotFound;
    }
    if (value < _ranges[first].location) {
        return _ranges[first].location;
    }
    if (value < NSMaxRange(_ranges[first])) {
        return value;
    }
    first++;
    if (first < _length) {
        return _ranges[first].location;
    }
    return NSNotFound;
}

- (NSUInteger)indexLessThanIndex:(NSUInteger)value {
    if (value == 0) {
        return NSNotFound;
    }
    NSUInteger first = NSISPositionLessThanOrEqualToLocation(_ranges, _length, value);
    if (first == NSNotFound) {
        return NSNotFound;
    }
    if (NSLocationInRange(value - 1, _ranges[first])) {
        return value - 1;
    }
    if (value == _ranges[first].location) {
        if (first == 0) {
            return NSNotFound;
        }
        first--;
    }
    return NSMaxRange(_ranges[first]) - 1;
}

- (NSUInteger)indexLessThanOrEqualToIndex:(NSUInteger)value {
    NSUInteger first = NSISPositionLessThanOrEqualToLocation(_ranges, _length, value);
    if (first == NSNotFound) {
        return NSNotFound;
    }
    if (NSLocationInRange(value, _ranges[first])) {
        return value;
    }
    return NSMaxRange(_ranges[first]) - 1;
}

- (NSUInteger)getIndexes:(NSUInteger *)indexBuffer maxCount:(NSUInteger)bufferSize inIndexRange:(NSRange *)range {
    NSRange window;
    NSUInteger result = 0;

    if (range != NULL) {
        window = *range;
    } else {
        if (_length == 0) {
            return 0;
        }
        window.location = _ranges[0].location;
        window.length = NSMaxRange(_ranges[_length - 1]) - window.location;
    }

    NSUInteger windowMax = NSMaxRange(window);
    NSUInteger pos = NSISPositionReachingLocation(_ranges, _length, window.location);
    while (pos < _length && result < bufferSize) {
        NSRange stored = _ranges[pos];
        if (stored.location >= windowMax) {
            break;
        }
        NSUInteger lo = stored.location > window.location ? stored.location : window.location;
        NSUInteger hi = NSMaxRange(stored) < windowMax ? NSMaxRange(stored) : windowMax;
        for (NSUInteger i = lo; i < hi && result < bufferSize; i++) {
            indexBuffer[result++] = i;
        }
        pos++;
    }

    if (range != NULL) {
        if (result > 0) {
            NSUInteger next = indexBuffer[result - 1] + 1;
            range->location = next;
            range->length = (next < windowMax) ? (windowMax - next) : 0;
        } else {
            range->location = window.location;
            range->length = window.length;
        }
    }
    return result;
}

- (NSUInteger)countOfIndexesInRange:(NSRange)range {
    NSUInteger result = 0;
    NSUInteger max = NSMaxRange(range);
    for (NSUInteger i = 0; i < _length; i++) {
        NSRange stored = _ranges[i];
        if (stored.location >= max) {
            break;
        }
        NSUInteger lo = stored.location;
        NSUInteger hi = NSMaxRange(stored);
        if (lo < range.location) {
            lo = range.location;
        }
        if (hi > max) {
            hi = max;
        }
        if (hi > lo) {
            result += hi - lo;
        }
    }
    return result;
}

- (BOOL)containsIndex:(NSUInteger)value {
    return [self containsIndexesInRange:NSMakeRange(value, 1)];
}

- (BOOL)containsIndexesInRange:(NSRange)range {
    if (range.length == 0) {
        return NO;
    }
    NSUInteger max = NSMaxRange(range);
    NSUInteger pos = NSISPositionLessThanOrEqualToLocation(_ranges, _length, range.location);
    return pos != NSNotFound && NSMaxRange(_ranges[pos]) >= max;
}

- (BOOL)containsIndexes:(NSIndexSet *)indexSet {
    if (_length == 0) {
        return indexSet->_length == 0;
    }
    for (NSUInteger i = 0; i < indexSet->_length; i++) {
        if (![self containsIndexesInRange:indexSet->_ranges[i]]) {
            return NO;
        }
    }
    return YES;
}

- (BOOL)intersectsIndexesInRange:(NSRange)range {
    if (range.length == 0) {
        return NO;
    }
    NSUInteger pos = NSISPositionReachingLocation(_ranges, _length, range.location);
    if (pos == NSNotFound) {
        return NO;
    }
    return _ranges[pos].location < NSMaxRange(range);
}

- (void)enumerateIndexesUsingBlock:(void (NS_NOESCAPE ^)(NSUInteger idx, BOOL *stop))block {
    [self enumerateIndexesWithOptions:0 usingBlock:block];
}

- (void)enumerateIndexesWithOptions:(NSEnumerationOptions)opts usingBlock:(void (NS_NOESCAPE ^)(NSUInteger idx, BOOL *stop))block {
    [self enumerateIndexesInRange:NSMakeRange(0, NSIntegerMax - 1) options:opts usingBlock:block];
}

- (void)enumerateIndexesInRange:(NSRange)range options:(NSEnumerationOptions)opts usingBlock:(void (NS_NOESCAPE ^)(NSUInteger idx, BOOL *stop))block {
    if (_length == 0 || range.length == 0) {
        return;
    }
    NSISEnumerate(self, _ranges, _length, range.location, NSMaxRange(range), (opts & NSEnumerationReverse) != 0, block);
}

- (NSUInteger)indexPassingTest:(BOOL (NS_NOESCAPE ^)(NSUInteger idx, BOOL *stop))predicate {
    return [self indexWithOptions:0 passingTest:predicate];
}

- (NSUInteger)indexWithOptions:(NSEnumerationOptions)opts passingTest:(BOOL (NS_NOESCAPE ^)(NSUInteger idx, BOOL *stop))predicate {
    return [self indexInRange:NSMakeRange(0, NSIntegerMax - 1) options:opts passingTest:predicate];
}

- (NSUInteger)indexInRange:(NSRange)range options:(NSEnumerationOptions)opts passingTest:(BOOL (NS_NOESCAPE ^)(NSUInteger idx, BOOL *stop))predicate {
    __block NSUInteger found = NSNotFound;
    [self enumerateIndexesInRange:range options:opts usingBlock:^(NSUInteger idx, BOOL *stop) {
        BOOL outerStop = NO;
        BOOL matched = predicate(idx, &outerStop);
        if (matched) {
            found = idx;
            *stop = YES;
        } else if (outerStop) {
            *stop = YES;
        }
    }];
    return found;
}

- (NSIndexSet *)indexesPassingTest:(BOOL (NS_NOESCAPE ^)(NSUInteger idx, BOOL *stop))predicate {
    return [self indexesWithOptions:0 passingTest:predicate];
}

- (NSIndexSet *)indexesWithOptions:(NSEnumerationOptions)opts passingTest:(BOOL (NS_NOESCAPE ^)(NSUInteger idx, BOOL *stop))predicate {
    return [self indexesInRange:NSMakeRange(0, NSIntegerMax - 1) options:opts passingTest:predicate];
}

- (NSIndexSet *)indexesInRange:(NSRange)range options:(NSEnumerationOptions)opts passingTest:(BOOL (NS_NOESCAPE ^)(NSUInteger idx, BOOL *stop))predicate {
    NSMutableIndexSet *result = [NSMutableIndexSet indexSet];
    [self enumerateIndexesInRange:range options:opts usingBlock:^(NSUInteger idx, BOOL *stop) {
        BOOL outerStop = NO;
        if (predicate(idx, &outerStop)) {
            [result addIndex:idx];
        }
        if (outerStop) {
            *stop = YES;
        }
    }];
    return result;
}

- (void)encodeWithCoder:(NSCoder *)coder {
    if ([coder allowsKeyedCoding]) {
        [coder encodeInteger:(NSInteger)_length forKey:@"NS.length"];
        [coder encodeBytes:(const uint8_t *)_ranges length:_length * sizeof(NSRange) forKey:@"NS.ranges"];
    } else {
        [coder encodeValueOfObjCType:@encode(NSUInteger) at:&_length];
        [coder encodeBytes:(const uint8_t *)_ranges length:_length * sizeof(NSRange)];
    }
}

- (instancetype)initWithCoder:(NSCoder *)coder {
    self = [super init];
    if (self) {
        NSUInteger returnedLength = 0;
        const uint8_t *bytes = NULL;
        if ([coder allowsKeyedCoding]) {
            _length = (NSUInteger)[coder decodeIntegerForKey:@"NS.length"];
            bytes = [coder decodeBytesForKey:@"NS.ranges" returnedLength:&returnedLength];
        } else {
            [coder decodeValueOfObjCType:@encode(NSUInteger) at:&_length size:sizeof(NSUInteger)];
            bytes = [coder decodeBytesWithReturnedLength:&returnedLength];
        }
        NSUInteger wanted = _length * sizeof(NSRange);
        if (wanted > returnedLength) {
            wanted = returnedLength;
        }
        _capacity = _length ? _length : 1;
        _ranges = (NSRange *)calloc(_capacity, sizeof(NSRange));
        if (bytes && wanted > 0) {
            memcpy(_ranges, bytes, wanted);
        }
    }
    return self;
}

+ (BOOL)supportsSecureCoding {
    return YES;
}

- (NSString *)description {
    NSMutableString *result = [NSMutableString stringWithCapacity:0];
    [result appendFormat:@"<%@: %p>", [self class], self];
    if (_length == 0) {
        [result appendString:@"(no indexes)"];
        return result;
    }
    [result appendFormat:@"[number of indexes: %lu (in %lu ranges), indexes: (",
                (unsigned long)self.count, (unsigned long)_length];
    for (NSUInteger i = 0; i < _length; i++) {
        NSUInteger last = NSMaxRange(_ranges[i]) - 1;
        if (last == _ranges[i].location) {
            [result appendFormat:@"%lu", (unsigned long)_ranges[i].location];
        } else {
            [result appendFormat:@"%lu-%lu", (unsigned long)_ranges[i].location, (unsigned long)last];
        }
        if (i + 1 < _length) {
            [result appendString:@" "];
        }
    }
    [result appendString:@")]"];
    return result;
}

@end

/* ---- NSMutableIndexSet ---- */

@implementation NSMutableIndexSet

- (instancetype)init {
    return [self initWithIndexesInRange:NSMakeRange(0, 0)];
}

- (instancetype)initWithCapacity:(NSUInteger)capacity {
    self = [super init];
    if (self) {
        _length = 0;
        _capacity = capacity ? capacity : 1;
        _ranges = (NSRange *)calloc(_capacity, sizeof(NSRange));
    }
    return self;
}

- (instancetype)initWithIndexesInRange:(NSRange)range {
    self = [super initWithIndexesInRange:range];
    return self;
}

- (instancetype)initWithIndexSet:(NSIndexSet *)indexSet {
    self = [super initWithIndexSet:indexSet];
    return self;
}

- (id)copyWithZone:(NSZone *)zone {
    (void)zone;
    return [[NSIndexSet alloc] initWithIndexSet:self];
}

- (void)_insertRange:(NSRange)range atPosition:(NSUInteger)position {
    _ranges = NSISEnsureCapacity(_ranges, &_capacity, _length + 1);
    NSInteger i;
    for (i = (NSInteger)_length; i >= (NSInteger)position + 1; i--) {
        _ranges[i] = _ranges[i - 1];
    }
    _ranges[position] = range;
    _length++;
}

- (void)addIndexesInRange:(NSRange)range {
    if (range.length == 0) {
        return;
    }
    NSUInteger pos = NSISPositionLessThanOrEqualToLocation(_ranges, _length, range.location);
    BOOL insert = NO;

    if (pos == NSNotFound) {
        pos = 0;
        insert = YES;
    } else {
        if (NSMaxRange(range) <= NSMaxRange(_ranges[pos])) {
            return; /* fully present */
        }
        if (range.location <= NSMaxRange(_ranges[pos])) { /* intersects or is adjacent */
            _ranges[pos].length = NSMaxRange(range) - _ranges[pos].location;
        } else {
            pos++;
            insert = YES;
        }
    }

    if (insert) {
        [self _insertRange:range atPosition:pos];
    }

    while (pos + 1 < _length) {
        NSUInteger max = NSMaxRange(_ranges[pos]);
        if (max < _ranges[pos + 1].location) {
            break;
        }
        NSUInteger nextMax = NSMaxRange(_ranges[pos + 1]);
        if (nextMax > max) {
            _ranges[pos].length = nextMax - _ranges[pos].location;
        }
        NSISRemoveRangeAtPosition(_ranges, pos + 1, _length);
        _length--;
    }
}

- (void)addIndexes:(NSIndexSet *)indexSet {
    for (NSUInteger i = 0; i < indexSet->_length; i++) {
        [self addIndexesInRange:indexSet->_ranges[i]];
    }
}

- (void)addIndex:(NSUInteger)value {
    [self addIndexesInRange:NSMakeRange(value, 1)];
}

- (void)removeAllIndexes {
    _length = 0;
}

- (void)removeIndexesInRange:(NSRange)range {
    NSUInteger pos = NSISPositionLessThanOrEqualToLocation(_ranges, _length, range.location);
    if (pos == NSNotFound) {
        pos = 0;
    }

    while (range.length > 0 && pos < _length) {
        if (_ranges[pos].location >= NSMaxRange(range)) {
            break;
        }
        if (NSMaxRange(_ranges[pos]) == NSMaxRange(range)) {
            if (_ranges[pos].location == range.location) {
                NSISRemoveRangeAtPosition(_ranges, pos, _length);
                _length--;
            } else {
                _ranges[pos].length = range.location - _ranges[pos].location;
            }
            break;
        }
        if (NSMaxRange(_ranges[pos]) > NSMaxRange(range)) {
            if (_ranges[pos].location == range.location) {
                NSUInteger max = NSMaxRange(_ranges[pos]);
                _ranges[pos].location = NSMaxRange(range);
                _ranges[pos].length = max - _ranges[pos].location;
            } else {
                NSRange iceberg;
                iceberg.location = NSMaxRange(range);
                iceberg.length = NSMaxRange(_ranges[pos]) - iceberg.location;
                _ranges[pos].length = range.location - _ranges[pos].location;
                [self _insertRange:iceberg atPosition:pos + 1];
            }
            break;
        }
        if (range.location >= NSMaxRange(_ranges[pos])) {
            pos++;
        } else {
            NSUInteger max = NSMaxRange(range);
            NSRange temp = _ranges[pos];
            if (_ranges[pos].location >= range.location) {
                NSISRemoveRangeAtPosition(_ranges, pos, _length);
                _length--;
            } else {
                _ranges[pos].length = range.location - _ranges[pos].location;
                pos++;
            }
            range.location = NSMaxRange(temp);
            range.length = max - range.location;
        }
    }
}

- (void)removeIndexes:(NSIndexSet *)indexSet {
    for (NSUInteger i = 0; i < indexSet->_length; i++) {
        [self removeIndexesInRange:indexSet->_ranges[i]];
    }
}

- (void)removeIndex:(NSUInteger)value {
    [self removeIndexesInRange:NSMakeRange(value, 1)];
}

- (void)shiftIndexesStartingAtIndex:(NSUInteger)index by:(NSInteger)delta {
    if (delta < 0) {
        /* Deletion zone [index+delta, index) clamped to non-negative; indexes
         * at or above `index` shift down by delta, and any that fall below
         * zero are dropped. */
        NSUInteger drop = (NSUInteger)(-delta);
        NSUInteger zoneStart = (index >= drop) ? (index - drop) : 0;
        NSRange *tmp = (NSRange *)malloc((_length ? _length : 1) * sizeof(NSRange));
        NSUInteger count = 0;
        for (NSUInteger pos = 0; pos < _length; pos++) {
            NSRange current = _ranges[pos];
            NSUInteger max = NSMaxRange(current);
            if (max <= zoneStart) {
                tmp[count++] = current;
            } else if (current.location >= index) {
                NSUInteger start = (current.location >= drop) ? current.location - drop : 0;
                NSUInteger end = (max >= drop) ? max - drop : 0;
                if (end > start) {
                    tmp[count++] = NSMakeRange(start, end - start);
                }
            } else {
                /* [location, zoneStart) stays, [index, max) shifts to
                 * [zoneStart, max-drop); the two halves are adjacent. */
                NSUInteger tailEnd = (max > index && max > drop) ? max - drop : 0;
                if (zoneStart > current.location && tailEnd > zoneStart) {
                    tmp[count++] = NSMakeRange(current.location, tailEnd - current.location);
                } else if (zoneStart > current.location) {
                    tmp[count++] = NSMakeRange(current.location, zoneStart - current.location);
                } else if (tailEnd > zoneStart) {
                    tmp[count++] = NSMakeRange(zoneStart, tailEnd - zoneStart);
                }
            }
        }
        free(_ranges);
        _ranges = tmp;
        _length = count;
    } else if (delta > 0) {
        NSUInteger shift = (NSUInteger)delta;
        NSInteger pos = NSISPositionLessThanOrEqualToLocation(_ranges, _length, index);
        if (pos == NSNotFound) {
            return;
        }
        /* split a stored range that straddles the insertion point */
        if (_ranges[pos].location < index && index < NSMaxRange(_ranges[pos])) {
            NSRange below = _ranges[pos];
            below.length = index - below.location;
            _ranges[pos].length = NSMaxRange(_ranges[pos]) - index;
            _ranges[pos].location = index;
            [self _insertRange:below atPosition:pos];
        }
        NSInteger count = (NSInteger)_length;
        while (--count >= pos) {
            if (_ranges[count].location >= index) {
                _ranges[count].location += shift;
            }
        }
    } else {
        return;
    }
    NSISMergeAdjacent(_ranges, &_length);
}

@end