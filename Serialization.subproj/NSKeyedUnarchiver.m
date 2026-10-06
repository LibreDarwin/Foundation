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
#import <Foundation/NSValue.h>
#import <Foundation/NSDate.h>
#import <Foundation/NSURL.h>
#include <CoreFoundation/CFArray.h>
#include <CoreFoundation/CFData.h>
#include <CoreFoundation/CFDictionary.h>
#include <CoreFoundation/CFNumber.h>
#include <CoreFoundation/CFString.h>
#include <CoreFoundation/ForFoundationOnly.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <objc/runtime.h>
#include <dlfcn.h>
#include <sys/stat.h>

/* The archive is a property list.  Everything below reads through that
 * structure: $objects is an array of values and nodes, $top a dictionary of
 * the root keys, and every reference is either a leaf value (string, number,
 * data) standing in $objects directly, or a {"CF$UID": n} token, or a node --
 * a dictionary holding $class plus the keyed members, or a class node holding
 * $classname and $classes.  Resolving a token follows the reference; resolving
 * a node instantiates the class and runs -initWithCoder:. */

/* Type tests for values that came out of a property list.
 *
 * These are all CoreFoundation-toll-free types, so CoreFoundation is the
 * authority on what they are, and it is the port's own convention elsewhere
 * (NSDictionary.m checks a plist with CFGetTypeID too).  isKindOfClass: is
 * not usable here: a plist value produced by CoreFoundation answers to
 * CoreFoundation's class (__NSDictionaryI, __NSCFConstantString, ...) while
 * [NSDictionary class] names the port's own class, so the identity test
 * reports a mismatch for every value.  Only ever call this on plist values,
 * which are always CoreFoundation objects. */
static BOOL _PlistIsDict(id value) {
    return value != nil && CFGetTypeID((__bridge CFTypeRef)value) == CFDictionaryGetTypeID();
}

static BOOL _PlistIsArray(id value) {
    return value != nil && CFGetTypeID((__bridge CFTypeRef)value) == CFArrayGetTypeID();
}

static BOOL _PlistIsString(id value) {
    return value != nil && CFGetTypeID((__bridge CFTypeRef)value) == CFStringGetTypeID();
}

static BOOL _PlistIsData(id value) {
    return value != nil && CFGetTypeID((__bridge CFTypeRef)value) == CFDataGetTypeID();
}

static BOOL _PlistIsNumber(id value) {
    return value != nil && CFGetTypeID((__bridge CFTypeRef)value) == CFNumberGetTypeID();
}

/* Read a uid reference.  A binary property list parses a real UID marker back
 * out as a CFKeyedArchiverUID, which is what the archiver writes; the
 * {"CF$UID": n} dictionary is the older textual form and is still accepted so
 * that archives written either way read back. */
static BOOL _UIDOfToken(id token, NSUInteger *outUID) {
    if (token == nil) {
        return NO;
    }
    if (CFGetTypeID((__bridge CFTypeRef)token) == _CFKeyedArchiverUIDGetTypeID()) {
        if (outUID != NULL) {
            *outUID = (NSUInteger)_CFKeyedArchiverUIDGetValue(
                (__bridge CFKeyedArchiverUIDRef)token);
        }
        return YES;
    }
    if (_PlistIsDict(token)) {
        id inner = ((NSDictionary *)token)[@"CF$UID"];
        if (_PlistIsNumber(inner)) {
            if (outUID != NULL) {
                *outUID = (NSUInteger)[inner unsignedIntegerValue];
            }
            return YES;
        }
    }
    return NO;
}

/* The inverse of the archiver's key mangling.  A key that begins with '$' has
 * had a second '$' prepended by the writer, so the reader strips one '$' only
 * from a "$$" key: that is the exact inverse of the writer, and it leaves a
 * single leading '$' alone instead of eating a character the caller asked
 * for. */
static NSString *_DecodedKey(NSString *key) {
    if (key != nil && [key length] > 1 &&
        [key characterAtIndex:0] == '$' && [key characterAtIndex:1] == '$') {
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

/*
 * Resolving a coded class name with NSClassFromString goes through the global
 * runtime, and this Foundation is built and linked next to a host Foundation
 * that already publishes classes under the very same names.  A name lookup
 * cannot tell the two apart, so an archive naming "NSValue" can be handed back
 * either implementation, and which one arrives depends on load order.  A
 * decodable class has to be the one whose -initWithCoder: understands the
 * archive, so the classes are resolved out of the set this Foundation itself
 * defines.
 *
 * "This Foundation" is decided by the image the class was defined in, found
 * from a symbol in this file, rather than by name, so a class keeps resolving
 * to our implementation whether the linker bound the reference to ours or the
 * host's.
 *
 * A class that only wraps a host object is not an implementation, but it does
 * know which host object it stands for.  The collection and string types here
 * are toll-free views over CoreFoundation, so their -init hands back the host's
 * object rather than one of their own, and that host class is what the name
 * decodes into -- its -initWithCoder: is the one CoreFoundation already
 * implements for this format.  A class this Foundation really builds, such as
 * NSValue or NSIndexSet, decodes into its own instances directly.
 *
 * An unrecognised name still falls through to the instance and global tables and
 * then to the runtime, which is what a class defined by the application relies
 * on.
 */
static Class _PortClassForDecoding(Class cls) {
    id instance = [[cls alloc] init];
    if (instance == nil) {
        return Nil;
    }
    Class actual = object_getClass(instance);
    return actual == cls ? cls : actual;
}

static const char *_PortImagePath(void) {
    Dl_info info;
    if (dladdr((const void *)_PortImagePath, &info) && info.dli_fname != NULL) {
        return info.dli_fname;
    }
    return NULL;
}

/* The two paths that have to be compared can be spelled differently -- one
 * side reports the name the image was loaded under, the other the resolved
 * location -- so identity is settled by the file itself where it can be, and
 * only falls back to the spelling when it cannot be. */
static BOOL _PortImageIs(const char *image) {
    static struct stat portStat;
    static int resolved;
    if (!resolved) {
        const char *own = _PortImagePath();
        resolved = (own != NULL && stat(own, &portStat) == 0) ? 1 : 0;
    }
    if (!resolved) {
        return NO;
    }
    struct stat other;
    if (stat(image, &other) != 0) {
        return NO;
    }
    return portStat.st_dev == other.st_dev && portStat.st_ino == other.st_ino;
}


static Class _PortCodedClass(NSString *name) {
    static NSDictionary *byName;
    if (byName == nil) {
        NSMutableDictionary *defined = [[NSMutableDictionary alloc] init];
        const char *image = _PortImagePath();
        if (image != NULL) {
            unsigned int count = objc_getClassList(NULL, 0);
            if (count > 0) {
                Class *classes = (Class *)malloc(sizeof(Class) * count);
                if (classes != NULL) {
                    count = objc_getClassList(classes, count);
                    for (unsigned int i = 0; i < count; i++) {
                        const char *where = class_getImageName(classes[i]);
                        if (where == NULL || !_PortImageIs(where)) {
                            continue;
                        }
                        const char *className = class_getName(classes[i]);
                        if (className == NULL || strlen(className) == 0) {
                            continue;
                        }
                        /* First definition wins, which keeps a category's
                         * replacement from displacing the class itself. */
                        NSString *key = [NSString stringWithUTF8String:className];
                        if ([defined objectForKey:key] == nil) {
                            [defined setObject:classes[i] forKey:key];
                        }
                    }
                    free(classes);
                }
            }
        }

        NSMutableDictionary *table = [[NSMutableDictionary alloc] init];
        NSArray *names = [defined allKeys];
        for (NSString *key in names) {
            Class decodable = _PortClassForDecoding([defined objectForKey:key]);
            if (decodable != Nil) {
                [table setObject:decodable forKey:key];
            }
        }
        byName = [table copy];
    }
    return byName[name];
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
    BOOL _unreadable; /* the bytes are not a keyed archive: answer nil, say nothing */
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

    [self _readArchiveFromData:data];
    return self;
}

/* Reading the archive out of the bytes.  Both initialisers differ only in how
 * they report a failure, so the parse lives here: YES leaves $objects and $top
 * in place, NO means there is no archive to read.  Bytes that are not a
 * property list at all are "no archive" the way Apple treats them -- the
 * legacy reader hands back nil and the error-taking one leaves its error
 * alone -- so those carry no error.  Bytes that do open as a property list but
 * are not shaped like a keyed archive are a corrupt archive, and keep the
 * 4864 the reader has always reported. */
- (BOOL)_readArchiveFromData:(NSData *)data {
    NSError *plistError = nil;
    NSPropertyListFormat format = NSPropertyListOpenStepFormat;
    id plist = [NSPropertyListSerialization propertyListWithData:data
                                                          options:NSPropertyListImmutable
                                                           format:&format
                                                            error:&plistError];
    if (plist == nil || !_PlistIsDict(plist)) {
        _unreadable = YES;
        return NO;
    }

    NSDictionary *archive = (NSDictionary *)plist;
    if (![[archive objectForKey:@"$archiver"] isEqual:@"NSKeyedArchiver"] ||
        ![[archive objectForKey:@"$version"] isEqual:@(100000)]) {
        _error = [NSError errorWithDomain:NSCocoaErrorDomain
                                     code:NSCoderReadCorruptError
                                 userInfo:nil];
        return NO;
    }

    id objects = archive[@"$objects"];
    id top = archive[@"$top"];
    if (!_PlistIsArray(objects) || !_PlistIsDict(top)) {
        _error = [NSError errorWithDomain:NSCocoaErrorDomain
                                     code:NSCoderReadCorruptError
                                 userInfo:nil];
        return NO;
    }

    _archive = archive;
    _objects = objects;
    _top = top;
    return YES;
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

    if (![self _readArchiveFromData:data]) {
        if (!_unreadable && _error != nil && error != NULL) {
            *error = _error;
        }
        return nil;
    }

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
        /* Bytes that are not a keyed archive at all leave the initialiser's
         * error alone, so the class-restricted reader still says why it handed
         * back nothing. */
        if (error != NULL && *error == nil) {
            *error = [NSError errorWithDomain:NSCocoaErrorDomain
                                         code:NSCoderReadCorruptError
                                     userInfo:nil];
        }
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
    if (_unreadable) {
        return nil;
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
    NSUInteger uid = 0;
    if (_UIDOfToken(value, &uid)) {
        return [self _objectForUID:uid];
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
    NSUInteger scalarUID = 0;
    if (_UIDOfToken(value, &scalarUID)) {
        value = [self _objectForUID:scalarUID];
    }

    if (_PlistIsString(value)) {
        if ([value isEqual:@"$null"]) {
            return NULL;
        }
        [self _failCorrupt];
        return NULL;
    }

    if (!_PlistIsData(value)) {
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
            if (value != nil && _PlistIsString(value)) {
                cls = NSClassFromString(value);
            }
            if (data != NULL) {
                *(Class *)data = cls;
            }
            return;
        }
        default: {
            id value = [self _readValueForKey:key];
            if (_PlistIsData(value)) {
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
    if (_PlistIsData(value)) {
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

    NSUInteger refUID = 0;
    if (_UIDOfToken(value, &refUID)) {
        return [self _objectForUID:refUID];
    }

    if (_PlistIsDict(value)) {
        if (value[@"$classname"] != nil) {
            return (id)[self _classForNode:value];
        }
        if (value[@"$class"] != nil) {
            return [self _decodeInstanceForUID:NSNotFound node:value];
        }
        return value;
    }

    if (_PlistIsArray(value)) {
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

    NSUInteger nestedUID = 0;
    if (_UIDOfToken(token, &nestedUID)) {
        return [self _objectForUID:nestedUID];
    }

    if (_PlistIsString(token)) {
        if ([token isEqual:@"$null"]) {
            return nil;
        }
        _uidToObject[key] = token;
        return token;
    }

    if (_PlistIsNumber(token) || _PlistIsData(token)) {
        _uidToObject[key] = token;
        return token;
    }

    if (_PlistIsArray(token)) {
        NSMutableArray *array = [NSMutableArray arrayWithCapacity:[token count]];
        for (id element in token) {
            [array addObject:[self _objectForObject:element]];
        }
        _uidToObject[key] = array;
        return array;
    }

    if (_PlistIsDict(token)) {
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

/*
 * Collections are built here rather than by sending the archive to a class.
 *
 * The collection types are toll-free views over CoreFoundation, so a class
 * allocated for one of them hands back the host's object instead of one of its
 * own, and for an immutable array that object is the host's empty-singleton
 * class, which cannot hold elements at all.  The archive's own -initWithCoder:
 * on that class reaches an initializer CoreFoundation refuses to run, because
 * whether that initializer is usable depends on the receiver rather than on the
 * class: the same implementation that fills a mutable array is refused for the
 * class behind an immutable one.  No choice of class avoids that, so the
 * elements are read out of the node here and the collection is built from them
 * with the constructors this Foundation defines.
 *
 * The keys read are the ones the archiver writes, which is the same layout
 * Foundation uses: a list under NS.objects for an array and a set, and separate
 * NS.keys and NS.objects lists for a dictionary.
 */
static BOOL _PortCollectionIsDictionary(NSString *codedName) {
    return [codedName isEqualToString:@"NSDictionary"] ||
           [codedName isEqualToString:@"NSMutableDictionary"];
}

static BOOL _PortCollectionIsSet(NSString *codedName) {
    return [codedName isEqualToString:@"NSSet"] ||
           [codedName isEqualToString:@"NSMutableSet"];
}

static BOOL _PortCollectionIsMutable(NSString *codedName) {
    return [codedName hasPrefix:@"NSMutable"];
}

static BOOL _PortCodedDataIsData(NSString *codedName) {
    return [codedName isEqualToString:@"NSData"] ||
           [codedName isEqualToString:@"NSMutableData"];
}

static BOOL _PortCollectionIsBuiltHere(NSString *codedName) {
    return [codedName isEqualToString:@"NSArray"] ||
           [codedName isEqualToString:@"NSMutableArray"] ||
           _PortCollectionIsSet(codedName) ||
           _PortCollectionIsDictionary(codedName);
}

- (id)_decodeCollectionForUID:(NSUInteger)uid node:(NSDictionary *)node
                      codedName:(NSString *)codedName {
    BOOL isDictionary = _PortCollectionIsDictionary(codedName);
    BOOL isSet = _PortCollectionIsSet(codedName);
    BOOL isMutable = _PortCollectionIsMutable(codedName);

    id container = isDictionary ? (id)[[NSMutableDictionary alloc] init]
                               : (id)[[NSMutableArray alloc] init];

    /* Published before the elements are read so that a node referring back to
     * this one finds it, the way a mutable placeholder would. */
    NSNumber *key = @(uid);
    _uidToObject[key] = container;

    [self _pushContainer:node];
    id objects = [self _readValueForKey:@"NS.objects"];
    id entryKeys = isDictionary ? [self _readValueForKey:@"NS.keys"] : nil;
    [self _popContainer];
    if (getenv("PORT_KA_TRACE") != NULL) {
        fprintf(stderr, "TRACE coll-read %s objects=%s count=%lu nodekeys=%s\n",
                [codedName UTF8String],
                objects ? object_getClassName(objects) : "(nil)",
                (unsigned long)[objects count],
                [[[node allKeys] sortedArrayUsingSelector:@selector(compare:)] description].UTF8String);
    }

    if (!_PlistIsArray(objects) || (isDictionary && !_PlistIsArray(entryKeys))) {
        [self _failCorrupt];
        _uidToObject[key] = [NSNull null];
        return nil;
    }

    NSUInteger count = [objects count];
    if (isDictionary) {
        /* The two lists have to describe the same entries, in the same order. */
        if ([entryKeys count] != count) {
            [self _failCorrupt];
            _uidToObject[key] = [NSNull null];
            return nil;
        }
        for (NSUInteger i = 0; i < count; i++) {
            id object = [objects objectAtIndex:i];
            id entryKey = [entryKeys objectAtIndex:i];
            if (object == nil || entryKey == nil) {
                [self _failCorrupt];
                _uidToObject[key] = [NSNull null];
                return nil;
            }
            [container setObject:object forKey:entryKey];
        }
        id result = isMutable ? container : [container copy];
        _uidToObject[key] = result;
        return result;
    }

    for (id element in objects) {
        if (element == nil) {
            [self _failCorrupt];
            _uidToObject[key] = [NSNull null];
            return nil;
        }
        [container addObject:element];
    }

    if (isSet) {
        id set = [NSSet setWithArray:container];
        id result = isMutable ? [set mutableCopy] : set;
        _uidToObject[key] = result;
        return result;
    }

    id result = isMutable ? container : [container copy];
    if (getenv("PORT_KA_TRACE") != NULL) {
        fprintf(stderr, "TRACE coll-done %s -> %s count=%lu\n",
                [codedName UTF8String], object_getClassName(result),
                (unsigned long)[result count]);
    }
    _uidToObject[key] = result;
    return result;
}

/*
 * Data is another host-drawn type: the Foundation NSData and NSMutableData
 * classes the archive names live in CoreFoundation, and no allocator descended
 * from them can be told to build a new instance.  The bytes the writer saved
 * under NS.data are pulled out in the same way the collection builders read
 * their element lists, and the value is made with the Data constructors this
 * Foundation defines so the decoded object is never a host placeholder.
 */
- (NSData *)_decodeDataForUID:(NSUInteger)uid node:(NSDictionary *)node
                       codedName:(NSString *)codedName {
    BOOL isMutable = [codedName isEqualToString:@"NSMutableData"];

    [self _pushContainer:node];
    NSUInteger length = 0;
    const uint8_t *bytes = [self decodeBytesForKey:@"NS.data" returnedLength:&length];
    [self _popContainer];

    if (bytes == NULL && length > 0) {
        [self _failCorrupt];
        return nil;
    }

    id data = isMutable ? (id)[NSMutableData dataWithBytes:bytes length:length]
                        : (id)[NSData dataWithBytes:bytes length:length];

    NSNumber *key = @(uid);
    _uidToObject[key] = data;
    return data;
}

- (id)_decodeInstanceForUID:(NSUInteger)uid node:(NSDictionary *)node {
    Class cls = [self _classForNode:node];
    if (cls == Nil) {
        return nil;
    }

    NSString *codedName = [self _codedNameForNode:node];
    /* The structural containers and data are rebuilt from their plist leaves
     * rather than by allocating the archive's class, so their decoded node
     * never runs the class's -initWithCoder:.  Nothing of theirs is classed
     * state either -- a container holds only plist leaves and further nodes of
     * its own kind -- so the secure coder does not gate nested containers
     * against the allowed set; the classes it does gate are the ones that are
     * actually instantiated below, which is what a secure archive's
     * restrictions are about.  The value reached from the top-level dictionary
     * is the object the caller asked for, so it is checked like any other
     * decoded class: the allowed set must admit it even when it is a container
     * (a secure decode of an array under an NSAttributedString-only set must
     * refuse it). */
    BOOL atTopLevel = ([_containerStack count] == 0);
    if (codedName != nil && _PortCollectionIsBuiltHere(codedName)) {
        if (atTopLevel) {
            [self _validateClass:cls];
        }
        return [self _decodeCollectionForUID:uid node:node codedName:codedName];
    }
    if (codedName != nil && _PortCodedDataIsData(codedName)) {
        if (atTopLevel) {
            [self _validateClass:cls];
        }
        return [self _decodeDataForUID:uid node:node codedName:codedName];
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
 * Class lookup.  An instance node points at its class through $class, and that
 * reference resolves to a class object; a class node carries $classname and
 * $classes itself.  So the instance case is finished by the $class lookup, and
 * only a node with no $class is a class node to be read by name.  The instance
 * table, the shared table and NSClassFromString are tried in that order, then
 * the fallback class names the archive saved, then the delegate.  A class that
 * names itself a substitute through +classForKeyedUnarchiver is honoured.
 */

- (NSString *)_codedNameForNode:(NSDictionary *)node {
    /* The class node is read straight out of $objects rather than through
     * -_objectForUID:, which would hand back the class it resolves to instead of
     * the node the name is written in. */
    id classValue = node[@"$class"];
    NSUInteger classUID = 0;
    if (_UIDOfToken(classValue, &classUID) && classUID < [_objects count]) {
        id classNode = _objects[classUID];
        if (_PlistIsDict(classNode)) {
            id name = ((NSDictionary *)classNode)[@"$classname"];
            if (_PlistIsString(name)) {
                return name;
            }
        }
    }
    id name = node[@"$classname"];
    return _PlistIsString(name) ? name : nil;
}

- (Class)_classForNode:(NSDictionary *)node {
    id classValue = node[@"$class"];
    NSUInteger classUID = 0;
    if (_UIDOfToken(classValue, &classUID)) {
        id resolved = [self _objectForUID:classUID];
        if (resolved != nil && object_isClass(resolved)) {
            return (Class)resolved;
        }
    }

    id name = node[@"$classname"];
    if (!_PlistIsString(name)) {
        [self _failCorrupt];
        return Nil;
    }
    id classes = node[@"$classes"];
    NSArray *fallbacks = _PlistIsArray(classes) ? classes : @[];
    return [self _classForCodedName:name fallbacks:fallbacks];
}

- (Class)_classForCodedName:(NSString *)name fallbacks:(NSArray *)fallbacks {
    /* Only the coded name names the class to instantiate.  The $classes list is
     * the hierarchy the writer saved -- coded name first, supers after -- and
     * it is handed to the delegate as originalClasses:, but a superclass is
     * never silently decoded in place of a class the archive named: that would
     * turn a class rename into a quietly wrong object. */
    Class cls = _PortCodedClass(name);
    if (cls == Nil) {
        cls = _instanceClassNames[name];
    }
    if (cls == Nil) {
        cls = _UnarchiverGlobalClassesByName[name];
    }
    if (cls == Nil) {
        cls = NSClassFromString(name);
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
        /* A named class the runtime does not have is 4865, the code Apple
         * reports for a value the archive names but nothing can supply. */
        [self failWithError:[NSError errorWithDomain:NSCocoaErrorDomain
                                                code:NSCoderValueNotFoundError
                                            userInfo:@{NSLocalizedDescriptionKey:
                [NSString stringWithFormat:@"class %@ is not in the archive's class list",
                                           name]}]];
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