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
#include <CoreFoundation/ForFoundationOnly.h>
#include <CoreFoundation/CFPropertyList.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

NSString * const NSKeyedArchiveRootObjectKey = @"root";

/* The leaf classes.  An instance of one of these, under its natural name, is
 * written directly into the $objects array and referenced by uid, the same
 * way a plain plist stores them.  Everything else has to pass through
 * -encodeWithCoder:, which is what "keyed coding" means for the rest. */
static inline BOOL _IsImmediateArchivedClass(id object, NSString *name) {
    if ([name isEqualToString:@"NSString"]) {
        return [object isKindOfClass:[NSString class]];
    }
    if ([name isEqualToString:@"NSNumber"]) {
        return [object isKindOfClass:[NSNumber class]];
    }
    return NO;
}

/* The uid marker, written as the value of an encoded object reference. */
static NSDictionary *_UIDToken(NSUInteger uid) {
    return @{@"CF$UID": @(uid)};
}

/* Key mangling.  A key that begins with '$' would collide with the reserved
 * keys ($class, $objects, ...); the encoder therefore prepends a second '$'.
 * The decoder strips one leading '$' and looks up the remainder. */
static NSString *_MangledKey(NSString *key) {
    if (key != nil && [key length] > 0 && [key characterAtIndex:0] == '$') {
        return [@"$" stringByAppendingString:key];
    }
    return key;
}

/* The class-name tables live between the two instances.  They are global by
 * design: setClassName:forClass: on either archiver and setClass:forClassName:
 * on either unarchiver talk to the same table. */
static NSMutableDictionary *_ArchiverGlobalNamesByClass;   /* class name -> coded name */
static NSMutableDictionary *_UnarchiverGlobalClassesByName; /* coded name -> class */

@interface NSKeyedArchiver (Private)
- (NSUInteger)_encodeNodeObject:(id)object;
- (NSUInteger)_encodeClassNodeNamed:(NSString *)name forClass:(Class)cls;
- (void)_resolveConditionalsForObject:(id)object uid:(NSUInteger)uid;
- (id)_identifiedObject:(id)object;
- (void)_checkSecureObject:(id)object;
- (void)_putValue:(id)value forKey:(NSString *)key;
- (NSDictionary *)_encodeObjectToken:(id)object;
- (void)_encodeArrayOfObjects:(NSArray *)array forKey:(NSString *)key;
- (NSString *)_nextUnkeyedKey;
- (void)_encodeObject:(id)object forKeyValue:(NSString *)key;
@end

/* The container classes call the archiver's private array encoder from inside
 * their -encodeWithCoder:, so the NSCoder side has to see it too. */
@interface NSCoder (NSKeyedArchiverPrivate)
- (void)_encodeArrayOfObjects:(NSArray *)array forKey:(NSString *)key;
@end

@implementation NSKeyedArchiver {
    NSMutableData *_data;
    NSData *_encodedData;

    NSMutableArray *_objects;              /* $objects, in uid order */
    NSMutableDictionary *_top;             /* root keys */
    NSMutableDictionary *_objToUid;        /* pointer string -> uid */
    NSMutableDictionary *_nameToClassUid;  /* coded name -> class-node uid */
    NSMutableDictionary *_conditionalPlaceholders; /* pointer string -> array of (container,key) pairs */
    NSMutableDictionary *_currentNode;     /* the node being encoded, nil at the top */
    NSMutableDictionary *_instanceClassNames; /* class name -> coded name, this archiver only */
    NSMutableSet *_identifiedSet;          /* objects already through substitution */
    NSString *_writingKey;             /* the key of the node currently being written */
    NSPropertyListFormat _outputFormat;
    NSUInteger _unkeyedCount;
    BOOL _requiresSecureCoding;
    BOOL _finished;
}

@synthesize delegate = _delegate;

+ (void)initialize {
    if (self == [NSKeyedArchiver class]) {
        _ArchiverGlobalNamesByClass = [[NSMutableDictionary alloc] init];
        _UnarchiverGlobalClassesByName = [[NSMutableDictionary alloc] init];
    }
}

+ (void)setClassName:(NSString *)codedName forClass:(Class)cls {
    if (codedName == nil) {
        [_ArchiverGlobalNamesByClass removeObjectForKey:NSStringFromClass(cls)];
    } else {
        [_ArchiverGlobalNamesByClass setObject:codedName forKey:NSStringFromClass(cls)];
    }
}

+ (NSString *)classNameForClass:(Class)cls {
    return _ArchiverGlobalNamesByClass[NSStringFromClass(cls)];
}

- (NSString *)classNameForClass:(Class)cls {
    NSString *name = _instanceClassNames[NSStringFromClass(cls)];
    if (name != nil) {
        return name;
    }
    return _ArchiverGlobalNamesByClass[NSStringFromClass(cls)];
}

- (void)setClassName:(NSString *)codedName forClass:(Class)cls {
    if (codedName == nil) {
        [_instanceClassNames removeObjectForKey:NSStringFromClass(cls)];
    } else {
        [_instanceClassNames setObject:codedName forKey:NSStringFromClass(cls)];
    }
}

- (instancetype)initWithRequiresSecureCoding:(BOOL)requiresSecureCoding {
    if ((self = [super init]) == nil) {
        return nil;
    }
    _objects = [[NSMutableArray alloc] init];
    [_objects addObject:@"$null"];          /* uid 0 is the nil token */
    _top = [[NSMutableDictionary alloc] init];
    _objToUid = [[NSMutableDictionary alloc] init];
    _nameToClassUid = [[NSMutableDictionary alloc] init];
    _conditionalPlaceholders = [[NSMutableDictionary alloc] init];
    _instanceClassNames = [[NSMutableDictionary alloc] init];
    _identifiedSet = [[NSMutableSet alloc] init];
    _outputFormat = NSPropertyListBinaryFormat_v1_0;
    _requiresSecureCoding = requiresSecureCoding;
    return self;
}

- (instancetype)initRequiringSecureCoding:(BOOL)requiresSecureCoding {
    return [self initWithRequiresSecureCoding:requiresSecureCoding];
}

- (instancetype)init {
    return [self initWithRequiresSecureCoding:NO];
}

- (instancetype)initForWritingWithMutableData:(NSMutableData *)data {
    if ((self = [self initWithRequiresSecureCoding:NO]) == nil) {
        return nil;
    }
    _data = data;
    return self;
}

+ (NSData *)archivedDataWithRootObject:(id)object
                 requiringSecureCoding:(BOOL)requiresSecureCoding
                                 error:(NSError **)error {
    NSKeyedArchiver *archiver = [[NSKeyedArchiver alloc] initWithRequiresSecureCoding:requiresSecureCoding];
    @try {
        [archiver encodeObject:object forKey:NSKeyedArchiveRootObjectKey];
        [archiver finishEncoding];
    } @catch (NSException *e) {
        if (error != NULL) {
            *error = [NSError errorWithDomain:NSCocoaErrorDomain
                                         code:NSCoderWriteInsufficientMemoryError
                                     userInfo:@{NSLocalizedDescriptionKey: [e reason]}];
        }
        return nil;
    }
    return archiver.encodedData;
}

+ (NSData *)archivedDataWithRootObject:(id)rootObject {
    NSKeyedArchiver *archiver = [[NSKeyedArchiver alloc] init];
    [archiver encodeObject:rootObject forKey:NSKeyedArchiveRootObjectKey];
    [archiver finishEncoding];
    return archiver.encodedData;
}

+ (BOOL)archiveRootObject:(id)rootObject toFile:(NSString *)path {
    NSData *data = [self archivedDataWithRootObject:rootObject];
    if (data == nil) return NO;
    FILE *file = fopen([path UTF8String], "wb");
    if (file == NULL) return NO;
    size_t written = fwrite([data bytes], 1, [data length], file);
    int closeResult = fclose(file);
    return written == [data length] && closeResult == 0;
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

- (NSPropertyListFormat)outputFormat {
    return _outputFormat;
}

- (void)setOutputFormat:(NSPropertyListFormat)outputFormat {
    _outputFormat = outputFormat;
}

- (NSData *)encodedData {
    if (!_finished) {
        [self finishEncoding];
    }
    return _encodedData;
}

/* Every keyed write lands on the node being encoded, or on the $top
 * dictionary at the top of the archive.  The container is a mutable
 * dictionary; containers from Apple, and any node whose coder keys collide
 * with the reserved ones, are the caller's problem to name uniquely. */
- (void)_putValue:(id)value forKey:(NSString *)key {
    NSMutableDictionary *container = _currentNode ?: _top;
    container[key] = value;
}

- (void)_checkSecureObject:(id)object {
    if (!_requiresSecureCoding || object == nil) {
        return;
    }
    if ([object isKindOfClass:[NSString class]] ||
        [object isKindOfClass:[NSNumber class]] ||
        [object isKindOfClass:[NSData class]]) {
        return;
    }
    if (![object conformsToProtocol:@protocol(NSSecureCoding)]) {
        [NSException raise:NSInvalidArgumentException
                    format:@"*** -[NSKeyedArchiver encodeObject:forKey:]: class %@ does not implement NSSecureCoding",
                           NSStringFromClass([object class])];
    }
}

/* Substitution.  A class may swap instances, then the delegate gets a look at
 * what is about to be written; the delegate's replacement, or nil, is what is
 * actually encoded.  Each object goes through this once. */
- (id)_identifiedObject:(id)object {
    if (object == nil) {
        return nil;
    }
    NSString *key = [NSString stringWithFormat:@"%p", (void *)object];
    id result = object;

    if (![_identifiedSet containsObject:key]) {
        [_identifiedSet addObject:key];
        id replacement = [object replacementObjectForKeyedArchiver:self];
        if (replacement != nil && replacement != object) {
            if ([_delegate respondsToSelector:@selector(archiver:willReplaceObject:withObject:)]) {
                [_delegate archiver:self willReplaceObject:object withObject:replacement];
            }
            result = replacement;
        }
    }

    if ([_delegate respondsToSelector:@selector(archiver:willEncodeObject:)]) {
        id delegateObject = [_delegate archiver:self willEncodeObject:result];
        if (delegateObject != nil) {
            result = delegateObject;
        }
    }
    return result;
}

/* The name an object is written as: the archiver's own table, the global
 * table, the class's own substitution, then its real name. */
- (NSString *)_codedNameForObject:(id)object {
    Class observed = [object classForKeyedArchiver];
    if (observed == Nil) {
        observed = [object class];
    }
    NSString *name = [self classNameForClass:observed];
    if (name == nil) {
        name = NSStringFromClass(observed);
    }
    return name;
}

/* The name of the class node: the coded name followed by the real class's
 * chain of superclasses down to NSObject. */
- (NSUInteger)_encodeClassNodeNamed:(NSString *)name forClass:(Class)cls {
    NSNumber *cached = _nameToClassUid[name];
    if (cached != nil) {
        return [cached unsignedIntegerValue];
    }

    NSMutableDictionary *node = [[NSMutableDictionary alloc] init];
    node[@"$classname"] = name;
    NSMutableArray *classes = [NSMutableArray arrayWithCapacity:1];
    [classes addObject:name];
    Class superclass = [cls superclass];
    while (superclass != Nil) {
        [classes addObject:NSStringFromClass(superclass)];
        if (superclass == [NSObject class]) {
            break;
        }
        superclass = [superclass superclass];
    }
    node[@"$classes"] = classes;

    NSUInteger uid = [_objects count];
    _nameToClassUid[name] = @(uid);
    [_objects addObject:node];
    return uid;
}

/* A leaf value (string, number, data) is appended to $objects and returns its
 * uid.  Re-encoding the same object reuses the uid, which is what keeps two
 * references to one object connected after a round trip. */
- (NSUInteger)_internLeaf:(id)leaf {
    NSUInteger uid = [_objects count];
    [_objects addObject:leaf];
    return uid;
}

- (void)_resolveConditionalsForObject:(id)object uid:(NSUInteger)uid {
    NSString *key = [NSString stringWithFormat:@"%p", (void *)object];
    NSMutableArray *placeholders = _conditionalPlaceholders[key];
    if (placeholders == nil) {
        return;
    }
    for (NSArray *pair in placeholders) {
        NSMutableDictionary *container = pair[0];
        NSString *containerKey = pair[1];
        container[containerKey] = _UIDToken(uid);
    }
    [_conditionalPlaceholders removeObjectForKey:key];
}

- (void)_registerConditional:(id)object {
    NSString *key = [NSString stringWithFormat:@"%p", (void *)object];
    NSMutableArray *placeholders = _conditionalPlaceholders[key];
    if (placeholders == nil) {
        placeholders = [[NSMutableArray alloc] init];
        _conditionalPlaceholders[key] = placeholders;
    }
    [placeholders addObject:@[_currentNode ?: _top, _writingKey]];
}

/* Encode one object and return the uid token that references it.  The token
 * is what callers write into whatever container they are filling; the writer
 * itself decides where it lands.  This is the meat of the format: called from
 * the top it is the root; called from within -encodeWithCoder: it fills the
 * object's node. */
- (NSDictionary *)_encodeObjectToken:(id)object {
    if (object == nil) {
        return _UIDToken(0);
    }

    object = [self _identifiedObject:object];

    if (object == nil) {
        return _UIDToken(0);
    }

    NSString *ptrKey = [NSString stringWithFormat:@"%p", (void *)object];
    NSNumber *existing = _objToUid[ptrKey];
    if (existing != nil) {
        return _UIDToken([existing unsignedIntegerValue]);
    }

    NSString *codedName = [self _codedNameForObject:object];

    if (_IsImmediateArchivedClass(object, codedName)) {
        NSUInteger uid = [self _internLeaf:object];
        _objToUid[ptrKey] = @(uid);
        [self _resolveConditionalsForObject:object uid:uid];
        if ([_delegate respondsToSelector:@selector(archiver:didEncodeObject:)]) {
            [_delegate archiver:self didEncodeObject:object];
        }
        return _UIDToken(uid);
    }

    [self _checkSecureObject:object];

    NSUInteger uid = [_objects count];
    [_objects addObject:[NSNull null]];
    _objToUid[ptrKey] = @(uid);

    NSMutableDictionary *node = [[NSMutableDictionary alloc] init];
    NSMutableDictionary *savedNode = _currentNode;
    _currentNode = node;
    [object encodeWithCoder:self];
    _currentNode = savedNode;

    NSUInteger classUid = [self _encodeClassNodeNamed:codedName forClass:[object class]];
    node[@"$class"] = _UIDToken(classUid);
    [_objects replaceObjectAtIndex:uid withObject:node];

    [self _resolveConditionalsForObject:object uid:uid];
    if ([_delegate respondsToSelector:@selector(archiver:didEncodeObject:)]) {
        [_delegate archiver:self didEncodeObject:object];
    }
    return _UIDToken(uid);
}

/* The reserved keys collide with any user key that starts with '$', so out of
 * the public entry points the key is first mangled.  The internal writes
 * below bypass that and take the key as given. */

- (void)encodeObject:(id)object forKey:(NSString *)key {
    [self _encodeObject:object forKeyValue:_MangledKey(key)];
}

/* Internal single-object write, key taken verbatim (used by the unkeyed
 * paths, which manage their own generated keys). */
- (void)_encodeObject:(id)object forKeyValue:(NSString *)key {
    _writingKey = key;
    [self _putValue:[self _encodeObjectToken:object] forKey:key];
    _writingKey = nil;
}

- (void)encodeConditionalObject:(id)object forKey:(NSString *)key {
    key = _MangledKey(key);
    _writingKey = key;
    if (object == nil) {
        [self _putValue:_UIDToken(0) forKey:key];
        _writingKey = nil;
        return;
    }

    object = [self _identifiedObject:object];

    if (object == nil) {
        [self _putValue:_UIDToken(0) forKey:key];
        _writingKey = nil;
        return;
    }

    NSString *ptrKey = [NSString stringWithFormat:@"%p", (void *)object];
    NSNumber *existing = _objToUid[ptrKey];
    if (existing != nil) {
        [self _putValue:_UIDToken([existing unsignedIntegerValue]) forKey:key];
    } else {
        [self _registerConditional:object];
        [self _putValue:_UIDToken(0) forKey:key];
    }
    _writingKey = nil;
}

/* A set of objects under one key becomes one inline array of uid tokens in
 * the current container node.  This is how NSArray, NSSet and the key/value
 * halves of NSDictionary store their members. */
- (void)_encodeArrayOfObjects:(NSArray *)array forKey:(NSString *)key {
    key = _MangledKey(key);
    NSMutableArray *tokens = [NSMutableArray arrayWithCapacity:[array count]];
    for (id element in array) {
        [tokens addObject:[self _encodeObjectToken:element]];
    }
    [self _putValue:tokens forKey:key];
}

- (void)encodeRootObject:(id)rootObject {
    [self _encodeObject:rootObject forKeyValue:[self _nextUnkeyedKey]];
}

/* Primitive keyed values are written inline; they are not objects and carry
 * no uid.  Their keys are mangled like any other keyed write. */

- (void)encodeBool:(BOOL)value forKey:(NSString *)key {
    [self _putValue:@(value) forKey:_MangledKey(key)];
}

- (void)encodeInt:(int)value forKey:(NSString *)key {
    [self _putValue:@(value) forKey:_MangledKey(key)];
}

- (void)encodeInt32:(int32_t)value forKey:(NSString *)key {
    [self _putValue:@(value) forKey:_MangledKey(key)];
}

- (void)encodeInt64:(int64_t)value forKey:(NSString *)key {
    [self _putValue:@(value) forKey:_MangledKey(key)];
}

- (void)encodeFloat:(float)value forKey:(NSString *)key {
    [self _putValue:@(value) forKey:_MangledKey(key)];
}

- (void)encodeDouble:(double)value forKey:(NSString *)key {
    [self _putValue:@(value) forKey:_MangledKey(key)];
}

- (void)encodeBytes:(const uint8_t *)bytes length:(NSUInteger)length forKey:(NSString *)key {
    key = _MangledKey(key);
    if (bytes == NULL && length == 0) {
        [self _putValue:@"$null" forKey:key];
    } else {
        [self _putValue:[NSData dataWithBytes:bytes length:length] forKey:key];
    }
}

- (void)encodeInteger:(NSInteger)value forKey:(NSString *)key {
    [self _putValue:@(value) forKey:_MangledKey(key)];
}

- (void)finishEncoding {
    if (_finished) {
        return;
    }
    _finished = YES;

    if ([_delegate respondsToSelector:@selector(archiverWillFinish:)]) {
        [_delegate archiverWillFinish:self];
    }

    if ([_top count] == 0) {
        [NSException raise:NSInvalidArchiveOperationException
                    format:@"*** -[NSKeyedArchiver finishEncoding]: no object was encoded"];
    }

    NSDictionary *plist = @{
        @"$archiver": @"NSKeyedArchiver",
        @"$version": @(100000),
        @"$top": _top,
        @"$objects": _objects,
    };

    NSPropertyListFormat format = _outputFormat;
    if (format == NSPropertyListOpenStepFormat) {
        format = NSPropertyListBinaryFormat_v1_0;
    }

    NSError *error = nil;
    NSData *data = [NSPropertyListSerialization dataWithPropertyList:plist
                                                              format:format
                                                             options:0
                                                               error:&error];
    if (data == nil) {
        [NSException raise:NSInvalidArchiveOperationException
                    format:@"*** -[NSKeyedArchiver finishEncoding]: could not serialize archive: %@", error];
    }

    if (_data != nil) {
        [_data setData:data];
    }
    _encodedData = data;

    if ([_delegate respondsToSelector:@selector(archiverDidFinish:)]) {
        [_delegate archiverDidFinish:self];
    }
}

/* The unkeyed primitives have no key: the value goes under a private generated
 * key, one counter shared by every unkeyed value the archiver meets.  The
 * first forty are the cheap cached keys $0..$39; beyond that they carry the
 * long form.  The paired decode runs the same counter on the way back out, so
 * the two match as long as the caller encodes and decodes through exactly the
 * same sequence.  Objects and classes travel as objects; everything else
 * travels as raw bytes. */

- (NSString *)_nextUnkeyedKey {
    NSUInteger n = _unkeyedCount++;
    if (n < 40) {
        return [NSString stringWithFormat:@"$%lu", (unsigned long)n];
    }
    return [NSString stringWithFormat:@"$NSKeyedArchiverKey$%lu", (unsigned long)n];
}

- (void)encodeValueOfObjCType:(const char *)type at:(const void *)addr {
    NSString *key = [self _nextUnkeyedKey];
    switch (*type) {
        case '@': {
            id __unsafe_unretained object = *(__unsafe_unretained id *)addr;
            [self _encodeObject:object forKeyValue:key];
            return;
        }
        case '#': {
            Class cls = *(Class *)addr;
            [self _encodeObject:NSStringFromClass(cls) forKeyValue:key];
            return;
        }
        default: {
            NSUInteger size = 0;
            (void)NSGetSizeAndAlignment(type, &size, NULL);
            NSData *data = [NSData dataWithBytes:addr length:size];
            [self _encodeObject:data forKeyValue:key];
            return;
        }
    }
}

- (void)encodeDataObject:(NSData *)data {
    [self _encodeObject:data forKeyValue:[self _nextUnkeyedKey]];
}

- (void)decodeValueOfObjCType:(const char *)type at:(void *)data size:(NSUInteger)size {
    [NSException raise:NSInvalidArchiveOperationException
                format:@"*** -[NSKeyedArchiver decodeValueOfObjCType:]: archiving only supports writing"];
}

- (NSData *)decodeDataObject {
    [NSException raise:NSInvalidArchiveOperationException
                format:@"*** -[NSKeyedArchiver decodeDataObject]: archiving only supports writing"];
    return nil;
}

- (NSInteger)versionForClassName:(NSString *)className {
    return 0;
}

@end

/* ===================================================================== *
 *  The classes Apple archives through -encodeWithCoder:.  Each container   *
 *  writes its members into arrays and lets the archiver resolve them.      *
 * ===================================================================== */

@implementation NSString (NSKeyedCoder)

- (void)encodeWithCoder:(NSCoder *)coder {
    [coder encodeObject:self forKey:@"NS.string"];
}

- (instancetype)initWithCoder:(NSCoder *)coder {
    return [coder decodeObjectForKey:@"NS.string"];
}

+ (BOOL)supportsSecureCoding {
    return YES;
}

@end

@interface NSData (NSKeyedCoder) <NSSecureCoding>
@end

@implementation NSData (NSKeyedCoder)

- (void)encodeWithCoder:(NSCoder *)coder {
    [coder encodeBytes:(const uint8_t *)[self bytes] length:[self length] forKey:@"NS.data"];
}

- (instancetype)initWithCoder:(NSCoder *)coder {
    NSUInteger length = 0;
    const uint8_t *bytes = [coder decodeBytesForKey:@"NS.data" returnedLength:&length];
    return [NSData dataWithBytes:bytes length:length];
}

+ (BOOL)supportsSecureCoding {
    return YES;
}

@end

@implementation NSMutableData (NSKeyedCoder)

- (void)encodeWithCoder:(NSCoder *)coder {
    [coder encodeBytes:(const uint8_t *)[self bytes] length:[self length] forKey:@"NS.data"];
}

- (instancetype)initWithCoder:(NSCoder *)coder {
    NSUInteger length = 0;
    const uint8_t *bytes = [coder decodeBytesForKey:@"NS.data" returnedLength:&length];
    NSMutableData *data = [NSMutableData dataWithCapacity:length];
    [data appendBytes:bytes length:length];
    return data;
}

+ (BOOL)supportsSecureCoding {
    return YES;
}

@end

@interface NSArray (NSKeyedCoder) <NSSecureCoding>
@end

@implementation NSArray (NSKeyedCoder)

- (void)encodeWithCoder:(NSCoder *)coder {
    [coder _encodeArrayOfObjects:self forKey:@"NS.objects"];
}

- (instancetype)initWithCoder:(NSCoder *)coder {
    return [[coder decodeObjectForKey:@"NS.objects"] copy];
}

+ (BOOL)supportsSecureCoding {
    return YES;
}

@end

@implementation NSMutableArray (NSKeyedCoder)

- (void)encodeWithCoder:(NSCoder *)coder {
    [coder _encodeArrayOfObjects:self forKey:@"NS.objects"];
}

- (instancetype)initWithCoder:(NSCoder *)coder {
    return [[coder decodeObjectForKey:@"NS.objects"] mutableCopy];
}

+ (BOOL)supportsSecureCoding {
    return YES;
}

@end

@interface NSDictionary (NSKeyedCoder) <NSSecureCoding>
@end

@implementation NSDictionary (NSKeyedCoder)

/* The keys and objects must stay in matching order.  Apple reads them out
 * pairwise; here we walk fast enumeration once, filling parallel arrays, so
 * key[i] always pairs with object[i] even though hashing order is arbitrary. */
- (void)encodeWithCoder:(NSCoder *)coder {
    NSArray *keys = [self allKeys];
    NSMutableArray *keysOrdered = [NSMutableArray arrayWithCapacity:[keys count]];
    NSMutableArray *valuesOrdered = [NSMutableArray arrayWithCapacity:[keys count]];
    for (id key in keys) {
        [keysOrdered addObject:key];
        [valuesOrdered addObject:self[key]];
    }
    [coder _encodeArrayOfObjects:keysOrdered forKey:@"NS.keys"];
    [coder _encodeArrayOfObjects:valuesOrdered forKey:@"NS.objects"];
}

- (instancetype)initWithCoder:(NSCoder *)coder {
    NSArray *keys = [coder decodeObjectForKey:@"NS.keys"];
    NSArray *values = [coder decodeObjectForKey:@"NS.objects"];
    NSMutableDictionary *dict = [NSMutableDictionary dictionaryWithCapacity:[keys count]];
    for (NSUInteger i = 0; i < [keys count]; i++) {
        dict[keys[i]] = values[i];
    }
    return [dict copy];
}

+ (BOOL)supportsSecureCoding {
    return YES;
}

@end

@implementation NSMutableDictionary (NSKeyedCoder)

- (void)encodeWithCoder:(NSCoder *)coder {
    NSArray *keys = [self allKeys];
    NSMutableArray *keysOrdered = [NSMutableArray arrayWithCapacity:[keys count]];
    NSMutableArray *valuesOrdered = [NSMutableArray arrayWithCapacity:[keys count]];
    for (id key in keys) {
        [keysOrdered addObject:key];
        [valuesOrdered addObject:self[key]];
    }
    [coder _encodeArrayOfObjects:keysOrdered forKey:@"NS.keys"];
    [coder _encodeArrayOfObjects:valuesOrdered forKey:@"NS.objects"];
}

- (instancetype)initWithCoder:(NSCoder *)coder {
    NSArray *keys = [coder decodeObjectForKey:@"NS.keys"];
    NSArray *values = [coder decodeObjectForKey:@"NS.objects"];
    NSMutableDictionary *dict = [NSMutableDictionary dictionaryWithCapacity:[keys count]];
    for (NSUInteger i = 0; i < [keys count]; i++) {
        dict[keys[i]] = values[i];
    }
    return dict;
}

+ (BOOL)supportsSecureCoding {
    return YES;
}

@end

@interface NSSet (NSKeyedCoder) <NSSecureCoding>
@end

@implementation NSSet (NSKeyedCoder)

- (void)encodeWithCoder:(NSCoder *)coder {
    [coder _encodeArrayOfObjects:[self allObjects] forKey:@"NS.objects"];
}

- (instancetype)initWithCoder:(NSCoder *)coder {
    return [NSSet setWithArray:[coder decodeObjectForKey:@"NS.objects"]];
}

+ (BOOL)supportsSecureCoding {
    return YES;
}

@end

/* NSMutableString has a body of its own to encode as an object; NSString does
 * not, because it never reaches this path -- it is one of the leaf classes
 * and is always interned.  NSMutableString's name keeps it out of the leaf
 * set, so it arrives here. */

@implementation NSObject (NSKeyedArchiverObjectSubstitution)

- (Class)classForKeyedArchiver {
    return [self class];
}

- (id)replacementObjectForKeyedArchiver:(NSKeyedArchiver *)archiver {
    return self;
}

+ (NSArray<NSString *> *)classFallbacksForKeyedArchiver {
    return @[];
}

@end

@implementation NSObject (NSKeyedUnarchiverObjectSubstitution)

+ (Class)classForKeyedUnarchiver {
    return self;
}

@end