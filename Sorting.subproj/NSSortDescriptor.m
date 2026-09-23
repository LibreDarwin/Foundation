/*
 * Copyright (C) 2026, Samuel Zormeister.
 *
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */

#import <Foundation/NSSortDescriptor.h>
#import <Foundation/NSDictionary.h>
#import <Foundation/NSString.h>
#import <Foundation/NSKeyValueCoding.h>
#include <objc/message.h>

@implementation NSSortDescriptor

+ (instancetype)sortDescriptorWithKey:(NSString *)key ascending:(BOOL)ascending {
    return [[[self class] alloc] initWithKey:key ascending:ascending];
}

+ (instancetype)sortDescriptorWithKey:(NSString *)key ascending:(BOOL)ascending selector:(SEL)selector {
    return [[[self class] alloc] initWithKey:key ascending:ascending selector:selector];
}

+ (instancetype)sortDescriptorWithKey:(NSString *)key ascending:(BOOL)ascending comparator:(NSComparator)comparator {
    return [[[self class] alloc] initWithKey:key ascending:ascending comparator:comparator];
}

- (instancetype)initWithKey:(NSString *)key ascending:(BOOL)ascending {
    self = [super init];
    if (self != nil) {
        _key = [key copy];
        _ascending = ascending;
        _selector = @selector(compare:);
        _selectorOrBlock = nil;
        _explicitSelector = 0;
        _reverseNullOrder = 0;
    }
    return self;
}

- (instancetype)initWithKey:(NSString *)key ascending:(BOOL)ascending selector:(SEL)selector {
    self = [super init];
    if (self != nil) {
        _key = [key copy];
        _ascending = ascending;
        _selector = selector;
        _selectorOrBlock = nil;
        _explicitSelector = (selector != NULL);
        _reverseNullOrder = 0;
    }
    return self;
}

- (instancetype)initWithKey:(NSString *)key ascending:(BOOL)ascending comparator:(NSComparator)comparator {
    self = [super init];
    if (self != nil) {
        _key = [key copy];
        _ascending = ascending;
        _selector = NULL;
        _selectorOrBlock = [comparator copy];
        _explicitSelector = 0;
        _reverseNullOrder = 0;
    }
    return self;
}

- (NSString *)key {
    return _key;
}

- (BOOL)ascending {
    return _ascending;
}

- (SEL)selector {
    return _selectorOrBlock != nil ? NULL : _selector;
}

- (NSComparator)comparator {
    return _selectorOrBlock;
}

- (void)allowEvaluation {
    /* A decoded descriptor starts out refusing to be evaluated; a freshly
     * created one is already unlocked, so this is normally a no-op. */
}

- (BOOL)reverseNullOrder {
    return _reverseNullOrder != 0;
}

- (NSComparisonResult)compareObject:(id)object1 toObject:(id)object2 {
    id target1 = object1;
    id target2 = object2;
    if (_key != nil) {
        target1 = [object1 valueForKeyPath:_key];
        target2 = [object2 valueForKeyPath:_key];
    }
    NSComparisonResult result;
    if (_selectorOrBlock != nil) {
        result = _selectorOrBlock(target1, target2);
    } else if (_selector != NULL) {
        NSComparisonResult (*fn)(id, SEL, id) = (NSComparisonResult (*)(id, SEL, id))objc_msgSend;
        result = fn(target1, _selector, target2);
    } else {
        result = NSOrderedSame;
    }
    if (!_ascending) {
        result = -result;
    }
    return result;
}

- (instancetype)reversedSortDescriptor {
    NSSortDescriptor *reversed;
    if (_selectorOrBlock != nil) {
        reversed = [[NSSortDescriptor alloc] initWithKey:_key ascending:!_ascending comparator:_selectorOrBlock];
    } else if (_explicitSelector) {
        reversed = [[NSSortDescriptor alloc] initWithKey:_key ascending:!_ascending selector:_selector];
    } else {
        reversed = [[NSSortDescriptor alloc] initWithKey:_key ascending:!_ascending];
    }
    reversed->_reverseNullOrder = !_reverseNullOrder;
    return reversed;
}

- (BOOL)isEqual:(id)object {
    if (object == self) {
        return YES;
    }
    if (![object isKindOfClass:[NSSortDescriptor class]]) {
        return NO;
    }
    NSSortDescriptor *other = object;
    if (_selectorOrBlock != nil || other->_selectorOrBlock != nil) {
        return NO;
    }
    if (_explicitSelector != other->_explicitSelector) {
        return NO;
    }
    if (_explicitSelector && _selector != other->_selector) {
        return NO;
    }
    if (_key != other->_key && ![_key isEqual:other->_key]) {
        return NO;
    }
    if (_ascending != other->_ascending) {
        return NO;
    }
    return YES;
}

- (id)copyWithZone:(NSZone *)zone {
    (void)zone;
    return self;
}

- (void)encodeWithCoder:(NSCoder *)coder {
    if (_key != nil) [coder encodeObject:_key forKey:@"NSKey"];
    [coder encodeBool:_ascending forKey:@"NSAscending"];
    [coder encodeBool:(_reverseNullOrder != 0) forKey:@"NSReverseNullOrder"];
}

- (instancetype)initWithCoder:(NSCoder *)coder {
    /* Apple also archives the selector under "NSSelector"; this port has no
     * selector<string> runtime helper in the gate, and no keyed archiver, so
     * the round-trip restores the default compare:. */
    NSString *key = [coder decodeObjectForKey:@"NSKey"];
    BOOL ascending = [coder decodeBoolForKey:@"NSAscending"];
    self = [self initWithKey:key ascending:ascending];
    if (self != nil) {
        _reverseNullOrder = [coder decodeBoolForKey:@"NSReverseNullOrder"] ? 1 : 0;
    }
    return self;
}

+ (BOOL)supportsSecureCoding {
    return YES;
}

@end