/*
 * Copyright (C) 2026, Sunneva N. Mariu.
 *
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */

#ifndef NSCoder_h
#define NSCoder_h

#import <Foundation/NSObject.h>
#import <Foundation/NSObjCRuntime.h>
#import <Foundation/NSZone.h>
#include <TargetConditionals.h>

@class NSData, NSError, NSString;

/* Forward-declared with their type parameters so this header is safe to
 * include before or after the ones that define them; clang will not let a
 * parameterised @interface follow a bare @class for the same name. */
@class NSArray<__covariant ObjectType>;
@class NSDictionary<__covariant KeyType, __covariant ObjectType>;

/* This is the first header in the umbrella to mention NSSet at all, and the
 * declaration has to be the parameterised one for the same reason: framework
 * headers outside Foundation forward-declare it bare, which is allowed to
 * follow this but not to precede it. */
@class NSSet<ObjectType>;

/* What a coder does when a decode fails -- a corrupt archive, a value of the
 * wrong type, a class the archive is not allowed to instantiate.  Raising is
 * the historical behaviour and stays the default; the other policy captures
 * the first failure in -error and makes every later decode return zero. */
typedef NS_ENUM(NSInteger, NSDecodingFailurePolicy) {
    NSDecodingFailurePolicyRaiseException,
    NSDecodingFailurePolicySetErrorAndReturn,
};

/* NSCoder is abstract.  The five methods below are the primitives: a concrete
 * subclass implements them and inherits everything in NSExtendedCoder, which
 * is written in terms of them.  The base implementations raise. */
@interface NSCoder : NSObject

- (void)encodeValueOfObjCType:(const char *)type at:(const void *)addr;
- (void)encodeDataObject:(NSData *)data;
- (NSData *)decodeDataObject;
- (void)decodeValueOfObjCType:(const char *)type at:(void *)data size:(NSUInteger)size;
- (NSInteger)versionForClassName:(NSString *)className;

@end

@interface NSCoder (NSExtendedCoder)

- (void)encodeObject:(id)object;
- (void)encodeRootObject:(id)rootObject;
- (void)encodeBycopyObject:(id)anObject;
- (void)encodeByrefObject:(id)anObject;
- (void)encodeConditionalObject:(id)object;
- (void)encodeValuesOfObjCTypes:(const char *)types, ...;
- (void)encodeArrayOfObjCType:(const char *)type count:(NSUInteger)count at:(const void *)array;
- (void)encodeBytes:(const void *)byteaddr length:(NSUInteger)length;

- (id)decodeObject;
- (id)decodeTopLevelObjectAndReturnError:(NSError **)error
    NS_SWIFT_UNAVAILABLE("Use 'decodeTopLevelObject() throws' instead");
- (void)decodeValuesOfObjCTypes:(const char *)types, ...;
- (void)decodeArrayOfObjCType:(const char *)itemType count:(NSUInteger)count at:(void *)array;
- (void *)decodeBytesWithReturnedLength:(NSUInteger *)lengthp NS_RETURNS_INNER_POINTER;

#if TARGET_OS_OSX
- (void)encodePropertyList:(id)aPropertyList;
- (id)decodePropertyList;
#endif

- (void)setObjectZone:(NSZone *)zone NS_AUTOMATED_REFCOUNT_UNAVAILABLE;
- (NSZone *)objectZone NS_AUTOMATED_REFCOUNT_UNAVAILABLE;

@property (readonly) unsigned int systemVersion;

/* NO on this class.  A subclass that overrides it to return YES must also
 * implement the keyed methods below, which otherwise raise. */
@property (readonly) BOOL allowsKeyedCoding;

- (void)encodeObject:(id)object forKey:(NSString *)key;
- (void)encodeConditionalObject:(id)object forKey:(NSString *)key;
- (void)encodeBool:(BOOL)value forKey:(NSString *)key;
- (void)encodeInt:(int)value forKey:(NSString *)key;
- (void)encodeInt32:(int32_t)value forKey:(NSString *)key;
- (void)encodeInt64:(int64_t)value forKey:(NSString *)key;
- (void)encodeFloat:(float)value forKey:(NSString *)key;
- (void)encodeDouble:(double)value forKey:(NSString *)key;
- (void)encodeBytes:(const uint8_t *)bytes length:(NSUInteger)length forKey:(NSString *)key;

- (BOOL)containsValueForKey:(NSString *)key;
- (id)decodeObjectForKey:(NSString *)key;
- (id)decodeTopLevelObjectForKey:(NSString *)key error:(NSError **)error
    NS_SWIFT_UNAVAILABLE("Use 'decodeObject(of:, forKey:)' instead");
- (BOOL)decodeBoolForKey:(NSString *)key;
- (int)decodeIntForKey:(NSString *)key;
- (int32_t)decodeInt32ForKey:(NSString *)key;
- (int64_t)decodeInt64ForKey:(NSString *)key;
- (float)decodeFloatForKey:(NSString *)key;
- (double)decodeDoubleForKey:(NSString *)key;

/* The returned bytes belong to the coder and are immutable. */
- (const uint8_t *)decodeBytesForKey:(NSString *)key returnedLength:(NSUInteger *)lengthp
    NS_RETURNS_INNER_POINTER;

/* As above, but the value must carry at least `length` bytes; a short value
 * fails the decode through -failWithError: rather than returning a buffer the
 * caller would read past the end of. */
- (void *)decodeBytesWithMinimumLength:(NSUInteger)length NS_RETURNS_INNER_POINTER;
- (const uint8_t *)decodeBytesForKey:(NSString *)key minimumLength:(NSUInteger)length
    NS_RETURNS_INNER_POINTER;

- (void)encodeInteger:(NSInteger)value forKey:(NSString *)key;
- (NSInteger)decodeIntegerForKey:(NSString *)key;

/* A secure coder checks every object it instantiates against a list of
 * allowed classes, and refuses classes that do not adopt NSSecureCoding. */
@property (readonly) BOOL requiresSecureCoding;

- (id)decodeObjectOfClass:(Class)aClass forKey:(NSString *)key;
- (id)decodeTopLevelObjectOfClass:(Class)aClass forKey:(NSString *)key error:(NSError **)error
    NS_SWIFT_UNAVAILABLE("Use 'decodeObject(of:, forKey:)' instead");

/* The collection decoders take the element class rather than the collection
 * class, and do not descend: an array of arrays, or a dictionary holding a
 * dictionary, is not what these decode.  They require secure coding. */
- (NSArray *)decodeArrayOfObjectsOfClass:(Class)cls forKey:(NSString *)key
    NS_REFINED_FOR_SWIFT;
- (NSDictionary *)decodeDictionaryWithKeysOfClass:(Class)keyCls
                                   objectsOfClass:(Class)objectCls
                                           forKey:(NSString *)key NS_REFINED_FOR_SWIFT;

/* The class may be any class in the set, or a subclass of one. */
- (id)decodeObjectOfClasses:(NSSet<Class> *)classes forKey:(NSString *)key
    NS_REFINED_FOR_SWIFT;
- (id)decodeTopLevelObjectOfClasses:(NSSet<Class> *)classes forKey:(NSString *)key
                              error:(NSError **)error
    NS_SWIFT_UNAVAILABLE("Use 'decodeObject(of:, forKey:)' instead");

- (NSArray *)decodeArrayOfObjectsOfClasses:(NSSet<Class> *)classes forKey:(NSString *)key
    NS_REFINED_FOR_SWIFT;
- (NSDictionary *)decodeDictionaryWithKeysOfClasses:(NSSet<Class> *)keyClasses
                                   objectsOfClasses:(NSSet<Class> *)objectClasses
                                            forKey:(NSString *)key NS_REFINED_FOR_SWIFT;

/* -decodeObjectOfClasses:forKey: over the property list classes. */
- (id)decodePropertyListForKey:(NSString *)key;

@property (readonly, copy) NSSet<Class> *allowedClasses;

/* Called from -initWithCoder: when the archive turns out to be unusable:
 * secure coding was required and not honoured, the data is corrupt, a value
 * is outside its domain.  Clean up and return nil straight after.
 *
 * The error is recorded once per top-level decode and stays set until the
 * stack unwinds to the -decodeTopLevel... call that started it, which is
 * where it surfaces.  How the unwinding happens is -decodingFailurePolicy:
 * an exception, or every subsequent decode returning zero. */
- (void)failWithError:(NSError *)error;

@property (readonly) NSDecodingFailurePolicy decodingFailurePolicy;

/* Always nil under NSDecodingFailurePolicyRaiseException.  Otherwise the
 * first failure of the current top-level decode, if there has been one. */
@property (readonly, copy) NSError *error;

@end

#if TARGET_OS_OSX

/* Reads an object written by NXWriteNSObject().  Not supported. */
FOUNDATION_EXPORT NSObject *NXReadNSObjectFromCoder(NSCoder *decoder);

@interface NSCoder (NSTypedstreamCompatibility)

- (void)encodeNXObject:(id)object;
- (id)decodeNXObject;

@end

#endif /* TARGET_OS_OSX */

@interface NSCoder (NSDeprecated)

/* Unsafe: nothing here bounds the write.  Use the -size: form. */
- (void)decodeValueOfObjCType:(const char *)type at:(void *)data;

@end

#endif /* NSCoder_h */
