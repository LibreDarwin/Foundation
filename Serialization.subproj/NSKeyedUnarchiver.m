/*
 * Copyright (C) 2026, Sunneva N. Mariu.
 *
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */

#import <Foundation/NSKeyedArchiver.h>
#import <Foundation/FoundationErrors.h>
#import <Foundation/NSArray.h>
#import <Foundation/NSData.h>
#import <Foundation/NSDictionary.h>
#import <Foundation/NSError.h>
#import <Foundation/NSException.h>
#import <Foundation/NSNull.h>
#import <Foundation/NSNumber.h>
#import <Foundation/NSSet.h>
#import <Foundation/NSString.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <objc/runtime.h>

/* The archive is a property list.  Everything below reads through that
 * structure: $objects is an array of values and nodes, $top a dictionary of
 * the root keys, and every reference is either a leaf value (string, number,
 * data) standing in $objects directly, or a {"CF$UID": n} token, or a node --
 * a dictionary holding $class plus the keyed members, or a class node holding
 * $classname and $classes.  Resolving a token follows the reference; resolving
 * a node instantiates the class and runs -initWithCoder:. */

/* The uid marker, as written by NSKeyedArchiver. */
static NSDictionary *_UIDToken(NSUInteger uid) {
    return @{@"CF$UID": @(uid)};
}

/* The inverse of the archiver's key mangling.  A key that begins with '$' has
 * had a second '$' prepended by the writer; the reader strips exactly one
 * leading '$' and looks up the remainder, which keeps the reserved keys out
 * of reach of the public decoder. */
static NSString *_DecodedKey(NSString *key) {
    if (key != nil && [key length] > 0 && [key characterAtIndex:0] == '$') {
        return [key substringFromIndex:1];
    }
    return key;
}

/* The plain classes a property list is built from.  They are always underway
 * in the stream, whether or not the archive is secure, so the class
 * validation step skips them. */
static BOOL _IsPlistLeafClass(Class cls) {
    return [cls isSubclassOfClass:[NSString class]]
        || [cls isSubclassOfClass:[NSNumber class]]
        || [cls isSubclassOfClass:[NSData class]];
}

/* The unarchiver's half of the class-name tables.  setClass:forClassName:
 * feeds both; the archiver's setClassName:forClass: only shapes what is
 * written, so it belongs to NSKeyedArchiver. */
static NSMutableDictionary *_UnarchiverGlobalClassesByName; /* coded name -> class */

@interface NSKeyedUnarchiver (Private)
- (id)_objectForObject:(id)value;
- (id)_objectForUID:(NSUInteger)uid;
- (id)_decodeInstanceForUID:(NSUInteger)uid node:(NSDictionary *)node;
- (Class)_classForNode:(NSDictionary *)node;
- (Class)_classForCodedName:(NSString *)name fallbacks:(NSArray *)fallbacks;
- (void)_validateClass:(Class)cls;
- (id)_readValueForKey:(NSString *)key;
- (id)_scalarForKey:(NSString *)key;
- (void)_failCorrupt;
- (void)_checkForFailure;
- (NSString *)_nextUnkeyedKey;
- (void)_pushContainer:(NSDictionary *)container;
- (void)_popContainer;
@end

@implementation NSKeyedUnarchiver {
    NSDictionary *_archive;               /* the parsed property list */
    NSArray *_objects;                    /* $objects, in uid order */
    NSDictionary *_top;                   /* $top, the root keys */

    NSMutableDictionary *_uidToObject;    /* uid -> decoded object (identity) */
    NSMutableArray *_containerStack;      /* the node being decoded; empty at the top */
    NSMutableDictionary *_instanceClassNames; /* coded name -> class, this unarchiver only */
    NSMutableArray *_allowedClassStack;   /* NSSet of classes, pushed by the secure decoders */
    void *_decodeBytes;                   /* the buffer behind -decodeBytesForKey: */
    NSUInteger _decodeBytesLength;
    NSUInteger _unkeyedCount;
    BOOL _requiresSecureCoding;
    NSDecodingFailurePolicy _decodingFailurePolicy;
    BOOL _finished;
    NSError *_error;
}

@synthesize delegate = _delegate;

+ (void)initialize {
    if (self == [NSKeyedUnarchiver class]) {
        _UnarchiverGlobalClassesByName = [[NSMutableDictionary alloc] init];
    }
}

- (void)dealloc {
    free(_decodeBytes);
#if !__has_feature(objc_arc)
    [super dealloc];
#endif
}

/*
 * Entry points.  The modern ones parse the archive and fail through the error
 * out-parameter; the legacy ones are how the old +unarchiveObjectWithData:
 * family of methods read, and they raise.
 */

- (instancetype)init {
    return [self initForReadingWithData:nil];
}

- (instancetype)initForReadingWithData:(NSData *)data {
    if ((self = [super init]) == nil) {
        return nil;
    }
    _decodingFailurePolicy = NSDecodingFailurePolicyRaiseException;
    _uidToObject = [[NSMutableDictionary alloc] init];
    _containerStack = [[NSMutableArray alloc] init];
    _instanceClassNames = [[NSMutableDictionary alloc] init];
    _allowedClassStack = [[NSMutableArray alloc] init];

    if (data == nil) {
        return self;
    }

    NSError *plistError = nil;
    NSPropertyListFormat format = NSPropertyListOpenStepFormat;
    id plist = [NSPropertyListSerialization propertyListWithData:data
                                                          options:NSPropertyListImmutable
                                                           format:&format
                                                            error:&plistError];
    if (plist == nil || ![plist isKindOfClass:[NSDictionary class]]) {
        _error = [NSError errorWithDomain:NSCocoaErrorDomain
                                     code:NSCoderReadCorruptError
                                 userInfo:nil];
        return self;
    }

    NSDictionary *archive = (NSDictionary *)plist;
    id objects = archive[@"$objects"];
    id top = archive[@"$top"];
    if (![objects isKindOfClass:[NSArray class]] || ![top isKindOfClass:[NSDictionary class]]) {
        _error = [NSError errorWithDomain:NSCocoaErrorDomain
                                     code:NSCoderReadCorruptError
                                 userInfo:nil];
        return self;
    }

    _archive = archive;
    _objects = objects;
    _top = top;
    return self;
}

- (instancetype)initForReadingFromData:(NSData *)data error:(NSError **)error {
    if (error != NULL) {
        *error = nil;
    }

    if ((self = [self initForReadingWithData:nil]) == nil) {
        return nil;
    }
    _requiresSecureCoding = YES;

    if (data == nil) {
        if (error != NULL) {
            *error = [NSError errorWithDomain:NSCocoaErrorDomain
                                         code:NSCoderReadCorruptError
                                     userInfo:nil];
        }
        return nil;
    }

    NSError *plistError = nil;
    NSPropertyListFormat format = NSPropertyListOpenStepFormat;
    id plist = [NSPropertyListSerialization propertyListWithData:data
                                                          options:NSPropertyListImmutable
                                                           format:&format
                                                            error:&plistError];
    if (plist == nil || ![plist isKindOfClass:[NSDictionary class]]) {
        if (error != NULL) {
            *error = [NSError errorWithDomain:NSCocoaErrorDomain
                                         code:NSCoderReadCorruptError
                                     userInfo:nil];
        }
        return nil;
    }

    NSDictionary *archive = (NSDictionary *)plist;
    if (![[archive objectForKey:@"$archiver"] isEqual:@"NSKeyedArchiver"] ||
        ![[archive objectForKey:@"$version"] isEqual:@(100000)]) {
        if (error != NULL) {
            *error = [NSError errorWithDomain:NSCocoaErrorDomain
                                         code:NSCoderReadCorruptError
                                     userInfo:nil];
        }
        return nil;
    }

    id objects = archive[@"$objects"];
    id top = archive[@"$top"];
    if (![objects isKindOfClass:[NSArray class]] || ![top isKindOfClass:[NSDictionary class]]) {
        if (error != NULL) {
            *error = [NSError errorWithDomain:NSCocoaErrorDomain
                                         code:NSCoderReadCorruptError
                                     userInfo:nil];
        }
        return nil;
    }

    _archive = archive;
    _objects = objects;
    _top = top;
    return self;
}

/* The modern class methods.  Secure coding is on (`initForReadingFromData:'),
 * the allowed classes are moved onto the stack so every object the archive
 * names is checked against them, and the root object is read from the key
 * NSKeyedArchiveRootObjectKey holds. */

+ (id)_unarchivedObjectOfClasses:(NSSet<Class> *)classes
                       rootClass:(Class)rootCls
                        fromData:(NSData *)data
                           error:(NSError **)error {
    NSKeyedUnarchiver *unarchiver = [[NSKeyedUnarchiver alloc] initForReadingFromData:data error:error];
    if (unarchiver == nil) {
        return nil;
    }

    NSMutableSet *allowed = [NSMutableSet setWithSet:classes];
    if (rootCls != Nil) {
        [allowed addObject:rootCls];
    }

    NSError *decodeError = nil;
    id object = [unarchiver decodeTopLevelObjectOfClasses:allowed
                                                forKey:NSKeyedArchiveRootObjectKey
                                                 error:&decodeError];
    if (decodeError != nil) {
        if (error != NULL) {
            *error = decodeError;
        }
        return nil;
    }

    if (object != nil && rootCls != Nil && ![object isKindOfClass:rootCls]) {
        if (error != NULL) {
            *error = [NSError errorWithDomain:NSCocoaErrorDomain
                                         code:NSCoderReadCorruptError
                                     userInfo:nil];
        }
        return nil;
    }

    [unarchiver finishDecoding];
    return object;
}

+ (id)unarchivedObjectOfClass:(Class)cls fromData:(NSData *)data error:(NSError **)error {
    NSSet *allowed = (cls != Nil) ? [NSSet setWithObject:cls] : [NSSet set];
    return [self _unarchivedObjectOfClasses:allowed rootClass:Nil fromData:data error:error];
}

+ (id)unarchivedObjectOfClasses:(NSSet<Class> *)classes fromData:(NSData *)data error:(NSError **)error {
    return [self _unarchivedObjectOfClasses:classes ?: [NSSet set] rootClass:Nil fromData:data error:error];
}

+ (NSArray *)unarchivedArrayOfObjectsOfClass:(Class)cls
                                     fromData:(NSData *)data
                                        error:(NSError **)error {
    NSSet *allowed = (cls != Nil) ? [NSSet setWithObject:cls] : [NSSet set];
    return (NSArray *)[self _unarchivedObjectOfClasses:allowed rootClass:[NSArray class] fromData:data error:error];
}

+ (NSArray *)unarchivedArrayOfObjectsOfClasses:(NSSet<Class> *)classes
                                       fromData:(NSData *)data
                                          error:(NSError **)error {
    return (NSArray *)[self _unarchivedObjectOfClasses:classes ?: [NSSet set] rootClass:[NSArray class] fromData:data error:error];
}

+ (NSDictionary *)unarchivedDictionaryWithKeysOfClass:(Class)keyCls
                                       objectsOfClass:(Class)valueCls
                                             fromData:(NSData *)data
                                                error:(NSError **)error {
    NSMutableSet *allowed = [NSMutableSet set];
    if (keyCls != Nil) {
        [allowed addObject:keyCls];
    }
    if (valueCls != Nil) {
        [allowed addObject:valueCls];
    }
    return (NSDictionary *)[self _unarchivedObjectOfClasses:allowed rootClass:[NSDictionary class] fromData:data error:error];
}

+ (NSDictionary *)unarchivedDictionaryWithKeysOfClasses:(NSSet<Class> *)keyClasses
                                       objectsOfClasses:(NSSet<Class> *)valueClasses
                                               fromData:(NSData *)data
                                                  error:(NSError **)error {
    NSMutableSet *allowed = [NSMutableSet set];
    if (keyClasses != nil) {
        [allowed unionSet:keyClasses];
    }
    if (valueClasses != nil) {
        [allowed unionSet:valueClasses];
    }
    return (NSDictionary *)[self _unarchivedObjectOfClasses:allowed rootClass:[NSDictionary class] fromData:data error:error];
}

/* The legacy entry points.  They go through the permissive init and read "root",
 * raising when the archive is corrupt or a class cannot be found. */

+ (id)unarchiveObjectWithData:(NSData *)data {
    NSKeyedUnarchiver *unarchiver = [[NSKeyedUnarchiver alloc] initForReadingWithData:data];
    id object = [unarchiver decodeObjectForKey:NSKeyedArchiveRootObjectKey];
    [unarchiver finishDecoding];
    return object;
}

+ (id)unarchiveTopLevelObjectWithData:(NSData *)data error:(NSError **)error {
    NSKeyedUnarchiver *unarchiver = [[NSKeyedUnarchiver alloc] initForReadingFromData:data error:error];
    if (unarchiver == nil) {
        return nil;
    }
    id object = [unarchiver decodeTopLevelObjectForKey:NSKeyedArchiveRootObjectKey error:error];
    [unarchiver finishDecoding];
    return object;
}

+ (id)unarchiveObjectWithFile:(NSString *)path {
    if (path == nil) {
        return nil;
    }
    FILE *file = fopen([path UTF8String], "rb");
    if (file == NULL) {
        return nil;
    }
    if (fseek(file, 0, SEEK_END) != 0) {
        fclose(file);
        return nil;
    }
    long size = ftell(file);
    if (size < 0) {
        fclose(file);
        return nil;
    }
    rewind(file);

    NSData *data = nil;
    if (size == 0) {
        data = [[NSData alloc] init];
    } else {
        void *buffer = malloc((size_t)size);
        if (buffer == NULL) {
            fclose(file);
            return nil;
        }
        size_t read = fread(buffer, 1, (size_t)size, file);
        data = [NSData dataWithBytesNoCopy:buffer length:read freeWhenDone:YES];
    }
    fclose(file);
    return [self unarchiveObjectWithData:data];
}

/*
 * The class-name tables.  Lookup is per-unarchiver first, then on the shared
 * table; nil means the name has no mapping and falls back to NSClassFromString.
 */

+ (void)setClass:(Class)cls forClassName:(NSString *)codedName {
    if (codedName == nil) {
        return;
    }
    if (cls == Nil) {
        [_UnarchiverGlobalClassesByName removeObjectForKey:codedName];
    } else {
        [_UnarchiverGlobalClassesByName setObject:cls forKey:codedName];
    }
}

+ (Class)classForClassName:(NSString *)codedName {
    if (codedName == nil) {
        return Nil;
    }
    return _UnarchiverGlobalClassesByName[codedName];
}

- (void)setClass:(Class)cls forClassName:(NSString *)codedName {
    if (codedName == nil) {
        return;
    }
    if (cls == Nil) {
        [_instanceClassNames removeObjectForKey:codedName];
    } else {
        [_instanceClassNames setObject:cls forKey:codedName];
    }
}

- (Class)classForClassName:(NSString *)codedName {
    if (codedName == nil) {
        return Nil;
    }
    Class cls = _instanceClassNames[codedName];
    if (cls == Nil) {
        cls = _UnarchiverGlobalClassesByName[codedName];
    }
    return cls;
}

- (BOOL)requiresSecureCoding {
    return _requiresSecureCoding;
}

- (void)setRequiresSecureCoding:(BOOL)requiresSecureCoding {
    _requiresSecureCoding = requiresSecureCoding;
}

- (BOOL)allowsKeyedCoding {
    return YES;
}

- (NSDecodingFailurePolicy)decodingFailurePolicy {
    return _decodingFailurePolicy;
}

- (void)setDecodingFailurePolicy:(NSDecodingFailurePolicy)decodingFailurePolicy {
    _decodingFailurePolicy = decodingFailurePolicy;
}

- (NSError *)error {
    return _error;
}

/* Under SetErrorAndReturn the first failure is captured and every later decode
 * comes back empty.  Under RaiseException the historical behaviour rules: the
 * exception goes up. */
- (void)failWithError:(NSError *)error {
    if (error == nil) {
        return;
    }
    if (_decodingFailurePolicy == NSDecodingFailurePolicySetErrorAndReturn) {
        if (_error == nil) {
            _error = error;
        }
        return;
    }
    [NSException raise:NSInvalidUnarchiveOperationException
                format:@"%@", [error localizedDescription]];
}

- (void)_failCorrupt {
    [self failWithError:[NSError errorWithDomain:NSCocoaErrorDomain
                                            code:NSCoderReadCorruptError
                                        userInfo:nil]];
}

- (void)_checkForFailure {
    if (_error == nil) {
        return;
    }
    if (_decodingFailurePolicy == NSDecodingFailurePolicyRaiseException) {
        [NSException raise:NSInvalidUnarchiveOperationException
                    format:@"%@", [_error localizedDescription]];
    }
}

- (void)finishDecoding {
    if (_finished) {
        return;
    }
    _finished = YES;

    if ([_delegate respondsToSelector:@selector(unarchiverWillFinish:)]) {
        [_delegate unarchiverWillFinish:self];
    }
    if (_error == nil && [_delegate respondsToSelector:@selector(unarchiverDidFinish:)]) {
        [_delegate unarchiverDidFinish:self];
    }
}

/*
 * The container.  While an -initWithCoder: runs its node sits on the top of
 * the stack; at the top of the archive the container is the $top dictionary.
 * The unkeyed paths share this container, which is what keeps an unkeyed
 * encode and its matching decode in agreement.
 */

- (void)_pushContainer:(NSDictionary *)container {
    [_containerStack addObject:container];
}

- (void)_popContainer {
    if ([_containerStack count] > 0) {
        [_containerStack removeLastObject];
    }
}

- (NSDictionary *)_currentContainer {
    return [_containerStack lastObject] ?: _top;
}

- (BOOL)containsValueForKey:(NSString *)key {
    if (_finished) {
        [NSException raise:NSInvalidUnarchiveOperationException
                    format:@"*** -[NSKeyedUnarchiver containsValueForKey:]: unarchive has already been finished"];
    }
    [self _checkForFailure];
    if (key == nil) {
        return NO;
    }
    return [[self _currentContainer] objectForKey:key] != nil;
}

/*
 * Keyed decoding.  The public object decoder un-mangles the key and resolves
 * whatever the container holds; the scalar decoders read the raw value and
 * hand back what the primitive asks for.
 */

- (id)decodeObjectForKey:(NSString *)key {
    if (_finished) {
        [NSException raise:NSInvalidUnarchiveOperationException
                    format:@"*** -[NSKeyedUnarchiver decodeObjectForKey:]: unarchive has already been finished"];
    }
    [self _checkForFailure];
    if (key == nil) {
        return nil;
    }
    return [self _readValueForKey:_DecodedKey(key)];
}

- (id)_readValueForKey:(NSString *)key {
    [self _checkForFailure];
    id value = [[self _currentContainer] objectForKey:key];
    if (value == nil) {
        return nil;
    }
    return [self _objectForObject:value];
}

- (id)_scalarForKey:(NSString *)key {
    id value = [[self _currentContainer] objectForKey:key];
    if (value == nil) {
        return nil;
    }
    if ([value isKindOfClass:[NSDictionary class]]) {
        NSNumber *uid = value[@"CF$UID"];
        if (uid != nil) {
            return [self _objectForUID:[uid unsignedIntegerValue]];
        }
    }
    return value;
}

- (BOOL)decodeBoolForKey:(NSString *)key {
    return [[self _scalarForKey:key] respondsToSelector:@selector(boolValue)]
        ? [[self _scalarForKey:key] boolValue] : NO;
}

- (int)decodeIntForKey:(NSString *)key {
    return (int)[self decodeInt64ForKey:key];
}

- (int32_t)decodeInt32ForKey:(NSString *)key {
    return (int32_t)[self decodeInt64ForKey:key];
}

- (int64_t)decodeInt64ForKey:(NSString *)key {
    id value = [self _scalarForKey:key];
    if (value == nil) {
        [self _checkForFailure];
        return 0;
    }
    if ([value respondsToSelector:@selector(longLongValue)]) {
        return [value longLongValue];
    }
    return 0;
}

- (NSInteger)decodeIntegerForKey:(NSString *)key {
    return (NSInteger)[self decodeInt64ForKey:key];
}

- (float)decodeFloatForKey:(NSString *)key {
    return (float)[self decodeDoubleForKey:key];
}

- (double)decodeDoubleForKey:(NSString *)key {
    id value = [self _scalarForKey:key];
    if (value == nil) {
        [self _checkForFailure];
        return 0.0;
    }
    if ([value respondsToSelector:@selector(doubleValue)]) {
        return [value doubleValue];
    }
    return 0.0;
}

- (const uint8_t *)decodeBytesForKey:(NSString *)key returnedLength:(NSUInteger *)lengthp {
    if (lengthp != NULL) {
        *lengthp = 0;
    }
    [self _checkForFailure];

    id value = [[self _currentContainer] objectForKey:key];
    if (value == nil) {
        return NULL;
    }
    if ([value isKindOfClass:[NSDictionary class]]) {
        NSNumber *uid = value[@"CF$UID"];
        if (uid != nil) {
            value = [self _objectForUID:[uid unsignedIntegerValue]];
        }
    }

    if ([value isKindOfClass:[NSString class]]) {
        if ([value isEqual:@"$null"]) {
            return NULL;
        }
        [self _failCorrupt];
        return NULL;
    }

    if (![value isKindOfClass:[NSData class]]) {
        [self _failCorrupt];
        return NULL;
    }

    NSUInteger length = [(NSData *)value length];
    if (length > 0) {
        void *buffer = malloc(length);
        if (buffer == NULL) {
            [self _failCorrupt];
            return NULL;
        }
        memcpy(buffer, [(NSData *)value bytes], length);
        free(_decodeBytes);
        _decodeBytes = buffer;
    } else {
        free(_decodeBytes);
        _decodeBytes = NULL;
    }
    _decodeBytesLength = length;

    if (lengthp != NULL) {
        *lengthp = length;
    }
    return _decodeBytes;
}

/*
 * The unkeyed decode.  The counter walks the same keys the archiver generated:
 * unkeyed objects and classes travel as keyed objects, everything else as raw
 * bytes in an NSData, exactly the mirror of -encodeValueOfObjCType:.
 */

- (NSString *)_nextUnkeyedKey {
    NSUInteger n = _unkeyedCount++;
    if (n < 40) {
        return [NSString stringWithFormat:@"$%lu", (unsigned long)n];
    }
    return [NSString stringWithFormat:@"$NSKeyedArchiverKey$%lu", (unsigned long)n];
}

- (void)decodeValueOfObjCType:(const char *)type at:(void *)data size:(NSUInteger)size {
    if (_finished) {
        [NSException raise:NSInvalidUnarchiveOperationException
                    format:@"*** -[NSKeyedUnarchiver decodeValueOfObjCType:]: unarchive has already been finished"];
    }
    [self _checkForFailure];

    NSString *key = [self _nextUnkeyedKey];
    switch (*type) {
        case '@': {
            id object = [self _readValueForKey:key];
            if (data != NULL) {
                *(__unsafe_unretained id *)data = object;
            }
            return;
        }
        case '#': {
            id value = [self _readValueForKey:key];
            Class cls = Nil;
            if (value != nil && [value isKindOfClass:[NSString class]]) {
                cls = NSClassFromString(value);
            }
            if (data != NULL) {
                *(Class *)data = cls;
            }
            return;
        }
        default: {
            id value = [self _readValueForKey:key];
            if ([value isKindOfClass:[NSData class]]) {
                NSData *bytes = (NSData *)value;
                NSUInteger toCopy = [bytes length];
                if (toCopy > size) {
                    toCopy = size;
                }
                if (data != NULL) {
                    memcpy(data, [bytes bytes], toCopy);
                }
                return;
            }
            if (_error == nil && data != NULL) {
                [self _failCorrupt];
            }
            return;
        }
    }
}

- (NSData *)decodeDataObject {
    id value = [self _readValueForKey:[self _nextUnkeyedKey]];
    if ([value isKindOfClass:[NSData class]]) {
        return value;
    }
    return nil;
}

- (NSInteger)versionForClassName:(NSString *)className {
    return 0;
}

/*
 * The secure decoders.  The allowed classes are pushed onto a stack before the
 * object comes back out of the container so the recursion that fills the
 * object's members validates every class the archive names, then popped.  A
 * coder that does not require secure coding ignores the classes entirely,
 * like the base NSCoder does.
 */

- (id)decodeObjectOfClass:(Class)aClass forKey:(NSString *)key {
    if (!_requiresSecureCoding) {
        return [self decodeObjectForKey:key];
    }
    NSSet *allowed = [NSSet setWithObject:aClass ?: [NSObject class]];
    [self->_allowedClassStack addObject:allowed];
    id object = [self decodeObjectForKey:key];
    [self->_allowedClassStack removeLastObject];
    return object;
}

- (id)decodeObjectOfClasses:(NSSet<Class> *)classes forKey:(NSString *)key {
    if (!_requiresSecureCoding) {
        return [self decodeObjectForKey:key];
    }
    [self->_allowedClassStack addObject:classes ?: [NSSet set]];
    id object = [self decodeObjectForKey:key];
    [self->_allowedClassStack removeLastObject];
    return object;
}

/*
 * Resolution.  Whatever the container holds for a key -- a leaf, a token, a
 * token array, or a node -- becomes an object.  Equality of reference is
 * preserved: the same uid always resolves to the same instance.
 */

- (id)_objectForObject:(id)value {
    if (value == nil) {
        return nil;
    }

    if ([value isKindOfClass:[NSDictionary class]]) {
        NSNumber *uid = value[@"CF$UID"];
        if (uid != nil) {
            return [self _objectForUID:[uid unsignedIntegerValue]];
        }
        if (value[@"$classname"] != nil) {
            return (id)[self _classForNode:value];
        }
        if (value[@"$class"] != nil) {
            return [self _decodeInstanceForUID:NSNotFound node:value];
        }
        return value;
    }

    if ([value isKindOfClass:[NSArray class]]) {
        NSMutableArray *array = [NSMutableArray arrayWithCapacity:[value count]];
        for (id element in value) {
            [array addObject:[self _objectForObject:element]];
        }
        return array;
    }

    return value;
}

- (id)_objectForUID:(NSUInteger)uid {
    if (uid == NSNotFound || uid >= [_objects count]) {
        [self _failCorrupt];
        return nil;
    }

    NSNumber *key = @(uid);
    id cached = _uidToObject[key];
    if (cached != nil) {
        return cached;
    }

    id token = _objects[uid];

    if ([token isKindOfClass:[NSString class]]) {
        if ([token isEqual:@"$null"]) {
            return nil;
        }
        _uidToObject[key] = token;
        return token;
    }

    if ([token isKindOfClass:[NSNumber class]] || [token isKindOfClass:[NSData class]]) {
        _uidToObject[key] = token;
        return token;
    }

    if ([token isKindOfClass:[NSArray class]]) {
        NSMutableArray *array = [NSMutableArray arrayWithCapacity:[token count]];
        for (id element in token) {
            [array addObject:[self _objectForObject:element]];
        }
        _uidToObject[key] = array;
        return array;
    }

    if ([token isKindOfClass:[NSDictionary class]]) {
        NSNumber *innerUID = token[@"CF$UID"];
        if (innerUID != nil) {
            return [self _objectForUID:[innerUID unsignedIntegerValue]];
        }
        if (token[@"$classname"] != nil) {
            Class cls = [self _classForNode:token];
            if (cls == Nil) {
                return nil;
            }
            _uidToObject[key] = (id)cls;
            return (id)cls;
        }
        if (token[@"$class"] != nil) {
            return [self _decodeInstanceForUID:uid node:token];
        }
    }

    return nil;
}

- (id)_decodeInstanceForUID:(NSUInteger)uid node:(NSDictionary *)node {
    Class cls = [self _classForNode:node];
    if (cls == Nil) {
        return nil;
    }
    [self _validateClass:cls];

    NSNumber *key = @(uid);
    id placeholder = [[cls alloc] init];
    _uidToObject[key] = placeholder;

    [self _pushContainer:node];
    id decoded = nil;
    @try {
        decoded = [placeholder initWithCoder:self];
    } @catch (NSException *exception) {
        [self _popContainer];
        if (_error == nil) {
            _uidToObject[key] = [NSNull null];
        }
        @throw;
    }
    [self _popContainer];

    if (_error != nil || decoded == nil) {
        [_uidToObject removeObjectForKey:key];
        if (uid == NSNotFound) {
            return nil;
        }
        return nil;
    }

    _uidToObject[key] = decoded;

    if ([_delegate respondsToSelector:@selector(unarchiver:didDecodeObject:)]) {
        id replaced = [_delegate unarchiver:self didDecodeObject:decoded];
        if (replaced != nil) {
            _uidToObject[key] = replaced;
            return replaced;
        }
    }
    return decoded;
}

/*
 * Class lookup.  The node names the class; the instance table, the shared
 * table and NSClassFromString are tried in that order, then the fallback
 * class names the archive saved, then the delegate.  A class that names
 * itself a substitute through +classForKeyedUnarchiver is honoured.
 */

- (Class)_classForNode:(NSDictionary *)node {
    id classValue = node[@"$class"];
    if ([classValue isKindOfClass:[NSDictionary class]]) {
        NSNumber *uid = classValue[@"CF$UID"];
        if (uid != nil) {
            id resolved = [self _objectForUID:[uid unsignedIntegerValue]];
            if (resolved != nil && object_getClass(resolved) == Nil) {
                return resolved;
            }
        }
    }

    id name = node[@"$classname"];
    if (![name isKindOfClass:[NSString class]]) {
        [self _failCorrupt];
        return Nil;
    }
    id classes = node[@"$classes"];
    NSArray *fallbacks = [classes isKindOfClass:[NSArray class]] ? classes : @[];
    return [self _classForCodedName:name fallbacks:fallbacks];
}

- (Class)_classForCodedName:(NSString *)name fallbacks:(NSArray *)fallbacks {
    Class cls = _instanceClassNames[name];
    if (cls == Nil) {
        cls = _UnarchiverGlobalClassesByName[name];
    }
    if (cls == Nil) {
        cls = NSClassFromString(name);
    }

    if (cls == Nil) {
        for (id fallback in fallbacks) {
            if (![fallback isKindOfClass:[NSString class]] || [fallback isEqual:name]) {
                continue;
            }
            Class found = _instanceClassNames[fallback];
            if (found == Nil) {
                found = _UnarchiverGlobalClassesByName[fallback];
            }
            if (found == Nil) {
                found = NSClassFromString(fallback);
            }
            if (found != Nil) {
                cls = found;
                break;
            }
        }
    }

    if (cls != Nil) {
        Class substituted = [cls classForKeyedUnarchiver];
        if (substituted != Nil) {
            cls = substituted;
        }
    }

    if (cls == Nil && _delegate != nil &&
        [_delegate respondsToSelector:@selector(unarchiver:cannotDecodeObjectOfClassName:originalClasses:)]) {
        cls = [_delegate unarchiver:self
         cannotDecodeObjectOfClassName:name
                       originalClasses:fallbacks];
    }

    if (cls == Nil) {
        [self _failCorrupt];
        return Nil;
    }
    return cls;
}

/* Secure coding.  Every class an archive instantiates must conform to
 * NSSecureCoding; when the secure decoders pushed an allowed set, it must be
 * one of those classes or a subclass. */
- (void)_validateClass:(Class)cls {
    if (!_requiresSecureCoding || cls == Nil) {
        return;
    }

    if (![cls conformsToProtocol:@protocol(NSSecureCoding)] &&
        !_IsPlistLeafClass(cls)) {
        [self failWithError:[NSError errorWithDomain:NSCocoaErrorDomain
                                                code:NSCoderReadCorruptError
                                            userInfo:@{NSLocalizedDescriptionKey:
                [NSString stringWithFormat:@"class %@ does not conform to NSSecureCoding",
                                           NSStringFromClass(cls)]}]];
        return;
    }

    NSSet *allowed = [_allowedClassStack lastObject];
    if (allowed == nil || [allowed count] == 0) {
        return;
    }
    if (_IsPlistLeafClass(cls)) {
        return;
    }
    for (id allowedClass in allowed) {
        if ([cls isSubclassOfClass:(Class)allowedClass]) {
            return;
        }
    }

    [self failWithError:[NSError errorWithDomain:NSCocoaErrorDomain
                                            code:NSCoderReadCorruptError
                                        userInfo:@{NSLocalizedDescriptionKey:
                [NSString stringWithFormat:
                    @"class %@ not allowed to be decoded: it is not in the allowed classes",
                    NSStringFromClass(cls)]}]];
}

@end