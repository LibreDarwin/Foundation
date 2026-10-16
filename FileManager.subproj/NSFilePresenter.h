/*
 * Copyright (C) 2026, PureDarwin Project.
 *
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */

#ifndef NSFilePresenter_h
#define NSFilePresenter_h

#import <Foundation/NSObject.h>
#import <Foundation/NSURL.h>
#import <Foundation/NSString.h>
#import <Foundation/NSSet.h>

@class NSError, NSFileVersion, NSOperationQueue;

NS_HEADER_AUDIT_BEGIN(nullability, sendability)

/* A protocol to be implemented by objects that present the contents of files
 * or directories to the user for viewing or editing.  The objects can take an
 * active role in operations that access those files or directories, even
 * operations performed by other processes in the system.  For an NSFilePresenter
 * to be aware of such file access it must be "coordinated" file access.
 *
 * The port implements the protocol surface faithfully; the cross-process
 * notification machinery that Apple's filecoordinationd performs has no
 * analogue in a single-process port, so presenters registered with
 * NSFileCoordinator are messaged from within this process only. */
@protocol NSFilePresenter<NSObject>

@required

/* The NSURL that locates the file or directory that the receiver is presenting
 * to the user.  A nil value is valid and means that the presented item does
 * not exist yet. */
@property (nullable, readonly, copy) NSURL *presentedItemURL;

/* The operation queue in which all of the other NSFilePresenter messages
 * except -presentedItemURL will be sent to the receiver.  A nil value is not
 * valid. */
@property (readonly, retain) NSOperationQueue *presentedItemOperationQueue;

@optional

/* The NSURL of the primary item on behalf of which the receiver's secondary
 * item is being accessed.  Support for App Sandbox. */
@property (nullable, readonly, copy) NSURL *primaryPresentedItemURL;

/* Given that something in the system is waiting to read from the presented
 * file or directory, invoke the passed-in reader block. */
- (void)relinquishPresentedItemToReader:(void (^)(void (^ _Nullable reacquirer)(void)))reader;

/* Given that something in the system is waiting to write to the presented
 * file or directory, invoke the passed-in writer block. */
- (void)relinquishPresentedItemToWriter:(void (^)(void (^ _Nullable reacquirer)(void)))writer;

/* Given that something in the system is waiting to read from the presented
 * file or directory, ensure the contents are up to date and then invoke the
 * completion handler. */
- (void)savePresentedItemChangesWithCompletionHandler:(void (^)(NSError * _Nullable errorOrNil))completionHandler;

/* Given that something in the system is waiting to delete the presented file
 * or directory, prepare for the deletion and then invoke the completion
 * handler. */
- (void)accommodatePresentedItemDeletionWithCompletionHandler:(void (^)(NSError * _Nullable errorOrNil))completionHandler;

/* Given that something in the system is waiting to evict the presented file or
 * directory, prepare for the eviction and then invoke the completion handler. */
- (void)accommodatePresentedItemEvictionWithCompletionHandler:(void (^)(NSError * _Nullable errorOrNil))completionHandler;

/* Be notified that the file or directory has been moved or renamed. */
- (void)presentedItemDidMoveToURL:(NSURL *)newURL;

/* Be notified that the file or file package's contents or attributes have been
 * written to. */
- (void)presentedItemDidChange;

/* Be notified that the presented file's ubiquity attributes have changed. */
- (void)presentedItemDidChangeUbiquityAttributes:(NSSet<NSString *> *)attributes;

/* The set of ubiquity attributes the receiver wishes to be notified about. */
@property (readonly, strong) NSSet<NSString *> *observedPresentedItemUbiquityAttributes;

/* Be notified that a version of the file or file package has been added,
 * removed, or resolved. */
- (void)presentedItemDidGainVersion:(NSFileVersion *)version;
- (void)presentedItemDidLoseVersion:(NSFileVersion *)version;
- (void)presentedItemDidResolveConflictVersion:(NSFileVersion *)version;

/* Given that something in the system is waiting to delete a file or directory
 * contained by the directory, prepare for the deletion and then invoke the
 * completion handler. */
- (void)accommodatePresentedSubitemDeletionAtURL:(NSURL *)url completionHandler:(void (^)(NSError * _Nullable errorOrNil))completionHandler;

/* Be notified that a file or directory contained by the directory has been
 * added. */
- (void)presentedSubitemDidAppearAtURL:(NSURL *)url;

/* Be notified that a file or directory contained by the directory has been
 * moved or renamed. */
- (void)presentedSubitemAtURL:(NSURL *)oldURL didMoveToURL:(NSURL *)newURL;

/* Be notified that the contents or attributes of a file or directory contained
 * by the directory have been written to. */
- (void)presentedSubitemDidChangeAtURL:(NSURL *)url;

/* Be notified that a version of a file or directory contained by the directory
 * has been added, removed, or resolved. */
- (void)presentedSubitemAtURL:(NSURL *)url didGainVersion:(NSFileVersion *)version;
- (void)presentedSubitemAtURL:(NSURL *)url didLoseVersion:(NSFileVersion *)version;
- (void)presentedSubitemAtURL:(NSURL *)url didResolveConflictVersion:(NSFileVersion *)version;

@end

NS_HEADER_AUDIT_END(nullability, sendability)

#endif /* NSFilePresenter_h */
