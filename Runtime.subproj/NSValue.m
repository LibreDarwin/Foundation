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
#import <Foundation/NSNumber.h>
#import <Foundation/NSString.h>
#include <CoreFoundation/CFString.h>
#include <objc/runtime.h>
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

/* NSValue is a genuine port class, not a CF cluster, so +class is left alone
 * here: pointing it at the runtime's NSValue would make -isEqual: compare a
 * port instance against a class it is not an instance of, and same-content
 * values would stop comparing equal. */

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

/* _SpecialForType names the struct types Foundation describes by name; it is
 * defined below with the archiving code that shares the same classification. */
static NSInteger _SpecialForType(const char *type);

/* Apple names the four geometry structs it knows and falls back to the raw
 * byte dump for everything else -- an int value really does describe as
 * "{length = 4, bytes = 0x05000000}".  A range describes as
 * "NSRange: {3, 8}", with the location and length separated by a space. */
- (NSString *)description {
    switch (_SpecialForType(_type)) {
        case _NSValueSpecialRange: {
            NSRange range;
            memcpy(&range, _bytes, sizeof range);
            return [NSString stringWithFormat:@"NSRange: {%lu, %lu}",
                    (unsigned long)range.location, (unsigned long)range.length];
        }
        case _NSValueSpecialPoint: {
            NSPoint point;
            memcpy(&point, _bytes, sizeof point);
            return [NSString stringWithFormat:@"NSPoint: {%g, %g}",
                    (double)point.x, (double)point.y];
        }
        case _NSValueSpecialSize: {
            NSSize size;
            memcpy(&size, _bytes, sizeof size);
            return [NSString stringWithFormat:@"NSSize: {%g, %g}",
                    (double)size.width, (double)size.height];
        }
        case _NSValueSpecialRect: {
            NSRect rect;
            memcpy(&rect, _bytes, sizeof rect);
            return [NSString stringWithFormat:@"NSRect: {{%g, %g}, {%g, %g}}",
                    (double)rect.origin.x, (double)rect.origin.y,
                    (double)rect.size.width, (double)rect.size.height];
        }
        case _NSValueSpecialNone:
            break;
    }
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

/* Foundation does not archive a geometry value as an opaque blob of bytes.  It
 * recognises the handful of struct types the old Foundation defined, gives each
 * a small number in the "NS.special" slot, and writes the fields out under
 * names derived from the type -- an NSRange becomes NS.rangeval.location and
 * NS.rangeval.length rather than sixteen anonymous bytes.  Each field is
 * written as an object, so it lands in the archive's object table like any
 * other value, and NS.special is written as a plain integer.  Anything outside
 * that set keeps the generic type-plus-bytes form, which is what this port has
 * always written and what its own older archives contain. */
enum {
    _NSValueSpecialNone = 0,
    _NSValueSpecialPoint = 1,
    _NSValueSpecialSize = 2,
    _NSValueSpecialRect = 3,
    _NSValueSpecialRange = 4,
};

static NSInteger _SpecialForType(const char *type) {
    if (type == NULL) {
        return _NSValueSpecialNone;
    }
    /* The struct tags moved from NSPoint/NSSize/NSRect to the CoreGraphics
     * spellings when those types were adopted, so both are accepted. */
    if (strcmp(type, "{_NSRange=QQ}") == 0) {
        return _NSValueSpecialRange;
    }
    if (strncmp(type, "{NSPoint=", 9) == 0 || strncmp(type, "{CGPoint=", 9) == 0) {
        return _NSValueSpecialPoint;
    }
    if (strncmp(type, "{NSSize=", 8) == 0 || strncmp(type, "{CGSize=", 8) == 0) {
        return _NSValueSpecialSize;
    }
    if (strncmp(type, "{NSRect=", 8) == 0 || strncmp(type, "{CGRect=", 8) == 0) {
        return _NSValueSpecialRect;
    }
    return _NSValueSpecialNone;
}

/* The archive carries the type encoding as a string next to the raw bytes, in
 * the keyed or the unkeyed slots so a coder that supports either can round-trip
 * a value. Decoding rebuilds through the designated initialiser, refusing a
 * byte count that disagrees with the type it is told to be. */
- (void)encodeWithCoder:(NSCoder *)coder {
    if ([coder allowsKeyedCoding]) {
        NSInteger special = _SpecialForType(_type);
        if (special != _NSValueSpecialNone) {
            switch (special) {
                case _NSValueSpecialRange: {
                    NSRange range;
                    memcpy(&range, _bytes, sizeof range);
                    /* Order is part of the bytes: length, then location, then
                     * the tag, with $class added afterwards by the archiver. */
                    [coder encodeObject:@(range.length) forKey:@"NS.rangeval.length"];
                    [coder encodeObject:@(range.location) forKey:@"NS.rangeval.location"];
                    [coder encodeInt:special forKey:@"NS.special"];
                    return;
                }
                case _NSValueSpecialPoint: {
                    double xy[2];
                    memcpy(xy, _bytes, sizeof xy);
                    [coder encodeObject:@(xy[0]) forKey:@"NS.pointval.x"];
                    [coder encodeObject:@(xy[1]) forKey:@"NS.pointval.y"];
                    [coder encodeInt:special forKey:@"NS.special"];
                    return;
                }
                case _NSValueSpecialSize: {
                    double wh[2];
                    memcpy(wh, _bytes, sizeof wh);
                    [coder encodeObject:@(wh[0]) forKey:@"NS.sizeval.width"];
                    [coder encodeObject:@(wh[1]) forKey:@"NS.sizeval.height"];
                    [coder encodeInt:special forKey:@"NS.special"];
                    return;
                }
                case _NSValueSpecialRect: {
                    double v[4];
                    memcpy(v, _bytes, sizeof v);
                    [coder encodeObject:@(v[0]) forKey:@"NS.rectval.origin.x"];
                    [coder encodeObject:@(v[1]) forKey:@"NS.rectval.origin.y"];
                    [coder encodeObject:@(v[2]) forKey:@"NS.rectval.size.width"];
                    [coder encodeObject:@(v[3]) forKey:@"NS.rectval.size.height"];
                    [coder encodeInt:special forKey:@"NS.special"];
                    return;
                }
                default:
                    break;
            }
        }
    }

    NSString *type = [NSString stringWithUTF8String:_type];
    if ([coder allowsKeyedCoding]) {
        [coder encodeObject:type forKey:@"NS.valueType"];
        [coder encodeBytes:_bytes length:_size forKey:@"NS.valueBytes"];
    } else {
        [coder encodeObject:type];
        [coder encodeBytes:_bytes length:_size];
    }
}

/* Reads the field-named form for the recognised struct types.  Returns NO when
 * the archive does not carry one, which leaves the caller to try the generic
 * form. */
- (BOOL)_decodeSpecialWithCoder:(NSCoder *)coder {
    if (![coder allowsKeyedCoding]) {
        return NO;
    }
    /* Ask whether the tag is there before reading anything: a keyed coder
     * treats a read of a key the archive never wrote as a failure, so probing
     * for it by decoding would poison an archive that uses the generic form. */
    if (![coder containsValueForKey:@"NS.special"]) {
        return NO;
    }
    NSInteger special = [coder decodeIntForKey:@"NS.special"];
    if (special == _NSValueSpecialNone) {
        return NO;
    }

    switch (special) {
        case _NSValueSpecialRange: {
            NSNumber *length = [coder decodeObjectForKey:@"NS.rangeval.length"];
            NSNumber *location = [coder decodeObjectForKey:@"NS.rangeval.location"];
            if (length == nil || location == nil) {
                return NO;
            }
            return [self initWithBytes:&(NSRange){[location unsignedIntegerValue],
                                                 [length unsignedIntegerValue]}
                              objCType:"{_NSRange=QQ}"] != nil;
        }
        case _NSValueSpecialPoint: {
            NSNumber *x = [coder decodeObjectForKey:@"NS.pointval.x"];
            NSNumber *y = [coder decodeObjectForKey:@"NS.pointval.y"];
            if (x == nil || y == nil) {
                return NO;
            }
            double v[2] = {[x doubleValue], [y doubleValue]};
            return [self initWithBytes:v objCType:"{NSPoint=dd}"] != nil;
        }
        case _NSValueSpecialSize: {
            NSNumber *w = [coder decodeObjectForKey:@"NS.sizeval.width"];
            NSNumber *h = [coder decodeObjectForKey:@"NS.sizeval.height"];
            if (w == nil || h == nil) {
                return NO;
            }
            double v[2] = {[w doubleValue], [h doubleValue]};
            return [self initWithBytes:v objCType:"{NSSize=dd}"] != nil;
        }
        case _NSValueSpecialRect: {
            NSNumber *ox = [coder decodeObjectForKey:@"NS.rectval.origin.x"];
            NSNumber *oy = [coder decodeObjectForKey:@"NS.rectval.origin.y"];
            NSNumber *sw = [coder decodeObjectForKey:@"NS.rectval.size.width"];
            NSNumber *sh = [coder decodeObjectForKey:@"NS.rectval.size.height"];
            if (ox == nil || oy == nil || sw == nil || sh == nil) {
                return NO;
            }
            double v[4] = {[ox doubleValue], [oy doubleValue], [sw doubleValue], [sh doubleValue]};
            return [self initWithBytes:v objCType:"{NSRect=}"] != nil;
        }
        default:
            return NO;
    }
}

- (instancetype)initWithCoder:(NSCoder *)coder {
    if ([self _decodeSpecialWithCoder:coder]) {
        return self;
    }

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
