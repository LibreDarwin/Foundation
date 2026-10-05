/*
 * Copyright (C) 2026, Samuel Zormeister.
 *
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */

#ifndef NSURL_h
#define NSURL_h

#import <Foundation/NSObject.h>
#import <Foundation/NSObjCRuntime.h>
#import <Foundation/NSString.h>

@class NSArray;
@class NSData;
@class NSDictionary;
@class NSError;
@class NSNumber;
@class NSURL;

NS_ASSUME_NONNULL_BEGIN

/* The resource keys this port actually answers.  Apple's full key list also
 * covers volume metadata, Finder flags and the "promised item" (NSFilePromise)
 * family; those are not CFURL-derived and are left to a later slice.  The
 * names are the plain string constants so no NSError/NSFileManager surface is
 * required here. */
FOUNDATION_EXPORT NSString *const NSURLNameKey;
FOUNDATION_EXPORT NSString *const NSURLLocalizedNameKey;
FOUNDATION_EXPORT NSString *const NSURLIsRegularFileKey;
FOUNDATION_EXPORT NSString *const NSURLIsDirectoryKey;
FOUNDATION_EXPORT NSString *const NSURLIsSymbolicLinkKey;
FOUNDATION_EXPORT NSString *const NSURLIsVolumeKey;
FOUNDATION_EXPORT NSString *const NSURLIsPackageKey;
FOUNDATION_EXPORT NSString *const NSURLIsSystemImmutableKey;
FOUNDATION_EXPORT NSString *const NSURLIsUserImmutableKey;
FOUNDATION_EXPORT NSString *const NSURLIsHiddenKey;
FOUNDATION_EXPORT NSString *const NSURLExtensionKey;
FOUNDATION_EXPORT NSString *const NSURLPathKey;
FOUNDATION_EXPORT NSString *const NSURLCanonicalPathKey;
FOUNDATION_EXPORT NSString *const NSURLFileSizeKey;
FOUNDATION_EXPORT NSString *const NSURLFileAllocatedSizeKey;
FOUNDATION_EXPORT NSString *const NSURLTotalFileSizeKey;
FOUNDATION_EXPORT NSString *const NSURLTotalFileAllocatedSizeKey;
FOUNDATION_EXPORT NSString *const NSURLIsReadableKey;
FOUNDATION_EXPORT NSString *const NSURLIsWritableKey;
FOUNDATION_EXPORT NSString *const NSURLIsExecutableKey;
FOUNDATION_EXPORT NSString *const NSURLFileSecurityKey;
FOUNDATION_EXPORT NSString *const NSURLIsExcludedFromBackupKey;
FOUNDATION_EXPORT NSString *const NSURLPathKeyPrivate;

/* Bookmark creation options.  Only the option set the port honours is
 * declared; see NSURL.m for the exact mapping. */
typedef NS_OPTIONS(NSUInteger, NSURLBookmarkCreationOptions) {
    NSURLBookmarkCreationMinimalBookmarkMask = 0,
    NSURLBookmarkCreationSuitableForBookmarkFileMask = 1 << 11,
    NSURLBookmarkCreationWithSecurityScopeMask = 1 << 12,
    NSURLBookmarkCreationSecurityScopeAllowOnlyReadAccessMask = 1 << 13,
};

typedef NS_OPTIONS(NSUInteger, NSURLBookmarkResolutionOptions) {
    NSURLBookmarkResolutionWithoutUI = 1 << 8,
    NSURLBookmarkResolutionWithoutMountingMask = 1 << 9,
    NSURLBookmarkResolutionWithSecurityScope = 1 << 10,
};

@interface NSURL : NSObject

/* Creating URLs. */
+ (nullable instancetype)URLWithString:(NSString *)string;
+ (nullable instancetype)URLWithString:(NSString *)string
                         relativeToURL:(nullable NSURL *)baseURL;
+ (instancetype)fileURLWithPath:(NSString *)path;
+ (instancetype)fileURLWithPath:(NSString *)path
                    isDirectory:(BOOL)isDirectory;
+ (instancetype)fileURLWithPath:(NSString *)path
                    isDirectory:(BOOL)isDirectory
                 relativeToURL:(nullable NSURL *)baseURL;

- (nullable instancetype)initWithString:(NSString *)string;
- (nullable instancetype)initWithString:(NSString *)string
                           relativeToURL:(nullable NSURL *)baseURL;
- (instancetype)initFileURLWithPath:(NSString *)path;
- (instancetype)initFileURLWithPath:(NSString *)path
                        isDirectory:(BOOL)isDirectory;
- (nullable instancetype)initFileURLWithPath:(NSString *)path
                                relativeToURL:(nullable NSURL *)baseURL;

/* Reading the components. */
@property (readonly, copy) NSString *absoluteString;
@property (readonly, copy) NSString *relativeString;
@property (readonly, copy, nullable) NSURL *baseURL;
@property (readonly, copy) NSURL *absoluteURL;
@property (readonly, copy, nullable) NSString *scheme;
@property (readonly, copy, nullable) NSString *user;
@property (readonly, copy, nullable) NSString *password;
@property (readonly, copy, nullable) NSString *host;
@property (readonly, copy, nullable) NSNumber *port;
@property (readonly, copy, nullable) NSString *path;
@property (readonly, copy, nullable) NSString *relativePath;
@property (readonly, copy) NSString *pathExtension;
@property (readonly, copy) NSString *lastPathComponent;
@property (readonly, copy, nullable) NSString *query;
@property (readonly, copy, nullable) NSString *fragment;
@property (readonly, copy, nullable) NSString *parameterString;
@property (readonly, copy, nullable) NSString *resourceSpecifier;
@property (readonly, copy) NSArray *pathComponents;
@property (readonly, getter=isFileURL) BOOL fileURL;
@property (readonly) BOOL hasDirectoryPath;

/* Deriving URLs by editing the path. */
- (NSURL *)URLByAppendingPathComponent:(NSString *)pathComponent;
- (NSURL *)URLByAppendingPathComponent:(NSString *)pathComponent
                           isDirectory:(BOOL)isDirectory;
- (NSURL *)URLByAppendingPathExtension:(NSString *)pathExtension;
- (NSURL *)URLByDeletingLastPathComponent;
- (NSURL *)URLByDeletingPathExtension;
- (NSURL *)URLByStandardizingPath;
- (NSURL *)URLByResolvingSymlinksInPath;

/* Representations. */
- (nullable const char *)fileSystemRepresentation;
- (BOOL)getFileSystemRepresentation:(char *)buffer
                         maxLength:(NSUInteger)maxBufferLength;
- (NSData *)dataRepresentation;

/* Resource values.  A key the port does not know reports NO rather than
 * raising; see NSURL.m. */
- (BOOL)getResourceValue:(out id _Nullable * _Nonnull)value
                  forKey:(NSString *)key
                   error:(out NSError ** _Nullable)error;
- (nullable NSDictionary *)resourceValuesForKeys:(NSArray *)keys
                                           error:(out NSError ** _Nullable)error;
- (BOOL)checkResourceIsReachableAndReturnError:(out NSError ** _Nullable)error;
- (nullable NSURL *)fileReferenceURL;

/* Security scope.  Files outside a sandbox have no security scope, so -start
 * returns YES and the matching -stop returns NO, matching Apple's behaviour
 * for unscoped URLs. */
- (BOOL)startAccessingSecurityScopedResource;
- (void)stopAccessingSecurityScopedResource;

/* Bookmarks.  The port's format is its own; see NSURL.m. */
- (nullable NSData *)bookmarkDataWithOptions:(NSURLBookmarkCreationOptions)options
                     includingResourceValuesForKeys:(nullable NSArray *)keys
                                      relativeToURL:(nullable NSURL *)relativeToURL
                                              error:(out NSError ** _Nullable)error;
+ (nullable NSURL *)URLByResolvingBookmarkData:(NSData *)data
                                        options:(NSURLBookmarkResolutionOptions)options
                          relativeToURL:(nullable NSURL *)relativeToURL
                                  bookmarkDataIsStale:(nullable BOOL *)isStale
                                            error:(out NSError ** _Nullable)error;

@end

NS_ASSUME_NONNULL_END

#endif /* NSURL_h */