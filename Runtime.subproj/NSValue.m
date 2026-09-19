/*
 * Copyright (C) 2026, PureDarwin Project.
 *
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */

#import <Foundation/NSValue.h>
#import <Foundation/NSException.h>
#import <Foundation/NSString.h>
#include <CoreFoundation/CFString.h>
#include <stdlib.h>
#include <string.h>

#if __has_feature(objc_arc)
#define NSVALUE_TRANSFER(value) (__bridge_transfer id)(value)
#else
#define NSVALUE_TRANSFER(value) [(id)(value) autorelease]
#endif

static void NSValueRequireType(const char *actualType, const char *expectedType,
                               const char *accessor) {
    if (strcmp(actualType, expectedType) != 0) {
        [NSException raise:NSInvalidArgumentException
                    format:@"%s cannot be used with NSValue type %s",
                           accessor, actualType];
    }
}

@implementation NSValue {
    void *_bytes;
    NSUInteger _size;
    char *_type;
}

+ (instancetype)valueWithBytes:(const void *)bytes objCType:(const char *)type {
    if (bytes == NULL || type == NULL) {
        [NSException raise:NSInvalidArgumentException
                    format:@"NSValue requires non-null bytes and objCType"];
    }

    NSUInteger size = 0;
    NSGetSizeAndAlignment(type, &size, NULL);

    NSValue *value = [[self alloc] init];
    if (value != nil) {
        value->_size = size;
        value->_bytes = malloc(size);
        memcpy(value->_bytes, bytes, size);
        value->_type = strdup(type);
    }
    return value;
}

+ (instancetype)value:(const void *)bytes withObjCType:(const char *)type {
    return [self valueWithBytes:bytes objCType:type];
}

+ (instancetype)valueWithPointer:(const void *)pointer {
    return [self valueWithBytes:&pointer objCType:@encode(void *)];
}

+ (instancetype)valueWithNonretainedObject:(id)object {
    return [self valueWithBytes:&object objCType:@encode(id)];
}

+ (instancetype)valueWithRange:(NSRange)range {
    return [self valueWithBytes:&range objCType:@encode(NSRange)];
}

+ (instancetype)valueWithPoint:(NSPoint)point {
    return [self valueWithBytes:&point objCType:@encode(NSPoint)];
}

+ (instancetype)valueWithSize:(NSSize)size {
    return [self valueWithBytes:&size objCType:@encode(NSSize)];
}

+ (instancetype)valueWithRect:(NSRect)rect {
    return [self valueWithBytes:&rect objCType:@encode(NSRect)];
}

- (void)dealloc {
    free(_bytes);
    free(_type);
}

- (void)getValue:(void *)buffer {
    if (buffer == NULL) {
        [NSException raise:NSInvalidArgumentException
                    format:@"NSValue getValue: requires a non-null buffer"];
    }
    memcpy(buffer, _bytes, _size);
}

- (const char *)objCType {
    return _type;
}

- (void *)pointerValue {
    NSValueRequireType(_type, @encode(void *), "pointerValue");
    void *pointer = NULL;
    [self getValue:&pointer];
    return pointer;
}

- (id)nonretainedObjectValue {
    NSValueRequireType(_type, @encode(id), "nonretainedObjectValue");
    id object = nil;
    [self getValue:&object];
    return object;
}

- (NSRange)rangeValue {
    NSValueRequireType(_type, @encode(NSRange), "rangeValue");
    NSRange range;
    [self getValue:&range];
    return range;
}

- (NSPoint)pointValue {
    NSValueRequireType(_type, @encode(NSPoint), "pointValue");
    NSPoint point;
    [self getValue:&point];
    return point;
}

- (NSSize)sizeValue {
    NSValueRequireType(_type, @encode(NSSize), "sizeValue");
    NSSize size;
    [self getValue:&size];
    return size;
}

- (NSRect)rectValue {
    NSValueRequireType(_type, @encode(NSRect), "rectValue");
    NSRect rect;
    [self getValue:&rect];
    return rect;
}

- (BOOL)isEqual:(id)other {
    if (![other isKindOfClass:[NSValue class]]) {
        return NO;
    }

    NSValue *value = (NSValue *)other;
    if (strcmp(_type, value->_type) != 0 || _size != value->_size) {
        return NO;
    }
    return memcmp(_bytes, value->_bytes, _size) == 0;
}

- (NSUInteger)hash {
    NSUInteger hash = 5381;
    for (NSUInteger i = 0; i < _size; i++) {
        hash = ((hash << 5) + hash) ^ ((const unsigned char *)_bytes)[i];
    }
    return hash;
}

- (NSString *)description {
    return NSVALUE_TRANSFER(CFStringCreateWithFormat(kCFAllocatorDefault, NULL,
                                                      CFSTR("<NSValue %s>"), _type));
}

@end
