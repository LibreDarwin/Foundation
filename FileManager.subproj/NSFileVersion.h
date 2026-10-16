/*
 * Copyright (C) 2026, PureDarwin Project.
 *
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */

#ifndef NSFileVersion_h
#define NSFileVersion_h

#import <Foundation/NSObject.h>
#import <Foundation/NSObjCRuntime.h>
#import <Foundation/NSArray.h>

@class NSDate, NSError, NSString, NSURL, NSPersonNameComponents;

NS_HEADER_AUDIT_BEGIN(nullability, sendability)

typedef NS_OPTIONS(NSUInteger, NSFileVersionAddingOptions) {

    /* Whether +addVersionOfItemAtURL:withContentsOfURL:options:error: can move
     * the new version contents file into the version store instead of copying
     * it.  Moving is much faster. */
    NSFileVersionAddingByMoving = 1 << 0

};

typedef NS_OPTIONS(NSUInteger, NSFileVersionReplacingOptions) {

    /* Whether -replaceItemAtURL:options:error: must move the version's contents
     * out of the version store instead of copying it. */
    NSFileVersionReplacingByMoving = 1 << 0

};

/* Instances of NSFileVersion for the same version of the same file are equal,
 * and instances of NSFileVersion for different versions of the same file are
 * not equal.
 *
 * The port backs versions with an on-disk store keyed off the versioned file's
 * path.  Apple's version store is a system service (and, for iCloud documents,
 * partly remote); the port's store is local to this machine and lives under
 * the user's home directory.  Versions that are "non-local" in Apple's sense
 * (not yet downloaded) do not exist here, so the nonlocal-version APIs report
 * no versions. */
@interface NSFileVersion : NSObject

/* Return an NSFileVersion that represents the contents of the file located by a
 * URL, or nil if there is no such file. */
+ (nullable NSFileVersion *)currentVersionOfItemAtURL:(NSURL *)url;

/* Return an array of NSFileVersions associated with the file located by a URL,
 * or nil if there is no such file.  The array never contains an NSFileVersion
 * equal to what +currentVersionOfItemAtURL: would return. */
+ (nullable NSArray<NSFileVersion *> *)otherVersionsOfItemAtURL:(NSURL *)url;

/* Return an array of NSFileVersions that represent unresolved conflicts for the
 * file located by a URL, or nil if there is no such file. */
+ (nullable NSArray<NSFileVersion *> *)unresolvedConflictVersionsOfItemAtURL:(NSURL *)url;

/* Asynchronously return an array of NSFileVersions associated with the file
 * located by the given URL, or nil if there is no such file or another error
 * occurs.  The port has no non-local versions, so the completion handler is
 * always invoked with an empty array. */
+ (void)getNonlocalVersionsOfItemAtURL:(NSURL *)url completionHandler:(void (^)(NSArray<NSFileVersion *> * _Nullable nonlocalFileVersions, NSError * _Nullable error))completionHandler;

/* For a file located by a URL, return the NSFileVersion identified by a
 * persistent identifier of the sort returned by -persistentIdentifier, or nil
 * if the version no longer exists. */
+ (nullable NSFileVersion *)versionOfItemAtURL:(NSURL *)url forPersistentIdentifier:(id)persistentIdentifier;

/* Add a new version of the file located by a URL, with the contents coming from
 * a file located by either the same or a different URL, and return a new
 * instance that represents the version if successful.  If not successful,
 * return nil after setting *outError to an NSError that encapsulates why not. */
+ (nullable NSFileVersion *)addVersionOfItemAtURL:(NSURL *)url withContentsOfURL:(NSURL *)contentsURL options:(NSFileVersionAddingOptions)options error:(NSError **)outError;

/* Given a URL, create a new directory that is suitable for using as the
 * container of a new temporary file that you will create and use with
 * NSFileVersionAddingByMoving.  You must remove this directory when you are
 * done with it. */
+ (NSURL *)temporaryDirectoryURLForNewVersionOfItemAtURL:(NSURL *)url;

/* The location of the receiver's storage, or possibly nil if the receiver's
 * storage has been deleted.  The storage is read-only. */
@property (readonly, copy) NSURL *URL;

/* The user-presentable name of the version, or possibly nil if the receiver's
 * storage has been deleted. */
@property (nullable, readonly, copy) NSString *localizedName;

/* The user-presentable name of the computer on which the version was saved, or
 * possibly nil. */
@property (nullable, readonly, copy) NSString *localizedNameOfSavingComputer;

/* The name components of the user who created this version of the file.  Nil if
 * the file is not shared or if the current user is the originator. */
@property (nullable, readonly, copy) NSPersonNameComponents *originatorNameComponents;

/* The modification date of the version, or possibly nil if the receiver's
 * storage has been deleted. */
@property (nullable, readonly, copy) NSDate *modificationDate;

/* An object that can be encoded and, after subsequent decoding, passed to
 * -versionOfItemAtURL:forPersistentIdentifier: to create a new instance of
 * NSFileVersion that is equal to the receiver. */
@property (readonly, retain) id<NSCoding> persistentIdentifier;

/* Whether the version was created as a result of the discovery of a conflict
 * between two writers of the versioned file. */
@property (readonly, getter=isConflict) BOOL conflict;

/* If the version is a conflict version, whether the conflict has been resolved.
 * If the version is not a conflict version, simply YES. */
@property (getter=isResolved) BOOL resolved;

/* Whether the system is allowed to automatically delete the receiver's storage
 * in the future, at an unpredictable time. */
@property (getter=isDiscardable) BOOL discardable;

/* Whether the version has local contents. */
@property (readonly) BOOL hasLocalContents;

/* Whether the version has a thumbnail image available. */
@property (readonly) BOOL hasThumbnail;

/* If the passed-in URL locates a file, replace the file with a file whose
 * contents are taken from the version but whose display name is taken from the
 * file.  If the passed-in URL does not locate a file then simply write one. */
- (nullable NSURL *)replaceItemAtURL:(NSURL *)url options:(NSFileVersionReplacingOptions)options error:(NSError **)error;

/* Delete the receiver's storage, and return YES if successful.  You cannot use
 * this method to delete the versioned file itself; it always throws an
 * exception when sent to the result of +currentVersionOfItemAtURL:. */
- (BOOL)removeAndReturnError:(NSError **)outError;

/* Delete all of the versions associated with the file located by a URL, except
 * for the current one, and return YES if successful. */
+ (BOOL)removeOtherVersionsOfItemAtURL:(NSURL *)url error:(NSError **)outError;

@end

NS_HEADER_AUDIT_END(nullability, sendability)

#endif /* NSFileVersion_h */
