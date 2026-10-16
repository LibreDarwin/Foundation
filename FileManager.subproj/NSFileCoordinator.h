/*
 * Copyright (C) 2026, PureDarwin Project.
 *
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */

#ifndef NSFileCoordinator_h
#define NSFileCoordinator_h

#import <Foundation/NSObject.h>
#import <Foundation/NSObjCRuntime.h>
#import <Foundation/NSURL.h>
#import <Foundation/NSArray.h>
#import <Foundation/NSString.h>
#import <Foundation/NSSet.h>

@class NSError, NSOperationQueue, NSMutableDictionary;

@protocol NSFilePresenter;

NS_HEADER_AUDIT_BEGIN(nullability, sendability)

typedef NS_OPTIONS(NSUInteger, NSFileCoordinatorReadingOptions) {

    /* Whether reading does _not_ trigger sending of
     * -savePresentedItemChangesWithCompletionHandler: to certain
     * NSFilePresenters in the system and waiting for those NSFilePresenters to
     * respond. */
    NSFileCoordinatorReadingWithoutChanges = 1 << 0,

    /* Whether reading of an item that might be a symbolic link file causes the
     * resolution of the link if it is. */
    NSFileCoordinatorReadingResolvesSymbolicLink = 1 << 1,

    /* Whether the reading to be done will only attempt to get an item's
     * metadata that is immediately available. */
    NSFileCoordinatorReadingImmediatelyAvailableMetadataOnly = 1 << 2,

    /* Whether reading of an item is being done for the purpose of uploading. */
    NSFileCoordinatorReadingForUploading = 1 << 3,

};

typedef NS_OPTIONS(NSUInteger, NSFileCoordinatorWritingOptions) {

    /* Whether the writing to be done is actually the deletion of the item. */
    NSFileCoordinatorWritingForDeleting = 1 << 0,

    /* Whether the writing to be done is actually the moving or renaming of the
     * item. */
    NSFileCoordinatorWritingForMoving = 1 << 1,

    /* Whether coordinated writing triggers sending of
     * -savePresentedItemChangesWithCompletionHandler: to certain
     * NSFilePresenters in the system and waiting for those NSFilePresenters to
     * respond. */
    NSFileCoordinatorWritingForMerging = 1 << 2,

    /* Whether the writing to be done is actually the replacement of the item
     * with a different item. */
    NSFileCoordinatorWritingForReplacing = 1 << 3,

    /* Whether the writing to be done will change the item's metadata only and
     * not its contents. */
    NSFileCoordinatorWritingContentIndependentMetadataOnly = 1 << 4

};

@interface NSFileAccessIntent : NSObject

+ (instancetype)readingIntentWithURL:(NSURL *)url options:(NSFileCoordinatorReadingOptions)options;
+ (instancetype)writingIntentWithURL:(NSURL *)url options:(NSFileCoordinatorWritingOptions)options;
@property (readonly, copy) NSURL *URL;

@end

/* Coordinated file access with NSFilePresenters.
 *
 * Apple's NSFileCoordinator arbitrates file access across every process on the
 * system through a privileged daemon (and optionally an NSFileProvider
 * extension).  The port has neither, so coordination is in-process: coordinated
 * reads and writes invoke their accessor blocks directly, on the caller's
 * thread, with the item URLs unchanged, and the presenter-facing notification
 * methods (-itemAtURL:didMoveToURL: and -itemAtURL:didChangeUbiquityAttributes:)
 * message only the NSFilePresenters registered in this process.  The API
 * surface, option flags, and error/cancellation behavior match Apple's; the
 * cross-process waiting does not. */
@interface NSFileCoordinator : NSObject

/* The process' file presenters.  If you invoke +addFilePresenter: you have to
 * do a balancing invocation of +removeFilePresenter: before the file presenter
 * is deallocated. */
+ (void)addFilePresenter:(id<NSFilePresenter>)filePresenter;
+ (void)removeFilePresenter:(id<NSFilePresenter>)filePresenter;
@property (class, readonly, copy) NSArray<id<NSFilePresenter>> *filePresenters;

/* The designated initializer.  If an NSFilePresenter is provided then the
 * receiver is considered to have been created by that NSFilePresenter, or on
 * its behalf. */
- (instancetype)initWithFilePresenter:(nullable id<NSFilePresenter>)filePresenterOrNil NS_DESIGNATED_INITIALIZER;

/* A string that uniquely identifies the file access that will be done by this
 * NSFileCoordinator.  Every NSFileCoordinator has a unique purpose identifier
 * that is created during initialization. */
@property (copy) NSString *purposeIdentifier;

#pragma mark *** Asynchronous File Coordination ***

- (void)coordinateAccessWithIntents:(NSArray<NSFileAccessIntent *> *)intents queue:(NSOperationQueue *)queue byAccessor:(void (^)(NSError * _Nullable error))accessor;

#pragma mark *** Synchronous File Coordination ***

- (void)coordinateReadingItemAtURL:(NSURL *)url options:(NSFileCoordinatorReadingOptions)options error:(NSError **)outError byAccessor:(void (NS_NOESCAPE ^)(NSURL *newURL))reader;
- (void)coordinateWritingItemAtURL:(NSURL *)url options:(NSFileCoordinatorWritingOptions)options error:(NSError **)outError byAccessor:(void (NS_NOESCAPE ^)(NSURL *newURL))writer;
- (void)coordinateReadingItemAtURL:(NSURL *)readingURL options:(NSFileCoordinatorReadingOptions)readingOptions writingItemAtURL:(NSURL *)writingURL options:(NSFileCoordinatorWritingOptions)writingOptions error:(NSError **)outError byAccessor:(void (NS_NOESCAPE ^)(NSURL *newReadingURL, NSURL *newWritingURL))readerWriter;
- (void)coordinateWritingItemAtURL:(NSURL *)url1 options:(NSFileCoordinatorWritingOptions)options1 writingItemAtURL:(NSURL *)url2 options:(NSFileCoordinatorWritingOptions)options2 error:(NSError **)outError byAccessor:(void (NS_NOESCAPE ^)(NSURL *newURL1, NSURL *newURL2))writer;

#pragma mark *** Batched File Coordination ***

- (void)prepareForReadingItemsAtURLs:(NSArray<NSURL *> *)readingURLs options:(NSFileCoordinatorReadingOptions)readingOptions writingItemsAtURLs:(NSArray<NSURL *> *)writingURLs options:(NSFileCoordinatorWritingOptions)writingOptions error:(NSError **)outError byAccessor:(void (NS_NOESCAPE ^)(void (^completionHandler)(void)))batchAccessor;

#pragma mark *** Renaming and Moving Notification ***

- (void)itemAtURL:(NSURL *)oldURL willMoveToURL:(NSURL *)newURL;
- (void)itemAtURL:(NSURL *)oldURL didMoveToURL:(NSURL *)newURL;

#pragma mark *** Ubiquity Attribute Change Notification ***

- (void)itemAtURL:(NSURL *)url didChangeUbiquityAttributes:(NSSet<NSString *> *)attributes;

#pragma mark *** Cancellation ***

- (void)cancel;

@end

NS_HEADER_AUDIT_END(nullability, sendability)

#endif /* NSFileCoordinator_h */
