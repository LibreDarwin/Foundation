/*
 * Copyright (C) 2026, PureDarwin Project.
 *
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */

#import <Foundation/NSValue.h>
#import <Foundation/NSCoder.h>
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

/* The designated initialiser: copy the bytes and keep the type encoding, which
 * is what every factory funnels through and what -initWithCoder: ends at. */
- (instancetype)initWithBytes:(const void *)bytes objCType:(const char *)type {
    if (bytes == NULL || type == NULL) {
        [NSException raise:NSInvalidArgumentException
                    format:@"NSValue requires non-null bytes and objCType"];
    }

    if ((self = [super init]) != nil) {
        NSUInteger size = 0;
        NSGetSizeAndAlignment(type, &size, NULL);
        _size = size;
        _bytes = malloc(size);
        memcpy(_bytes, bytes, size);
        _type = strdup(type);
    }
    return self;
}

+ (instancetype)valueWithBytes:(const void *)bytes objCType:(const char *)type {
    return NSVALUE_TRANSFER([[self alloc] initWithBytes:bytes objCType:type]);
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
#if !__has_feature(objc_arc)
    [super dealloc];
#endif
}

- (void)getValue:(void *)buffer {
    if (buffer == NULL) {
        [NSException raise:NSInvalidArgumentException
                    format:@"NSValue getValue: requires a non-null buffer"];
    }
    memcpy(buffer, _bytes, _size);
}

/* The bounded form: write as much as fits. A caller asking for fewer bytes
 * than the value holds gets a truncated copy rather than an overrun; asking for
 * more leaves the tail of their buffer untouched, as Apple does. */
- (void)getValue:(void *)buffer size:(NSUInteger)size {
    if (buffer == NULL) {
        [NSException raise:NSInvalidArgumentException
                    format:@"NSValue getValue:size: requires a non-null buffer"];
    }
    memcpy(buffer, _bytes, size < _size ? size : _size);
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

- (BOOL)isEqualToValue:(NSValue *)value {
    if (value == nil || strcmp(_type, value->_type) != 0 || _size != value->_size) {
        return NO;
    }
    return memcmp(_bytes, value->_bytes, _size) == 0;
}

- (BOOL)isEqual:(id)other {
    if (![other isKindOfClass:[NSValue class]]) {
        return NO;
    }
    return [self isEqualToValue:(NSValue *)other];
}

- (NSUInteger)hash {
    NSUInteger hash = 5381;
    for (NSUInteger i = 0; i < _size; i++) {
        hash = ((hash << 5) + hash) ^ ((const unsigned char *)_bytes)[i];
    }
    return hash;
}

- (NSString *)description {
    NSMutableString *result = [NSMutableString string];
    [result appendFormat:@"{length = %lu, bytes = 0x", (unsigned long)_size];
    const unsigned char *byte = (const unsigned char *)_bytes;
    for (NSUInteger i = 0; i < _size; i++) {
        [result appendFormat:@"%02x", (unsigned int)byte[i]];
    }
    [result appendString:@"}"];
    return result;
}

/* Immutable: a copy is the same object, handed back owned. */
- (id)copyWithZone:(NSZone *)zone {
    (void)zone;
    return [self retain];
}

/* The archive carries the type encoding as a string next to the raw bytes, in
 * the keyed or the unkeyed slots so a coder that supports either can round-trip
 * a value. Decoding rebuilds through the designated initialiser, refusing a
 * byte count that disagrees with the type it is told to be. */
- (void)encodeWithCoder:(NSCoder *)coder {
    NSString *type = [NSString stringWithUTF8String:_type];
    if ([coder allowsKeyedCoding]) {
        [coder encodeObject:type forKey:@"NS.valueType"];
        [coder encodeBytes:_bytes length:_size forKey:@"NS.valueBytes"];
    } else {
        [coder encodeObject:type];
        [coder encodeBytes:_bytes length:_size];
    }
}

- (instancetype)initWithCoder:(NSCoder *)coder {
    NSString *type = nil;
    const uint8_t *bytes = NULL;
    NSUInteger length = 0;

    if ([coder allowsKeyedCoding]) {
        type = [coder decodeObjectForKey:@"NS.valueType"];
        bytes = [coder decodeBytesForKey:@"NS.valueBytes" returnedLength:&length];
    } else {
        type = [coder decodeObject];
        bytes = [coder decodeBytesWithReturnedLength:&length];
    }

    if (type == nil || bytes == NULL) return nil;

    NSUInteger expected = 0;
    NSGetSizeAndAlignment([type UTF8String], &expected, NULL);
    if (length != expected) return nil;

    return [self initWithBytes:bytes objCType:[type UTF8String]];
}

+ (BOOL)supportsSecureCoding {
    return YES;
}

@end
