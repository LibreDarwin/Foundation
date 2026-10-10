/*
	NSFileWrapper.h
	Copyright (c) 1995-2019, Apple Inc.
*/

#import <Foundation/NSObject.h>

@class NSData, NSDictionary<KeyType, ObjectType>, NSError, NSString, NSURL;

NS_HEADER_AUDIT_BEGIN(nullability, sendability)

typedef NS_OPTIONS(NSUInteger, NSFileWrapperReadingOptions) {
    NSFileWrapperReadingImmediate = 1 << 0,
    NSFileWrapperReadingWithoutMapping = 1 << 1
} API_AVAILABLE(macos(10.6), ios(4.0), watchos(2.0), tvos(9.0));

typedef NS_OPTIONS(NSUInteger, NSFileWrapperWritingOptions) {
    NSFileWrapperWritingAtomic = 1 << 0,
    NSFileWrapperWritingWithNameUpdating = 1 << 1
} API_AVAILABLE(macos(10.6), ios(4.0), watchos(2.0), tvos(9.0));

API_AVAILABLE(macos(10.0), ios(4.0), watchos(2.0), tvos(9.0))
@interface NSFileWrapper : NSObject<NSSecureCoding>

#pragma mark *** Initialization ***

- (nullable instancetype)initWithURL:(NSURL *)url options:(NSFileWrapperReadingOptions)options error:(NSError **)outError NS_DESIGNATED_INITIALIZER API_AVAILABLE(macos(10.6), ios(4.0), watchos(2.0), tvos(9.0));
- (instancetype)initDirectoryWithFileWrappers:(NSDictionary<NSString *, NSFileWrapper *> *)childrenByPreferredName NS_DESIGNATED_INITIALIZER;
- (instancetype)initRegularFileWithContents:(NSData *)contents NS_DESIGNATED_INITIALIZER;
- (instancetype)initSymbolicLinkWithDestinationURL:(NSURL *)url NS_DESIGNATED_INITIALIZER API_AVAILABLE(macos(10.6), ios(4.0), watchos(2.0), tvos(9.0));
- (nullable instancetype)initWithSerializedRepresentation:(NSData *)serializeRepresentation NS_DESIGNATED_INITIALIZER;
- (nullable instancetype)initWithCoder:(NSCoder *)inCoder NS_DESIGNATED_INITIALIZER;

#pragma mark *** Properties Applicable to Every Kind of File Wrapper ***

@property (readonly, getter=isDirectory) BOOL directory;
@property (readonly, getter=isRegularFile) BOOL regularFile;
@property (readonly, getter=isSymbolicLink) BOOL symbolicLink;

@property (nullable, copy) NSString *preferredFilename;
@property (nullable, copy) NSString *filename;
@property (copy) NSDictionary<NSString *, id> *fileAttributes;

#pragma mark *** Reading ***

- (BOOL)matchesContentsOfURL:(NSURL *)url API_AVAILABLE(macos(10.6), ios(4.0), watchos(2.0), tvos(9.0));
- (BOOL)readFromURL:(NSURL *)url options:(NSFileWrapperReadingOptions)options error:(NSError **)outError API_AVAILABLE(macos(10.6), ios(4.0), watchos(2.0), tvos(9.0));

#pragma mark *** Writing ***

- (BOOL)writeToURL:(NSURL *)url options:(NSFileWrapperWritingOptions)options originalContentsURL:(nullable NSURL *)originalContentsURL error:(NSError **)outError API_AVAILABLE(macos(10.6), ios(4.0), watchos(2.0), tvos(9.0));

#pragma mark *** Serialization ***

@property (nullable, readonly, copy) NSData *serializedRepresentation;

#pragma mark *** Directories ***

- (NSString *)addFileWrapper:(NSFileWrapper *)child;
- (NSString *)addRegularFileWithContents:(NSData *)data preferredFilename:(NSString *)fileName;
- (void)removeFileWrapper:(NSFileWrapper *)child;
@property (nullable, readonly, copy) NSDictionary<NSString *, NSFileWrapper *> *fileWrappers;
- (nullable NSString *)keyForFileWrapper:(NSFileWrapper *)child;

#pragma mark *** Regular Files ***

@property (nullable, readonly, copy) NSData *regularFileContents;

#pragma mark *** Symbolic Links ***

@property (nullable, readonly, copy) NSURL *symbolicLinkDestinationURL API_AVAILABLE(macos(10.6), ios(4.0), watchos(2.0), tvos(9.0));

@end

#if TARGET_OS_OSX

@interface NSFileWrapper(NSDeprecated)

- (nullable id)initWithPath:(NSString *)path API_DEPRECATED("Use -initWithURL:options:error: instead.", macos(10.0,10.10)) API_UNAVAILABLE(ios, watchos, tvos);
- (id)initSymbolicLinkWithDestination:(NSString *)path API_DEPRECATED("Use -initSymbolicLinkWithDestinationURL: and -setPreferredFileName:, if necessary, instead.", macos(10.0,10.10)) API_UNAVAILABLE(ios, watchos, tvos);
- (BOOL)needsToBeUpdatedFromPath:(NSString *)path API_DEPRECATED("Use -matchesContentsOfURL: instead.", macos(10.0,10.10)) API_UNAVAILABLE(ios, watchos, tvos);
- (BOOL)updateFromPath:(NSString *)path API_DEPRECATED("Use -readFromURL:options:error: instead.", macos(10.0,10.10)) API_UNAVAILABLE(ios, watchos, tvos);
- (BOOL)writeToFile:(NSString *)path atomically:(BOOL)atomicFlag updateFilenames:(BOOL)updateFilenamesFlag API_DEPRECATED("Use -writeToURL:options:originalContentsURL:error: instead.", macos(10.0,10.10)) API_UNAVAILABLE(ios, watchos, tvos);
- (NSString *)addFileWithPath:(NSString *)path API_DEPRECATED("Instantiate a new NSFileWrapper with -initWithURL:options:error:, send it -setPreferredFileName: if necessary, then use -addFileWrapper: instead.", macos(10.0,10.10)) API_UNAVAILABLE(ios, watchos, tvos);
- (NSString *)addSymbolicLinkWithDestination:(NSString *)path preferredFilename:(NSString *)filename API_DEPRECATED("Instantiate a new NSFileWrapper with -initWithSymbolicLinkDestinationURL:, send it -setPreferredFileName: if necessary, then use -addFileWrapper: instead.", macos(10.0,10.10)) API_UNAVAILABLE(ios, watchos, tvos);
- (NSString *)symbolicLinkDestination API_DEPRECATED("Use -symbolicLinkDestinationURL instead.", macos(10.0,10.10)) API_UNAVAILABLE(ios, watchos, tvos);

@end

#endif

NS_HEADER_AUDIT_END(nullability, sendability)
