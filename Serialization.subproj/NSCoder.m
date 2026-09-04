/*
 * Copyright (C) 2026, Sunneva N. Mariu.
 *
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */

#import <Foundation/NSCoder.h>
#import <Foundation/FoundationErrors.h>
#import <Foundation/NSArray.h>
#import <Foundation/NSData.h>
#import <Foundation/NSDate.h>
#import <Foundation/NSDictionary.h>
#import <Foundation/NSError.h>
#import <Foundation/NSException.h>
#import <Foundation/NSNull.h>
#import <Foundation/NSNumber.h>
#import <Foundation/NSString.h>
#include <CoreFoundation/CFSet.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

/* An unimplemented primitive.  Apple words this two ways: sending it to
 * NSCoder itself is a caller's mistake, while a subclass reaching here has
 * simply not finished the job.  Both are NSInvalidArgumentException. */
static void _NSCoderAbstract(NSCoder *coder, SEL sel) {
    NSString *selector = NSStringFromSelector(sel);
    NSString *className = NSStringFromClass([coder class]);

    if ([coder class] == [NSCoder class]) {
        [NSException raise:NSInvalidArgumentException
                    format:@"*** -%@ cannot be sent to an abstract object of"
                            " class %@: Create a concrete instance!",
                           selector, className];
    }
    [NSException raise:NSInvalidArgumentException
                format:@"*** -%@ only defined for abstract class."
                        "  Define -[%@ %@]!",
                       selector, className, selector];
}

/* A keyed method on a coder that answers NO to -allowsKeyedCoding. */
static void _NSCoderRequiresKeyedCoding(NSCoder *coder, SEL sel) {
    if ([coder class] == [NSCoder class]) {
        _NSCoderAbstract(coder, sel);
    }
    [NSException raise:NSInvalidArgumentException
                format:@"*** -[%@ %@]: This method is only implemented for"
                        " coders which allowKeyedCoding.",
                       NSStringFromClass([coder class]), NSStringFromSelector(sel)];
}

/* "[<count><type>]", the encoding of a C array, which is how the array and
 * byte-string methods below hand their payload to a single primitive call. */
static BOOL _NSCoderArrayType(char *buf, size_t size, NSUInteger count, const char *type) {
    int n = snprintf(buf, size, "[%lu%s]", (unsigned long)count, type);
    return n > 0 && (size_t)n < size;
}

/* Membership test behind the secure decoders: an object passes if it is an
 * instance of an allowed class or of a subclass of one.  Exactly one of
 * `one` and `many` is given, which saves the single-class entry points from
 * having to build a one-element set to ask the question. */
static BOOL _NSCoderObjectIsAllowed(id object, Class one, NSSet<Class> *many) {
    if (object == nil) {
        return NO;
    }
    if (one != Nil) {
        return [object isKindOfClass:one];
    }
    if (many == nil) {
        return NO;
    }

    /* NSSet is toll-free bridged and Foundation does not vend a header for it
     * yet, so the set is read through CoreFoundation. */
    CFSetRef set = (__bridge CFSetRef)many;
    CFIndex count = CFSetGetCount(set);
    if (count <= 0) {
        return NO;
    }

    const void **classes = calloc((size_t)count, sizeof(*classes));
    if (classes == NULL) {
        return NO;
    }
    CFSetGetValues(set, classes);

    BOOL allowed = NO;
    for (CFIndex i = 0; i < count && !allowed; i++) {
        allowed = [object isKindOfClass:(__bridge Class)classes[i]];
    }
    free(classes);
    return allowed;
}

/* The classes a property list is made of. */
static BOOL _NSCoderIsPropertyList(id object) {
    return [object isKindOfClass:[NSString class]]
        || [object isKindOfClass:[NSNumber class]]
        || [object isKindOfClass:[NSDate class]]
        || [object isKindOfClass:[NSData class]]
        || [object isKindOfClass:[NSArray class]]
        || [object isKindOfClass:[NSDictionary class]]
        || [object isKindOfClass:[NSNull class]];
}

/* The collection decoders, unlike -decodeObjectOfClass:forKey:, are not
 * willing to run without secure coding: their whole purpose is to bound what
 * an archive may name, so a coder that checks nothing has nothing to offer
 * them.  The selector reported is always the plural one, which is where the
 * single-class entry points funnel. */
static void _NSCoderRequireSecureCoding(NSCoder *coder, SEL sel) {
    if (![coder requiresSecureCoding]) {
        [NSException raise:NSInvalidUnarchiveOperationException
                    format:@"*** -[%@ %@]: This method only supports secure coding.",
                           NSStringFromClass([coder class]), NSStringFromSelector(sel)];
    }
}

static void _NSCoderFailCorrupt(NSCoder *coder) {
    [coder failWithError:[NSError errorWithDomain:NSCocoaErrorDomain
                                              code:NSCoderReadCorruptError]];
}

/* Shared body of -decodeObjectOfClass:forKey: and -decodeObjectOfClasses:.
 * A coder that does not require secure coding ignores the classes, which is
 * what makes those two the same as -decodeObjectForKey: there. */
static id _NSCoderDecodeObject(NSCoder *coder, NSString *key, Class one, NSSet<Class> *many) {
    id object = [coder decodeObjectForKey:key];

    if (object == nil || ![coder requiresSecureCoding]) {
        return object;
    }
    if (_NSCoderObjectIsAllowed(object, one, many)) {
        return object;
    }
    _NSCoderFailCorrupt(coder);
    return nil;
}

/* An array of the given element classes.  Only one level deep: an array of
 * arrays is not what this decodes. */
static NSArray *_NSCoderDecodeArray(NSCoder *coder, SEL sel, NSString *key,
                                    Class one, NSSet<Class> *many) {
    _NSCoderRequireSecureCoding(coder, sel);

    id object = [coder decodeObjectForKey:key];
    if (object == nil) {
        return nil;
    }
    if (![object isKindOfClass:[NSArray class]]) {
        _NSCoderFailCorrupt(coder);
        return nil;
    }

    NSArray *array = (NSArray *)object;
    NSUInteger count = [array count];
    for (NSUInteger i = 0; i < count; i++) {
        if (!_NSCoderObjectIsAllowed([array objectAtIndex:i], one, many)) {
            _NSCoderFailCorrupt(coder);
            return nil;
        }
    }
    return array;
}

/* As above for a dictionary, checking keys and values against their own
 * class lists. */
static NSDictionary *_NSCoderDecodeDictionary(NSCoder *coder, SEL sel, NSString *key,
                                              Class keyOne, NSSet<Class> *keyMany,
                                              Class objectOne, NSSet<Class> *objectMany) {
    _NSCoderRequireSecureCoding(coder, sel);

    id object = [coder decodeObjectForKey:key];
    if (object == nil) {
        return nil;
    }
    if (![object isKindOfClass:[NSDictionary class]]) {
        _NSCoderFailCorrupt(coder);
        return nil;
    }

    NSDictionary *dictionary = (NSDictionary *)object;
    NSArray *keys = [dictionary allKeys];
    NSUInteger count = [keys count];

    for (NSUInteger i = 0; i < count; i++) {
        id each = [keys objectAtIndex:i];
        if (!_NSCoderObjectIsAllowed(each, keyOne, keyMany) ||
            !_NSCoderObjectIsAllowed([dictionary objectForKey:each], objectOne, objectMany)) {
            _NSCoderFailCorrupt(coder);
            return nil;
        }
    }
    return dictionary;
}

/* Runs one top-level decode and turns a decode failure into an error for the
 * caller.  Only a failure signalled through -failWithError: is caught: an
 * NSInvalidArgumentException from calling the coder wrongly is a mistake in
 * the program, not in the archive, and keeps unwinding. */
static id _NSCoderTopLevel(NSCoder *coder, NSError **error, id (^body)(void)) {
    if (error != NULL) {
        *error = nil;
    }

    if ([coder decodingFailurePolicy] == NSDecodingFailurePolicySetErrorAndReturn) {
        id result = body();
        NSError *failure = [coder error];
        if (failure != nil) {
            if (error != NULL) {
                *error = failure;
            }
            return nil;
        }
        return result;
    }

    @try {
        return body();
    } @catch (NSException *exception) {
        if (!CFEqual((__bridge CFStringRef)[exception name],
                     (__bridge CFStringRef)NSInvalidUnarchiveOperationException)) {
            @throw;
        }
        if (error != NULL) {
            *error = [NSError errorWithDomain:NSCocoaErrorDomain
                                          code:NSCoderReadCorruptError];
        }
        return nil;
    }
}

@implementation NSCoder {
    /* Backs the inner pointers -decodeBytes... hand out.  Plain malloc so the
     * lifetime is the coder's regardless of which memory model this is built
     * under, and so nothing outlives -dealloc. */
    void *_decodedBytes;
    NSUInteger _decodedBytesLength;
}

- (void)dealloc {
    free(_decodedBytes);
#if !__has_feature(objc_arc)
    [super dealloc];
#endif
}

/*
 * The primitives.  Everything in NSExtendedCoder is written in terms of these
 * five, so a subclass that implements them inherits the whole class.
 */

- (void)encodeValueOfObjCType:(const char *)type at:(const void *)addr {
    _NSCoderAbstract(self, _cmd);
}

- (void)encodeDataObject:(NSData *)data {
    _NSCoderAbstract(self, _cmd);
}

- (NSData *)decodeDataObject {
    _NSCoderAbstract(self, _cmd);
    return nil;
}

- (void)decodeValueOfObjCType:(const char *)type at:(void *)data size:(NSUInteger)size {
    _NSCoderAbstract(self, _cmd);
}

- (NSInteger)versionForClassName:(NSString *)className {
    _NSCoderAbstract(self, _cmd);
    return NSNotFound;
}

@end

@implementation NSCoder (NSExtendedCoder)

/*
 * Objects.  bycopy, byref and conditional encoding are distinctions a
 * distributed-objects or archiving subclass draws; here they are all just
 * the object.
 */

- (void)encodeObject:(id)object {
    [self encodeValueOfObjCType:@encode(id) at:&object];
}

- (void)encodeRootObject:(id)rootObject {
    [self encodeObject:rootObject];
}

- (void)encodeBycopyObject:(id)anObject {
    [self encodeObject:anObject];
}

- (void)encodeByrefObject:(id)anObject {
    [self encodeObject:anObject];
}

- (void)encodeConditionalObject:(id)object {
    [self encodeObject:object];
}

- (id)decodeObject {
    id object = nil;
    [self decodeValueOfObjCType:@encode(id) at:&object size:sizeof(object)];
    return object;
}

/*
 * Values.  The type string is handed to the primitive as-is at each step
 * rather than being split up: a coder reads the first item it finds and
 * ignores the rest, and NSGetSizeAndAlignment walks us to the next one.
 */

- (void)encodeValuesOfObjCTypes:(const char *)types, ... {
    va_list args;
    va_start(args, types);
    for (const char *type = types; type != NULL && *type != '\0'; ) {
        const void *addr = va_arg(args, const void *);
        [self encodeValueOfObjCType:type at:addr];
        type = NSGetSizeAndAlignment(type, NULL, NULL);
    }
    va_end(args);
}

- (void)decodeValuesOfObjCTypes:(const char *)types, ... {
    va_list args;
    va_start(args, types);
    for (const char *type = types; type != NULL && *type != '\0'; ) {
        void *addr = va_arg(args, void *);
        NSUInteger size = 0;
        const char *next = NSGetSizeAndAlignment(type, &size, NULL);
        [self decodeValueOfObjCType:type at:addr size:size];
        type = next;
    }
    va_end(args);
}

- (void)encodeArrayOfObjCType:(const char *)type count:(NSUInteger)count at:(const void *)array {
    char arrayType[64];
    if (!_NSCoderArrayType(arrayType, sizeof(arrayType), count, type)) {
        [NSException raise:NSInvalidArgumentException
                    format:@"*** -[%@ %@]: type '%s' is too long to encode",
                           NSStringFromClass([self class]), NSStringFromSelector(_cmd), type];
    }
    [self encodeValueOfObjCType:arrayType at:array];
}

- (void)decodeArrayOfObjCType:(const char *)itemType count:(NSUInteger)count at:(void *)array {
    char arrayType[64];
    if (!_NSCoderArrayType(arrayType, sizeof(arrayType), count, itemType)) {
        [NSException raise:NSInvalidArgumentException
                    format:@"*** -[%@ %@]: type '%s' is too long to decode",
                           NSStringFromClass([self class]), NSStringFromSelector(_cmd), itemType];
    }
    NSUInteger itemSize = 0;
    (void)NSGetSizeAndAlignment(itemType, &itemSize, NULL);
    [self decodeValueOfObjCType:arrayType at:array size:(itemSize * count)];
}

/*
 * Byte strings: an unsigned int length, then the bytes as a C array.  The
 * length is deliberately an unsigned int rather than an NSUInteger -- that is
 * what the format has always been, and widening it would not round-trip.
 */

- (void)encodeBytes:(const void *)byteaddr length:(NSUInteger)length {
    unsigned int wireLength = (unsigned int)length;
    [self encodeValueOfObjCType:@encode(unsigned int) at:&wireLength];
    [self encodeArrayOfObjCType:@encode(char) count:length at:byteaddr];
}

- (void *)decodeBytesWithReturnedLength:(NSUInteger *)lengthp {
    unsigned int wireLength = 0;
    [self decodeValueOfObjCType:@encode(unsigned int) at:&wireLength size:sizeof(wireLength)];

    /* One spare byte so a zero-length decode still returns a pointer the
     * caller may hold, which is what callers of an inner-pointer method
     * expect. */
    void *bytes = realloc(_decodedBytes, (size_t)wireLength + 1);
    if (bytes == NULL) {
        [NSException raise:NSMallocException
                    format:@"*** -[%@ %@]: cannot allocate %u bytes",
                           NSStringFromClass([self class]), NSStringFromSelector(_cmd),
                           wireLength];
    }
    _decodedBytes = bytes;
    _decodedBytesLength = wireLength;

    [self decodeArrayOfObjCType:@encode(char) count:wireLength at:_decodedBytes];

    if (lengthp != NULL) {
        *lengthp = wireLength;
    }
    return _decodedBytes;
}

- (void *)decodeBytesWithMinimumLength:(NSUInteger)length {
    NSUInteger decoded = 0;
    void *bytes = [self decodeBytesWithReturnedLength:&decoded];

    if (decoded < length) {
        _NSCoderFailCorrupt(self);
        return NULL;
    }
    return bytes;
}

#if TARGET_OS_OSX

/* Deprecated, and only meaningful for a coder that can serialise a property
 * list to data; the work happens on either side of the data primitives. */
- (void)encodePropertyList:(id)aPropertyList {
    _NSCoderAbstract(self, _cmd);
}

- (id)decodePropertyList {
    _NSCoderAbstract(self, _cmd);
    return nil;
}

#endif /* TARGET_OS_OSX */

/* Zones stopped meaning anything a long time ago; the setter is ignored and
 * the getter answers the default zone, as Apple's does. */
- (void)setObjectZone:(NSZone *)zone {
}

- (NSZone *)objectZone {
    return NSDefaultMallocZone();
}

- (unsigned int)systemVersion {
    return 1000;
}

/*
 * Keyed coding.  This class does not support it, so every method below
 * raises; a subclass overrides -allowsKeyedCoding and implements them.
 */

- (BOOL)allowsKeyedCoding {
    return NO;
}

- (void)encodeObject:(id)object forKey:(NSString *)key {
    _NSCoderRequiresKeyedCoding(self, _cmd);
}

- (void)encodeConditionalObject:(id)object forKey:(NSString *)key {
    _NSCoderRequiresKeyedCoding(self, _cmd);
}

- (void)encodeBool:(BOOL)value forKey:(NSString *)key {
    _NSCoderRequiresKeyedCoding(self, _cmd);
}

- (void)encodeInt:(int)value forKey:(NSString *)key {
    _NSCoderRequiresKeyedCoding(self, _cmd);
}

- (void)encodeInt32:(int32_t)value forKey:(NSString *)key {
    _NSCoderRequiresKeyedCoding(self, _cmd);
}

- (void)encodeInt64:(int64_t)value forKey:(NSString *)key {
    _NSCoderRequiresKeyedCoding(self, _cmd);
}

- (void)encodeFloat:(float)value forKey:(NSString *)key {
    _NSCoderRequiresKeyedCoding(self, _cmd);
}

- (void)encodeDouble:(double)value forKey:(NSString *)key {
    _NSCoderRequiresKeyedCoding(self, _cmd);
}

- (void)encodeBytes:(const uint8_t *)bytes length:(NSUInteger)length forKey:(NSString *)key {
    _NSCoderRequiresKeyedCoding(self, _cmd);
}

/* NSInteger is not its own wire type; it travels as the widest one so an
 * archive written on one word size reads back on the other. */
- (void)encodeInteger:(NSInteger)value forKey:(NSString *)key {
    [self encodeInt64:(int64_t)value forKey:key];
}

- (BOOL)containsValueForKey:(NSString *)key {
    _NSCoderRequiresKeyedCoding(self, _cmd);
    return NO;
}

- (id)decodeObjectForKey:(NSString *)key {
    _NSCoderRequiresKeyedCoding(self, _cmd);
    return nil;
}

- (BOOL)decodeBoolForKey:(NSString *)key {
    _NSCoderRequiresKeyedCoding(self, _cmd);
    return NO;
}

- (int)decodeIntForKey:(NSString *)key {
    _NSCoderRequiresKeyedCoding(self, _cmd);
    return 0;
}

- (int32_t)decodeInt32ForKey:(NSString *)key {
    _NSCoderRequiresKeyedCoding(self, _cmd);
    return 0;
}

- (int64_t)decodeInt64ForKey:(NSString *)key {
    _NSCoderRequiresKeyedCoding(self, _cmd);
    return 0;
}

- (float)decodeFloatForKey:(NSString *)key {
    _NSCoderRequiresKeyedCoding(self, _cmd);
    return 0.0f;
}

- (double)decodeDoubleForKey:(NSString *)key {
    _NSCoderRequiresKeyedCoding(self, _cmd);
    return 0.0;
}

- (const uint8_t *)decodeBytesForKey:(NSString *)key returnedLength:(NSUInteger *)lengthp {
    _NSCoderRequiresKeyedCoding(self, _cmd);
    return NULL;
}

- (const uint8_t *)decodeBytesForKey:(NSString *)key minimumLength:(NSUInteger)length {
    NSUInteger decoded = 0;
    const uint8_t *bytes = [self decodeBytesForKey:key returnedLength:&decoded];

    if (decoded < length) {
        _NSCoderFailCorrupt(self);
        return NULL;
    }
    return bytes;
}

- (NSInteger)decodeIntegerForKey:(NSString *)key {
    return (NSInteger)[self decodeInt64ForKey:key];
}

/*
 * Secure coding.  A coder that requires it checks each decoded object against
 * a list of classes the archive is allowed to name; one that does not ignores
 * the class arguments entirely, which is why -decodeObjectOfClass: on a plain
 * coder is just -decodeObjectForKey:.
 */

- (BOOL)requiresSecureCoding {
    return NO;
}

- (NSSet<Class> *)allowedClasses {
    return nil;
}

- (id)decodeObjectOfClass:(Class)aClass forKey:(NSString *)key {
    return _NSCoderDecodeObject(self, key, aClass, nil);
}

- (id)decodeObjectOfClasses:(NSSet<Class> *)classes forKey:(NSString *)key {
    return _NSCoderDecodeObject(self, key, Nil, classes);
}

- (NSArray *)decodeArrayOfObjectsOfClass:(Class)cls forKey:(NSString *)key {
    return _NSCoderDecodeArray(self, @selector(decodeArrayOfObjectsOfClasses:forKey:),
                               key, cls, nil);
}

- (NSArray *)decodeArrayOfObjectsOfClasses:(NSSet<Class> *)classes forKey:(NSString *)key {
    return _NSCoderDecodeArray(self, _cmd, key, Nil, classes);
}

- (NSDictionary *)decodeDictionaryWithKeysOfClass:(Class)keyCls
                                   objectsOfClass:(Class)objectCls
                                           forKey:(NSString *)key {
    return _NSCoderDecodeDictionary(self,
                                    @selector(decodeDictionaryWithKeysOfClasses:objectsOfClasses:forKey:),
                                    key, keyCls, nil, objectCls, nil);
}

- (NSDictionary *)decodeDictionaryWithKeysOfClasses:(NSSet<Class> *)keyClasses
                                   objectsOfClasses:(NSSet<Class> *)objectClasses
                                             forKey:(NSString *)key {
    return _NSCoderDecodeDictionary(self, _cmd, key, Nil, keyClasses, Nil, objectClasses);
}

- (id)decodePropertyListForKey:(NSString *)key {
    id object = [self decodeObjectForKey:key];

    if (object != nil && [self requiresSecureCoding] && !_NSCoderIsPropertyList(object)) {
        _NSCoderFailCorrupt(self);
        return nil;
    }
    return object;
}

/*
 * Failure.  -failWithError: is what an -initWithCoder: calls when the archive
 * turns out to be unusable; the top-level decodes below are where the failure
 * surfaces to the caller that started the decode.
 */

- (void)failWithError:(NSError *)error {
    [NSException raise:NSInvalidUnarchiveOperationException
                format:@"%@", [error localizedDescription]];
}

- (NSDecodingFailurePolicy)decodingFailurePolicy {
    return NSDecodingFailurePolicyRaiseException;
}

- (NSError *)error {
    return nil;
}

- (id)decodeTopLevelObjectAndReturnError:(NSError **)error {
    return _NSCoderTopLevel(self, error, ^id{ return [self decodeObject]; });
}

- (id)decodeTopLevelObjectForKey:(NSString *)key error:(NSError **)error {
    return _NSCoderTopLevel(self, error, ^id{ return [self decodeObjectForKey:key]; });
}

- (id)decodeTopLevelObjectOfClass:(Class)aClass forKey:(NSString *)key error:(NSError **)error {
    return _NSCoderTopLevel(self, error, ^id{
        return [self decodeObjectOfClass:aClass forKey:key];
    });
}

- (id)decodeTopLevelObjectOfClasses:(NSSet<Class> *)classes
                             forKey:(NSString *)key
                              error:(NSError **)error {
    return _NSCoderTopLevel(self, error, ^id{
        return [self decodeObjectOfClasses:classes forKey:key];
    });
}

@end

#if TARGET_OS_OSX

NSObject *NXReadNSObjectFromCoder(NSCoder *decoder) {
    return nil;
}

@implementation NSCoder (NSTypedstreamCompatibility)

- (void)encodeNXObject:(id)object {
    [NSException raise:NSInvalidArchiveOperationException
                format:@"*** -[%@ %@]: typedstreams are not supported",
                       NSStringFromClass([self class]), NSStringFromSelector(_cmd)];
}

- (id)decodeNXObject {
    [NSException raise:NSInvalidUnarchiveOperationException
                format:@"*** -[%@ %@]: typedstreams are not supported",
                       NSStringFromClass([self class]), NSStringFromSelector(_cmd)];
    return nil;
}

@end

#endif /* TARGET_OS_OSX */

@implementation NSCoder (NSDeprecated)

- (void)decodeValueOfObjCType:(const char *)type at:(void *)data {
    NSUInteger size = 0;
    (void)NSGetSizeAndAlignment(type, &size, NULL);
    [self decodeValueOfObjCType:type at:data size:size];
}

@end
