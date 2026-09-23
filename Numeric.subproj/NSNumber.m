/*
 * Copyright (C) 2026, Samuel Zormeister.
 *
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */

#import <Foundation/NSNumber.h>
#import <Foundation/NSCoder.h>
#import <Foundation/NSString.h>
#include <CoreFoundation/CFString.h>
#include <CoreFoundation/CFNumber.h>
#include <CoreFoundation/ForFoundationOnly.h>
#include <stdint.h>
#include <stdio.h>

/* Every constructor here is a class convenience method, so the result must be
 * autoreleased - a boxed @(x) under ARC is released by its caller. */
static id
__NSNumberCreate(CFNumberType type, const void *value)
{
    CFNumberRef result = CFNumberCreate(kCFAllocatorDefault, type, value);
    return (id)CFAutorelease(result);
}

/* CFNumber has no boolean storage of its own; kCFBooleanTrue/False are the
 * canonical bridged objects and are what a CFDictionary round-trips. */
@implementation NSNumber

+ (instancetype)numberWithChar:(char)value {
    return __NSNumberCreate(kCFNumberCharType, &value);
}

+ (instancetype)numberWithUnsignedChar:(unsigned char)value {
    short widened = value;
    return __NSNumberCreate(kCFNumberShortType, &widened);
}

+ (instancetype)numberWithShort:(short)value {
    return __NSNumberCreate(kCFNumberShortType, &value);
}

+ (instancetype)numberWithUnsignedShort:(unsigned short)value {
    int widened = value;
    return __NSNumberCreate(kCFNumberIntType, &widened);
}

+ (instancetype)numberWithInt:(int)value {
    return __NSNumberCreate(kCFNumberIntType, &value);
}

+ (instancetype)numberWithUnsignedInt:(unsigned int)value {
    long long widened = value;
    return __NSNumberCreate(kCFNumberLongLongType, &widened);
}

+ (instancetype)numberWithLong:(long)value {
    return __NSNumberCreate(kCFNumberLongType, &value);
}

/* An unsigned long past LLONG_MAX cannot be represented; CFNumber is signed
 * throughout, so it wraps, exactly as Foundation's own NSNumber does. */
+ (instancetype)numberWithUnsignedLong:(unsigned long)value {
    long long widened = (long long)value;
    return __NSNumberCreate(kCFNumberLongLongType, &widened);
}

+ (instancetype)numberWithLongLong:(long long)value {
    return __NSNumberCreate(kCFNumberLongLongType, &value);
}

+ (instancetype)numberWithUnsignedLongLong:(unsigned long long)value {
    long long widened = (long long)value;
    return __NSNumberCreate(kCFNumberLongLongType, &widened);
}

+ (instancetype)numberWithFloat:(float)value {
    return __NSNumberCreate(kCFNumberFloatType, &value);
}

+ (instancetype)numberWithDouble:(double)value {
    return __NSNumberCreate(kCFNumberDoubleType, &value);
}

+ (instancetype)numberWithBool:(BOOL)value {
    return (id)(value ? kCFBooleanTrue : kCFBooleanFalse);
}

+ (instancetype)numberWithInteger:(NSInteger)value {
    return __NSNumberCreate(kCFNumberNSIntegerType, &value);
}

+ (instancetype)numberWithUnsignedInteger:(NSUInteger)value {
    long long widened = (long long)value;
    return __NSNumberCreate(kCFNumberLongLongType, &widened);
}

/* NSNumber is immutable and CF-backed, so -init cannot fill in self: each
 * initialiser mints a fresh CF number in place of the +alloc result, the same
 * swap NSDate uses. Keeping the pairing mechanical means the two spellings of
 * every constructor cannot drift apart. */
#define __NSNUMBER_INIT(name, type)                          \
    - (instancetype)initWith##name:(type)value {             \
        return [[self class] numberWith##name:value];        \
    }

__NSNUMBER_INIT(Char, char)
__NSNUMBER_INIT(UnsignedChar, unsigned char)
__NSNUMBER_INIT(Short, short)
__NSNUMBER_INIT(UnsignedShort, unsigned short)
__NSNUMBER_INIT(Int, int)
__NSNUMBER_INIT(UnsignedInt, unsigned int)
__NSNUMBER_INIT(Long, long)
__NSNUMBER_INIT(UnsignedLong, unsigned long)
__NSNUMBER_INIT(LongLong, long long)
__NSNUMBER_INIT(UnsignedLongLong, unsigned long long)
__NSNUMBER_INIT(Float, float)
__NSNUMBER_INIT(Double, double)
__NSNUMBER_INIT(Bool, BOOL)
__NSNUMBER_INIT(Integer, NSInteger)
__NSNUMBER_INIT(UnsignedInteger, NSUInteger)

/* -init on Apple hands back nil, not a zeroed number, so return nil rather
 * than minting an empty number that every other method would trip over. */
- (instancetype)init {
    return nil;
}

/* CFNumberGetValue converts, and reports false when the value did not fit.
 * The result is still the truncated conversion, which is what NSNumber
 * promises for a lossy read, so the return value is deliberately ignored. */
#define __NSNUMBER_GETTER(name, type, cfType)                       \
    - (type)name {                                                  \
        type result = 0;                                            \
        CFNumberGetValue((CFNumberRef)self, cfType, &result);       \
        return result;                                              \
    }

__NSNUMBER_GETTER(charValue, char, kCFNumberCharType)
__NSNUMBER_GETTER(shortValue, short, kCFNumberShortType)
__NSNUMBER_GETTER(intValue, int, kCFNumberIntType)
__NSNUMBER_GETTER(longValue, long, kCFNumberLongType)
__NSNUMBER_GETTER(longLongValue, long long, kCFNumberLongLongType)
__NSNUMBER_GETTER(floatValue, float, kCFNumberFloatType)
__NSNUMBER_GETTER(doubleValue, double, kCFNumberDoubleType)
__NSNUMBER_GETTER(integerValue, NSInteger, kCFNumberNSIntegerType)

- (unsigned char)unsignedCharValue {
    return (unsigned char)[self charValue];
}

- (unsigned short)unsignedShortValue {
    return (unsigned short)[self shortValue];
}

- (unsigned int)unsignedIntValue {
    return (unsigned int)[self intValue];
}

- (unsigned long)unsignedLongValue {
    return (unsigned long)[self longValue];
}

- (unsigned long long)unsignedLongLongValue {
    return (unsigned long long)[self longLongValue];
}

- (NSUInteger)unsignedIntegerValue {
    return (NSUInteger)[self integerValue];
}

/* The text of a number is its value, with no locale or grouping -- that is
 * what Apple's -stringValue gives and what -description forwards to. Writing
 * it out by hand rather than through CFCopyDescription: CFNumber's description
 * is not the bare value on every CF implementation. */
- (NSString *)stringValue {
    char type = [self objCType][0];
    char buffer[32];
    if (type == 'f' || type == 'd')
        snprintf(buffer, sizeof(buffer), "%.*g", type == 'f' ? 7 : 16, [self doubleValue]);
    else
        snprintf(buffer, sizeof(buffer), "%lld", [self longLongValue]);
    CFStringRef result = CFStringCreateWithCString(kCFAllocatorDefault, buffer, kCFStringEncodingUTF8);
    return (NSString *)CFAutorelease(result);
}

/* Apple's -description for a number is its bare value, i.e. -stringValue. */
- (NSString *)description {
    return [self stringValue];
}

- (BOOL)boolValue {
    return [self longLongValue] != 0;
}

- (const char *)objCType {
    /* CFNumberGetType hands back the canonical storage type, not the one the
     * number was created with: kCFNumberIntType reads back as kCFNumberSInt32Type
     * and kCFNumberLongLongType as kCFNumberSInt64Type. Both spellings are
     * enumerated so the answer is the same either way. */
    if (CFGetTypeID((CFTypeRef)self) == CFBooleanGetTypeID()) return @encode(BOOL);
    switch (CFNumberGetType((CFNumberRef)self)) {
        case kCFNumberCharType: return @encode(char);
        case kCFNumberShortType: return @encode(short);
        case kCFNumberIntType: return @encode(int);
        case kCFNumberLongType: return @encode(long);
        case kCFNumberLongLongType: return @encode(long long);
        case kCFNumberFloatType: return @encode(float);
        case kCFNumberDoubleType: return @encode(double);
        case kCFNumberCFIndexType: return @encode(CFIndex);
        case kCFNumberNSIntegerType: return @encode(NSInteger);
        case kCFNumberSInt8Type: return @encode(int8_t);
        case kCFNumberSInt16Type: return @encode(int16_t);
        case kCFNumberSInt32Type: return @encode(int32_t);
        case kCFNumberSInt64Type: return @encode(int64_t);
        case kCFNumberFloat32Type: return @encode(float);
        case kCFNumberFloat64Type: return @encode(double);
        default: return @encode(double);
    }
}

- (NSComparisonResult)compare:(NSNumber *)number {
    if (number == nil) return NSOrderedDescending;
    if (![number respondsToSelector:@selector(decimalValue)] &&
        CFGetTypeID((CFTypeRef)number) == CFNumberGetTypeID()) {
        return (NSComparisonResult)CFNumberCompare((CFNumberRef)self, (CFNumberRef)number, NULL);
    }
    double left = [self doubleValue];
    double right = [number doubleValue];
    return left < right ? NSOrderedAscending : left > right ? NSOrderedDescending : NSOrderedSame;
}

- (BOOL)isEqualToNumber:(NSNumber *)number {
    return number != nil && [self compare:number] == NSOrderedSame;
}

/* NSNumber overrides -isEqual: so that two boxed values of the same magnitude
 * compare equal across the integer/float types (-compare: is numeric), while a
 * boxed BOOL is equal only to another BOOL -- @YES is -isEqual:@1 false, as on
 * Apple -- and anything that is not a number is unequal. The test is by CF type
 * rather than -isKindOfClass: because every NSNumber is a CF number and the
 * runtime's NSNumber can be CoreFoundation's. */
- (BOOL)isEqual:(id)other {
    if (other == self) return YES;
    if (other == nil) return NO;
    CFTypeID mine = CFGetTypeID((CFTypeRef)self);
    CFTypeID theirs = CFGetTypeID((CFTypeRef)other);
    if (mine == CFBooleanGetTypeID() || theirs == CFBooleanGetTypeID())
        return mine == theirs;
    if (mine != CFNumberGetTypeID() || theirs != CFNumberGetTypeID()) return NO;
    return [self isEqualToNumber:other];
}

- (NSUInteger)hash {
    return (NSUInteger)CFHash((CFTypeRef)self);
}

/* Immutable, so a copy is the same object. */
- (id)copyWithZone:(NSZone *)zone {
    (void)zone;
    return self;
}

- (NSString *)descriptionWithLocale:(id)locale {
    (void)locale;
    return [self stringValue];
}

/* The archive has to carry the type as well as the magnitude: -objCType is the
 * only thing that distinguishes 1 from 1.0, and it is what Apple's NSCoder
 * keys a number by. The leading byte is stored alongside the value, and the
 * value goes through an int64 for every integer type (a bit pattern, so an
 * unsigned value past INT64_MAX survives) or a double for the two float types.
 */
- (void)encodeWithCoder:(NSCoder *)coder {
    /* A boolean's -objCType is 'c', same as a char, so the only way to keep a
     * boxed BOOL a boolean across the round trip is to tag it by identity. */
    char type = CFGetTypeID((CFTypeRef)self) == CFBooleanGetTypeID()
              ? 'B' : [self objCType][0];
    if ([coder allowsKeyedCoding]) {
        [coder encodeInteger:(NSInteger)type forKey:@"NS.numberType"];
        switch (type) {
            case 'f':
            case 'd':
                [coder encodeDouble:[self doubleValue] forKey:@"NS.number"];
                break;
            default:
                [coder encodeInt64:(int64_t)[self longLongValue] forKey:@"NS.number"];
                break;
        }
    } else {
        [coder encodeValueOfObjCType:@encode(char) at:&type];
        switch (type) {
            case 'f':
            case 'd': {
                double value = [self doubleValue];
                [coder encodeValueOfObjCType:@encode(double) at:&value];
                break;
            }
            default: {
                int64_t value = (int64_t)[self longLongValue];
                [coder encodeValueOfObjCType:@encode(int64_t) at:&value];
                break;
            }
        }
    }
}

- (instancetype)initWithCoder:(NSCoder *)coder {
    char type = 0;
    int64_t integer = 0;
    double floating = 0;

    if ([coder allowsKeyedCoding]) {
        type = (char)[coder decodeIntegerForKey:@"NS.numberType"];
        if (type == 'f' || type == 'd') {
            floating = [coder decodeDoubleForKey:@"NS.number"];
        } else {
            integer = [coder decodeInt64ForKey:@"NS.number"];
        }
    } else {
        [coder decodeValueOfObjCType:@encode(char) at:&type size:sizeof(char)];
        if (type == 'f' || type == 'd') {
            [coder decodeValueOfObjCType:@encode(double) at:&floating size:sizeof(double)];
        } else {
            [coder decodeValueOfObjCType:@encode(int64_t) at:&integer size:sizeof(int64_t)];
        }
    }

    switch (type) {
        case 'c': return [[self class] numberWithChar:(char)integer];
        case 'C': return [[self class] numberWithUnsignedChar:(unsigned char)integer];
        case 's': return [[self class] numberWithShort:(short)integer];
        case 'S': return [[self class] numberWithUnsignedShort:(unsigned short)integer];
        case 'i': return [[self class] numberWithInt:(int)integer];
        case 'I': return [[self class] numberWithUnsignedInt:(unsigned int)integer];
        case 'l': return [[self class] numberWithLong:(long)integer];
        case 'L': return [[self class] numberWithUnsignedLong:(unsigned long)integer];
        case 'q': return [[self class] numberWithLongLong:(long long)integer];
        case 'Q': return [[self class] numberWithUnsignedLongLong:(unsigned long long)integer];
        case 'f': return [[self class] numberWithFloat:(float)floating];
        case 'd': return [[self class] numberWithDouble:floating];
        case 'B': return [[self class] numberWithBool:integer != 0];
        default: return [[self class] numberWithLongLong:(long long)integer];
    }
}

+ (BOOL)supportsSecureCoding {
    return YES;
}

@end

#if DEPLOYMENT_RUNTIME_OBJC
__attribute__((constructor))
static void __NSCFNumberBridgeInit(void) {
    _CFRuntimeBridgeClasses(CFNumberGetTypeID(), "NSNumber");
}
#endif
