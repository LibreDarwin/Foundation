/*
 * Copyright (C) 2026, Sunneva N. Mariu.
 *
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */

#ifndef NSKeyedArchiver_h
#define NSKeyedArchiver_h

#import <Foundation/NSCoder.h>
#import <Foundation/NSPropertyList.h>
#import <Foundation/NSObjCRuntime.h>

/* Parameterised as in NSCoder.h, which this header imports; the re-declaration
 * keeps this file self-sufficient if it is ever compiled on its own. */
@class NSArray<__covariant ObjectType>;
@class NSSet<ObjectType>;

@class NSMutableData;
@protocol NSKeyedArchiverDelegate, NSKeyedUnarchiverDelegate;

/* The key an archive's root object is stored under.  The unarchiving class
 * methods look for the root object under this key, and a program writing a
 * top-level object with its own -encodeWithCoder: should do the same so its
 * archives read back with them. */
FOUNDATION_EXPORT NSString * const NSKeyedArchiveRootObjectKey;

/* Writes an object graph to a property-list archive.  The keyed codec is
 * deliberately limited in what it can represent, which is what makes the
 * format stable: strings, numbers and data travel inline, everything else is
 * encoded through the keyed coding methods and comes back through
 * -initWithCoder:.  The encoded form is a dictionary of $archiver, $version,
 * $top and $objects; NSKeyedUnarchiver is the only reader of it. */
@interface NSKeyedArchiver : NSCoder

/* Secure coding is on by default.  An archiver that requires it refuses to
 * encode objects that do not conform to NSSecureCoding, which is a promise
 * that the archive can always decode itself.  Turn it off only if the objects
 * being archived cannot conform. */
- (instancetype)initRequiringSecureCoding:(BOOL)requiresSecureCoding;

+ (NSData *)archivedDataWithRootObject:(id)object
                 requiringSecureCoding:(BOOL)requiresSecureCoding
                                 error:(NSError **)error;

- (instancetype)init;
- (instancetype)initForWritingWithMutableData:(NSMutableData *)data;

+ (NSData *)archivedDataWithRootObject:(id)rootObject;
+ (BOOL)archiveRootObject:(id)rootObject toFile:(NSString *)path;

@property (assign) id <NSKeyedArchiverDelegate> delegate;

@property NSPropertyListFormat outputFormat;

/* The serialised archive.  Reading it encodes if -finishEncoding has not run
 * yet.  When the archiver was given a mutable data to write into, that is the
 * object returned. */
@property (readonly) NSData *encodedData;

- (void)finishEncoding;

/* The name a class is written as.  Lookup is per-archiver first, then on the
 * class itself; the two spellings share the global table.  Instance-level
 * classNameForClass: also searches the global table set by the class method. */
+ (void)setClassName:(NSString *)codedName forClass:(Class)cls;
- (void)setClassName:(NSString *)codedName forClass:(Class)cls;

+ (NSString *)classNameForClass:(Class)cls;
- (NSString *)classNameForClass:(Class)cls;

@property (readwrite) BOOL requiresSecureCoding;

@end

/* Reads an archive written by NSKeyedArchiver.  With secure coding on, every
 * class the archive names must be in the allowed set passed to decodeObjectOf
 * Class:forKey: (or one of the +unarchived... class methods) and must conform
 * to NSSecureCoding; a step in violation of either fails the decode. */
@interface NSKeyedUnarchiver : NSCoder

/* Parses the archive.  Enables requiresSecureCoding and sets
 * decodingFailurePolicy to SetErrorAndReturn: failures surface in the error
 * out-parameter.  Returns nil (with an error) if the data is not a valid
 * archive. */
- (instancetype)initForReadingFromData:(NSData *)data error:(NSError **)error;

+ (id)unarchivedObjectOfClass:(Class)cls
                       fromData:(NSData *)data
                          error:(NSError **)error NS_REFINED_FOR_SWIFT;

+ (NSArray *)unarchivedArrayOfObjectsOfClass:(Class)cls
                                     fromData:(NSData *)data
                                        error:(NSError **)error NS_REFINED_FOR_SWIFT;

+ (NSDictionary *)unarchivedDictionaryWithKeysOfClass:(Class)keyCls
                                       objectsOfClass:(Class)valueCls
                                             fromData:(NSData *)data
                                                error:(NSError **)error NS_REFINED_FOR_SWIFT;

+ (id)unarchivedObjectOfClasses:(NSSet<Class> *)classes
                          fromData:(NSData *)data
                             error:(NSError **)error;

+ (NSArray *)unarchivedArrayOfObjectsOfClasses:(NSSet<Class> *)classes
                                       fromData:(NSData *)data
                                          error:(NSError **)error NS_REFINED_FOR_SWIFT;

+ (NSDictionary *)unarchivedDictionaryWithKeysOfClasses:(NSSet<Class> *)keyClasses
                                       objectsOfClasses:(NSSet<Class> *)valueClasses
                                               fromData:(NSData *)data
                                                  error:(NSError **)error NS_REFINED_FOR_SWIFT;

- (instancetype)init;
- (instancetype)initForReadingWithData:(NSData *)data;

+ (id)unarchiveObjectWithData:(NSData *)data;
+ (id)unarchiveTopLevelObjectWithData:(NSData *)data
                                error:(NSError **)error NS_SWIFT_UNAVAILABLE("Use 'unarchiveTopLevelObjectWithData(_:) throws' instead");
+ (id)unarchiveObjectWithFile:(NSString *)path;

@property (assign) id <NSKeyedUnarchiverDelegate> delegate;

- (void)finishDecoding;

/* The class an archived class name is decoded as.  Lookup is per-unarchiver
 * first, then on the class.  A nil mapping falls back to NSClassFromString. */
+ (void)setClass:(Class)cls forClassName:(NSString *)codedName;
- (void)setClass:(Class)cls forClassName:(NSString *)codedName;

+ (Class)classForClassName:(NSString *)codedName;
- (Class)classForClassName:(NSString *)codedName;

@property (readwrite) BOOL requiresSecureCoding;

@property (readwrite) NSDecodingFailurePolicy decodingFailurePolicy;

@end

/* The delegate sees every object as it goes by, may substitute objects on the
 * way in, and is told when encoding starts and finishes. */
@protocol NSKeyedArchiverDelegate <NSObject>
@optional

/* The delegate may return a different object to be encoded instead, or nil to
 * encode nil.  Called after the object has told the archiver to use a
 * replacement, and only once per object; nil is not reported. */
- (id)archiver:(NSKeyedArchiver *)archiver willEncodeObject:(id)object;

/* The object has been encoded.  May be nil.  Conditional objects are only
 * reported once really encoded, if ever. */
- (void)archiver:(NSKeyedArchiver *)archiver didEncodeObject:(id)object;

/* newObject is being encoded in place of object, whether by the archiver or
 * by the delegate itself. */
- (void)archiver:(NSKeyedArchiver *)archiver willReplaceObject:(id)object withObject:(id)newObject;

- (void)archiverWillFinish:(NSKeyedArchiver *)archiver;
- (void)archiverDidFinish:(NSKeyedArchiver *)archiver;

@end

/* The delegate is told when an archive names a class the runtime does not
 * have, may see and replace every decoded object, and is book-ended by the
 * finish notifications. */
@protocol NSKeyedUnarchiverDelegate <NSObject>
@optional

/* The named class is not known.  The delegate may load code to introduce it
 * or return a substitute class; returning nil aborts the decode.  The first
 * entry of classNames is the encoded class, then its superclasses in order. */
- (Class)unarchiver:(NSKeyedUnarchiver *)unarchiver cannotDecodeObjectOfClassName:(NSString *)name originalClasses:(NSArray<NSString *> *)classNames;

/* The object has been decoded.  The delegate may return a different object or
 * nil (meaning: keep the decoded one). */
- (id)unarchiver:(NSKeyedUnarchiver *)unarchiver didDecodeObject:(id)object;

- (void)unarchiver:(NSKeyedUnarchiver *)unarchiver willReplaceObject:(id)object withObject:(id)newObject;

- (void)unarchiverWillFinish:(NSKeyedUnarchiver *)unarchiver;
- (void)unarchiverDidFinish:(NSKeyedUnarchiver *)unarchiver;

@end

/* The hooks every object runs through as it is archived.  The default
 * implementations, provided by NSKeyedArchiver.m, answer the object itself;
 * a class overrides them to substitute a new class or instance.  The results
 * are overridden by the archiver's class-name tables. */
@interface NSObject (NSKeyedArchiverObjectSubstitution)

/* The class the object is encoded as. */
@property (readonly) Class classForKeyedArchiver;

/* The instance encoded in place of the receiver under the keyed codec. */
- (id)replacementObjectForKeyedArchiver:(NSKeyedArchiver *)archiver;

/* Class names to fall back to when decoding an archived instance of a missing
 * class; empty by default. */
+ (NSArray<NSString *> *)classFallbacksForKeyedArchiver;

@end

/* The class an archived object is instantiated as, overriding the unarchiver's
 * class-name tables.  Returns self by default. */
@interface NSObject (NSKeyedUnarchiverObjectSubstitution)

+ (Class)classForKeyedUnarchiver;

@end

#endif /* NSKeyedArchiver_h */