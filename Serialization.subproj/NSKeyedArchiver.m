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
#include <objc/runtime.h>
#include <CoreFoundation/ForFoundationOnly.h>
#include <CoreFoundation/CFPropertyList.h>
#include <CoreFoundation/CFData.h>
#include <CoreFoundation/CFNumber.h>
#include <CoreFoundation/CFString.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

NSString * const NSKeyedArchiveRootObjectKey = @"root";

/* Type tests for the toll-free leaf and container classes.
 *
 * These classes have two names each: the port's own (NSDictionary) and
 * CoreFoundation's (__NSDictionaryI), depending on which side produced the
 * object.  isKindOfClass: can only see one of them, so a string that came from
 * CoreFoundation fails [object isKindOfClass:[NSString class]] and falls
 * through to -encodeWithCoder:.  Ask CoreFoundation for the type instead; the
 * port already leans on CFGetTypeID this way for arbitrary input in
 * NSNumberFormatter and NSScanner. */
static inline BOOL _IsCFKind(id object, CFTypeID type) {
    return object != nil && CFGetTypeID((__bridge CFTypeRef)object) == type;
}

static inline BOOL _IsPlistString(id object) {
    return _IsCFKind(object, CFStringGetTypeID());
}

static inline BOOL _IsPlistNumber(id object) {
    return _IsCFKind(object, CFNumberGetTypeID());
}

static inline BOOL _IsPlistData(id object) {
    return _IsCFKind(object, CFDataGetTypeID());
}

/* The three collection types are written here rather than by their own coder.
 *
 * An array, set or dictionary in this Foundation is a CoreFoundation object, so
 * the coder that runs for one is CoreFoundation's, and it writes its elements
 * under generated keys -- NS.object.0, NS.object.1 and so on.  A keyed archive
 * spells the list out instead: the element references sit directly in the node
 * under NS.objects, and a dictionary keeps its keys in a second list of their
 * own.  Writing that from the collection's contents also keeps the element list
 * out of $objects, which is where a keyed archive keeps it: the list is part of
 * the node, not an object with a reference of its own. */
static BOOL _IsPlistCollection(id object) {
    return _IsCFKind(object, CFArrayGetTypeID()) ||
           _IsCFKind(object, CFSetGetTypeID()) ||
           _IsCFKind(object, CFDictionaryGetTypeID());
}

/* A property list is written by handing the writer a graph of objects, and the
 * writer decides what to keep by object identity: two equal strings or numbers
 * that are the same object are written once, and two that are merely equal are
 * written twice.  Which of those two happens is decided before the writer is
 * involved, because on Apple platforms a small number and a short ASCII string
 * are held as a tagged pointer -- the value is the pointer, so writing the same
 * value a second time produces the same object -- while anything too big to tag
 * is a separate object every time.  The limits are the runtime's: an integer of
 * at most 2^55 - 1, and 11 characters.  An archive is a byte format, so the
 * archiver has to hand the writer the same identities Apple would; a number
 * beyond the limit, a real, and a long string each go in as themselves.
 *
 * Returns the key that identifies the value, or nil when the value is one of
 * the objects the writer will write out again. */
static NSString *_SharedPlistScalarKey(id value) {
    if (_IsPlistString(value)) {
        NSString *string = value;
        if ([string length] > 11) {
            return nil;
        }
        for (NSUInteger i = 0; i < [string length]; i++) {
            if ([string characterAtIndex:i] > 0x7F) {
                return nil;              /* a tagged string is ASCII */
            }
        }
        return [@"$s:" stringByAppendingString:string];
    }
    if (_IsPlistNumber(value)) {
        double real = [value doubleValue];
        if (real < 0.0 || real >= 36028797018963968.0) {     /* 2^55, exclusive */
            return nil;
        }
        if (real != (double)(long long)real && real != (double)(unsigned long long)real) {
            return nil;                  /* a real is not tagged */
        }
        return [NSString stringWithFormat:@"$n:%llu", (unsigned long long)real];
    }
    return nil;
}

/* The leaf classes.  An instance of one of these is written directly into the
 * $objects array and referenced by uid, the same way a plain plist stores
 * them.  Everything else has to pass through -encodeWithCoder:, which is what
 * "keyed coding" means for the rest.  The test is on the type, not on the
 * class name: a toll-free leaf is still a leaf when CoreFoundation, rather than
 * the port, is what named its class. */
static inline BOOL _IsImmediateArchivedClass(id object, NSString *name) {
    (void)name;
    return _IsPlistString(object) || _IsPlistNumber(object) || _IsPlistData(object);
}

/* The uid marker, written as the value of an encoded object reference.
 *
 * This is a CFKeyedArchiverUID rather than the {"CF$UID": n} dictionary the
 * older OpenStep-era format used.  The binary plist writer recognises the
 * former and emits a real UID marker (kCFBinaryPlistMarkerUID); a plain
 * dictionary goes out as an ordinary dictionary, which is neither the same
 * bytes nor something the reader treats as a reference.
 *
 * One token object per uid, shared by every reference to it.  The plist
 * writer walks the finished archive and folds an object it has already seen
 * back onto its first position, so a uid that is referenced twice has to
 * arrive as one object: handing over two equal-but-distinct tokens writes two
 * markers and the second reference lands on the second marker instead of the
 * first.  Apple hands the same object to both references, and that is what
 * keeps the repeated reference pointing at the first marker. */
static id _NewUIDToken(NSUInteger uid) {
    return (__bridge id)_CFKeyedArchiverUIDCreate(kCFAllocatorDefault, (uint32_t)uid);
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
- (NSUInteger)_encodeClassNodeNamed:(NSString *)name;
- (void)_resolveConditionalsForObject:(id)object uid:(NSUInteger)uid;
- (id)_identifiedObject:(id)object;
- (void)_checkSecureObject:(id)object;
- (void)_putValue:(id)value forKey:(NSString *)key;
- (id)_sharedPlistScalar:(id)value;
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
    NSMutableDictionary *_sharedScalars;   /* tagged-scalar key -> the one object for that value */
    NSMutableDictionary *_sharedClassNames; /* class name -> the one object for that name */
    NSMutableDictionary *_uidTokens;       /* uid -> the one uid object every reference to it shares */
    NSString *_writingKey;             /* the key of the node currently being written */
    NSPropertyListFormat _outputFormat;
    NSUInteger _unkeyedCount;
    BOOL _requiresSecureCoding;
    BOOL _finished;
    NSError *_writeError; /* why this archiver refused, for the error-taking API */
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
    _sharedScalars = [[NSMutableDictionary alloc] init];
    _sharedClassNames = [[NSMutableDictionary alloc] init];
    _uidTokens = [[NSMutableDictionary alloc] init];
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
        /* The archiver's own refusal wins, because it knows what it refused;
         * anything else is a failure the writer has no finer word for. */
        NSError *reported = archiver->_writeError;
        if (reported == nil) {
            reported = [NSError errorWithDomain:NSCocoaErrorDomain
                                           code:NSCoderWriteInsufficientMemoryError
                                       userInfo:@{NSLocalizedDescriptionKey: [e reason]}];
        }
        if (error != NULL) {
            *error = reported;
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
    container[[self _sharedPlistScalar:key]] = [self _sharedPlistScalar:value];
}

/* The one object the property list writer will see for a class name.
 *
 * A class node holds its name twice, as $classname and as the head of $classes,
 * and Apple builds those two strings separately.  The writer only folds two
 * objects together when they are the same object, and the two name strings are
 * the same object exactly when the name is short enough for the runtime to hand
 * out as a tagged pointer: at most nine ASCII characters.  So NSArray and
 * NSObject are written once, and NSIndexSet and NSOrderedSet are written twice.
 *
 * That limit is the runtime's, and it is lower than the eleven characters a
 * tagged property list scalar gets in _SharedPlistScalarKey: the two are
 * different taggings, one by the runtime and one by the writer, and they only
 * happen to agree for the short names a class usually has. */
- (id)_sharedClassName:(NSString *)name {
    if ([name length] > 9) {
        return name;
    }
    for (NSUInteger i = 0; i < [name length]; i++) {
        if ([name characterAtIndex:i] > 0x7F) {
            return name;                /* a tagged string is ASCII */
        }
    }
    id shared = _sharedClassNames[name];
    if (shared == nil) {
        _sharedClassNames[name] = name;
        return name;
    }
    return shared;
}

/* The one object the property list writer will see for a scalar, which is the
 * object already used for that value if the value is one that Apple holds as a
 * tagged pointer.  See _SharedPlistScalarKey. */
- (id)_sharedPlistScalar:(id)value {
    if (!_IsPlistString(value) && !_IsPlistNumber(value)) {
        return value;
    }
    NSString *key = _SharedPlistScalarKey(value);
    if (key == nil) {
        return value;
    }
    id shared = _sharedScalars[key];
    if (shared == nil) {
        _sharedScalars[key] = value;
        return value;
    }
    return shared;
}

- (void)_checkSecureObject:(id)object {
    if (!_requiresSecureCoding || object == nil) {
        return;
    }
    if (_IsPlistString(object) || _IsPlistNumber(object) || _IsPlistData(object)) {
        return;
    }
    if (![object conformsToProtocol:@protocol(NSSecureCoding)]) {
        /* The refusal is a value the archiver will not write, so the
         * error-taking API reports it as 4866 rather than as a memory
         * problem; -_writeError keeps the code honest about which. */
        NSString *reason = [NSString stringWithFormat:
            @"class %@ does not implement NSSecureCoding", NSStringFromClass([object class])];
        if (_writeError == nil) {
            _writeError = [NSError errorWithDomain:NSCocoaErrorDomain
                                              code:NSCoderInvalidValueError
                                          userInfo:@{NSLocalizedDescriptionKey: reason}];
        }
        [NSException raise:NSInvalidArgumentException
                    format:@"*** -[NSKeyedArchiver encodeObject:forKey:]: %@", reason];
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

/* The class a value is written under.  A CoreFoundation value is a private
 * implementation subclass of the Foundation class it stands in for -- a
 * __NSTaggedDate is an NSDate, an __NSConcreteValue is an NSValue -- and
 * Foundation archives it under the public name, never the private one.  Naming
 * the concrete class would make the archive unreadable to anything but this
 * process, and would not match what Foundation itself writes. */
static Class _PublicCodedClass(Class cls) {
    if (cls == Nil) {
        return Nil;
    }
    NSString *name = NSStringFromClass(cls);
    if (![name hasPrefix:@"_"]) {
        return cls;
    }
    for (Class superclass = class_getSuperclass(cls);
         superclass != Nil;
         superclass = class_getSuperclass(superclass)) {
        NSString *superName = NSStringFromClass(superclass);
        if (![superName hasPrefix:@"_"]) {
            return superclass;
        }
    }
    return cls;
}

/* The name an object is written as: the archiver's own table, the global
 * table, the class's own substitution, then its real name. */
- (NSString *)_codedNameForObject:(id)object {
    Class observed = [object classForKeyedArchiver];
    if (observed == Nil) {
        observed = [object class];
    }
    observed = _PublicCodedClass(observed);
    NSString *name = [self classNameForClass:observed];
    if (name == nil) {
        name = NSStringFromClass(observed);
    }
    return name;
}

/* The name of the class node: the coded name, and -- when that name is a class
 * the runtime knows -- the chain of superclasses down to NSObject. */
- (NSUInteger)_encodeClassNodeNamed:(NSString *)name {
    NSNumber *cached = _nameToClassUid[name];
    if (cached != nil) {
        return [cached unsignedIntegerValue];
    }

    NSMutableDictionary *node = [[NSMutableDictionary alloc] init];
    node[@"$classname"] = [self _sharedClassName:name];
    /* $classes records the hierarchy of the class the name resolves to, and a
     * name that resolves to nothing has no hierarchy to record.  A name
     * swapped in with -setClassName:forClass: is exactly that: the archive
     * names a class that was never there, and Apple writes $classname alone.
     * The reader is left to fail on the unknown name, which is what it does. */
    Class resolved = NSClassFromString(name);
    if (resolved != Nil) {
        NSMutableArray *classes = [NSMutableArray arrayWithCapacity:1];
        /* A class node names its class twice, once for $classname and once as
         * the head of $classes, and Apple builds those two names separately.  A
         * name short enough to be tagged comes back as the same object and so
         * is written once; a longer one is two strings and is written twice. */
        [classes addObject:[self _sharedClassName:[NSString stringWithFormat:@"%@", name]]];
        Class superclass = [resolved superclass];
        while (superclass != Nil) {
            [classes addObject:[self _sharedClassName:NSStringFromClass(superclass)]];
            if (superclass == [NSObject class]) {
                break;
            }
            superclass = [superclass superclass];
        }
        node[@"$classes"] = classes;
    }

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
    [_objects addObject:[self _sharedPlistScalar:leaf]];
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
        container[containerKey] = [self _uidToken:uid];
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
/* The element list is written in the collection's own order: index order for
 * an array, and the order the collection enumerates in for a set or a
 * dictionary, which is the order a keyed archive records and the order the
 * reader pairs NS.keys back up with NS.objects. */
- (void)_writeCollection:(id)object intoNode:(NSMutableDictionary *)node {
    CFTypeID type = CFGetTypeID((__bridge CFTypeRef)object);

    if (type == CFDictionaryGetTypeID()) {
        CFDictionaryRef dictionary = (__bridge CFDictionaryRef)object;
        CFIndex count = CFDictionaryGetCount(dictionary);
        const void **keys = count > 0 ? calloc((size_t)count, sizeof(void *)) : NULL;
        const void **values = count > 0 ? calloc((size_t)count, sizeof(void *)) : NULL;
        if (keys != NULL && values != NULL) {
            CFDictionaryGetKeysAndValues(dictionary, keys, values);
            NSMutableArray *keyList = [NSMutableArray arrayWithCapacity:(NSUInteger)count];
            NSMutableArray *valueList = [NSMutableArray arrayWithCapacity:(NSUInteger)count];
            /* The keys are encoded as a run before the values, not a key and
             * its object alternating.  A keyed archive hands out $objects
             * positions in the order the writer reaches the objects, and Apple
             * reaches every key of a dictionary before it reaches any of that
             * dictionary's objects -- so a nested collection under an early key
             * lands in $objects after all the keys, not between them. */
            for (CFIndex i = 0; i < count; i++) {
                [keyList addObject:[self _encodeObjectToken:(__bridge id)keys[i]]];
            }
            for (CFIndex i = 0; i < count; i++) {
                [valueList addObject:[self _encodeObjectToken:(__bridge id)values[i]]];
            }
            node[@"NS.keys"] = keyList;
            node[@"NS.objects"] = valueList;
        }
        free(keys);
        free(values);
        return;
    }

    if (type == CFSetGetTypeID()) {
        CFSetRef set = (__bridge CFSetRef)object;
        CFIndex count = CFSetGetCount(set);
        const void **values = count > 0 ? calloc((size_t)count, sizeof(void *)) : NULL;
        if (values != NULL) {
            CFSetGetValues(set, values);
            NSMutableArray *list = [NSMutableArray arrayWithCapacity:(NSUInteger)count];
            for (CFIndex i = 0; i < count; i++) {
                [list addObject:[self _encodeObjectToken:(__bridge id)values[i]]];
            }
            node[@"NS.objects"] = list;
        }
        free(values);
        return;
    }

    CFArrayRef array = (__bridge CFArrayRef)object;
    CFIndex count = CFArrayGetCount(array);
    NSMutableArray *list = [NSMutableArray arrayWithCapacity:(NSUInteger)count];
    for (CFIndex i = 0; i < count; i++) {
        [list addObject:[self _encodeObjectToken:(__bridge id)CFArrayGetValueAtIndex(array, i)]];
    }
    node[@"NS.objects"] = list;
}

- (id)_uidToken:(NSUInteger)uid {
    NSNumber *key = @(uid);
    id token = _uidTokens[key];
    if (token == nil) {
        token = _NewUIDToken(uid);
        _uidTokens[key] = token;
    }
    return token;
}

- (NSDictionary *)_encodeObjectToken:(id)object {
    if (object == nil) {
        return [self _uidToken:0];
    }

    object = [self _identifiedObject:object];

    if (object == nil) {
        return [self _uidToken:0];
    }

    NSString *ptrKey = [NSString stringWithFormat:@"%p", (void *)object];
    NSNumber *existing = _objToUid[ptrKey];
    if (existing != nil) {
        return [self _uidToken:[existing unsignedIntegerValue]];
    }

    NSString *codedName = [self _codedNameForObject:object];

    if (_IsImmediateArchivedClass(object, codedName)) {
        NSUInteger uid = [self _internLeaf:object];
        _objToUid[ptrKey] = @(uid);
        [self _resolveConditionalsForObject:object uid:uid];
        if ([_delegate respondsToSelector:@selector(archiver:didEncodeObject:)]) {
            [_delegate archiver:self didEncodeObject:object];
        }
        return [self _uidToken:uid];
    }

    [self _checkSecureObject:object];

    NSUInteger uid = [_objects count];
    [_objects addObject:[NSNull null]];
    _objToUid[ptrKey] = @(uid);

    NSMutableDictionary *node = [[NSMutableDictionary alloc] init];
    NSMutableDictionary *savedNode = _currentNode;
    _currentNode = node;
    if (_IsPlistCollection(object)) {
        [self _writeCollection:object intoNode:node];
    } else {
        [object encodeWithCoder:self];
    }
    _currentNode = savedNode;

    NSUInteger classUid = [self _encodeClassNodeNamed:codedName];
    node[@"$class"] = [self _uidToken:classUid];
    [_objects replaceObjectAtIndex:uid withObject:node];

    [self _resolveConditionalsForObject:object uid:uid];
    if ([_delegate respondsToSelector:@selector(archiver:didEncodeObject:)]) {
        [_delegate archiver:self didEncodeObject:object];
    }
    return [self _uidToken:uid];
}

/* The reserved keys collide with any user key that starts with '$', so out of
 * the public entry points the key is first mangled.  The internal writes
 * below bypass that and take the key as given. */

- (void)encodeObject:(id)object forKey:(NSString *)key {
    if (getenv("PORT_KA_TRACE") != NULL) {
        fprintf(stderr, "TRACE enc-key '%s' obj=%s\n", [key UTF8String],
                object ? object_getClassName(object) : "nil");
    }
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
        [self _putValue:[self _uidToken:0] forKey:key];
        _writingKey = nil;
        return;
    }

    object = [self _identifiedObject:object];

    if (object == nil) {
        [self _putValue:[self _uidToken:0] forKey:key];
        _writingKey = nil;
        return;
    }

    NSString *ptrKey = [NSString stringWithFormat:@"%p", (void *)object];
    NSNumber *existing = _objToUid[ptrKey];
    if (existing != nil) {
        [self _putValue:[self _uidToken:[existing unsignedIntegerValue]] forKey:key];
    } else {
        [self _registerConditional:object];
        [self _putValue:[self _uidToken:0] forKey:key];
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

    /* The reserved keys are written in the order they appear here, and that
     * order is part of the archive's bytes.  A four-entry dictionary literal is
     * laid out in hash order, which puts $objects second; asking for a larger
     * capacity moves these keys into the wider layout CoreFoundation uses for
     * dictionaries that are not tiny, and the insertion order becomes the
     * written order.  Capacity has to clear that threshold -- seven is the first
     * value that does -- so the number is a behavioural requirement, not a hint. */
    NSMutableDictionary *plist = [NSMutableDictionary dictionaryWithCapacity:8];
    plist[@"$version"] = @(100000);
    plist[@"$archiver"] = @"NSKeyedArchiver";
    plist[@"$top"] = _top;
    plist[@"$objects"] = _objects;

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