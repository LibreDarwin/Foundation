/*
 * Copyright (C) 2026, PureDarwin Project.
 *
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */

#import <Foundation/NSFileVersion.h>
#import <Foundation/NSFileManager.h>
#import <Foundation/NSData.h>
#import <Foundation/NSURL.h>
#import <Foundation/NSDate.h>
#import <Foundation/NSError.h>
#import <Foundation/NSException.h>
#import <Foundation/NSString.h>
#import <Foundation/NSArray.h>
#import <Foundation/NSDictionary.h>
#import <Foundation/NSPathUtilities.h>
#import <Foundation/NSUUID.h>

#include <sys/stat.h>

/* NSCocoaErrorDomain codes the version store reports.  These keep Apple's
 * numbers; the port does not declare them in FoundationErrors.h yet. */
enum {
    NSFileNoSuchFileError = 4,
    NSFileReadUnknownError = 256,
    NSFileReadNoSuchFileError = 260,
    NSFileWriteUnknownError = 512,
};

/* The field separator inside a persistent identifier.  It is the ASCII unit
 * separator, which may not appear in a POSIX path. */
static NSString *const kNSFileVersionFieldSeparator = @"\x1f";

@implementation NSFileVersion {
    NSURL *_URL;
    NSString *_itemPath;
    NSString *_snapshotName;
    NSDate *_modificationDate;
    BOOL _isCurrent;
    BOOL _isConflict;
    BOOL _resolved;
    BOOL _discardable;
}

#pragma mark *** Store location ***

/* A stable key for the version store directory of a given item path.  FNV-1a
 * over the path's UTF-8 bytes. */
static NSString *_StoreKeyForPath(NSString *path) {
    const char *bytes = [path UTF8String];
    unsigned long long hash = 1469598103934665603ULL;
    if (bytes != NULL) {
        for (const unsigned char *p = (const unsigned char *)bytes; *p != '\0'; p++) {
            hash ^= (unsigned long long)*p;
            hash *= 1099511628211ULL;
        }
    }
    return [NSString stringWithFormat:@"%016llx", hash];
}

static NSString *_VersionStoreRoot(void) {
    NSString *base = NSHomeDirectory();
    if (base == nil || [base length] == 0 || [base isEqualToString:@"/"]) {
        base = NSTemporaryDirectory();
    }
    return [base stringByAppendingPathComponent:@".NSFileVersionStore"];
}

static NSString *_StoreDirectoryForPath(NSString *path) {
    return [_VersionStoreRoot() stringByAppendingPathComponent:_StoreKeyForPath(path)];
}

static NSDate *_ModificationDateForPath(NSString *path) {
    struct stat st;
    if (stat([path UTF8String], &st) != 0) {
        return nil;
    }
    return [NSDate dateWithTimeIntervalSince1970:(NSTimeInterval)st.st_mtime];
}

static BOOL _FileExists(NSString *path, BOOL *isDirectory) {
    return [[NSFileManager defaultManager] fileExistsAtPath:path isDirectory:isDirectory];
}

static NSError *_Error(NSInteger code, NSString *path) {
    NSDictionary *info = nil;
    if (path != nil) {
        info = @{ @"NSFilePath": path };
    }
    return [NSError errorWithDomain:NSCocoaErrorDomain code:code userInfo:info];
}

#pragma mark *** Construction ***

+ (nullable NSFileVersion *)currentVersionOfItemAtURL:(NSURL *)url {
    NSString *path = [url path];
    if (path == nil) {
        return nil;
    }
    BOOL isDirectory = NO;
    if (!_FileExists(path, &isDirectory)) {
        return nil;
    }
    NSFileVersion *version = [[NSFileVersion alloc] init];
    version->_URL = [url copy];
    version->_itemPath = [path copy];
    version->_snapshotName = nil;
    version->_modificationDate = _ModificationDateForPath(path);
    version->_isCurrent = YES;
    version->_isConflict = NO;
    version->_resolved = YES;
    return version;
}

+ (nullable NSArray<NSFileVersion *> *)otherVersionsOfItemAtURL:(NSURL *)url {
    NSString *path = [url path];
    if (path == nil) {
        return nil;
    }
    BOOL isDirectory = NO;
    if (!_FileExists(path, &isDirectory)) {
        return nil;
    }
    return [self _versionsForItemPath:path conflictsOnly:NO];
}

+ (nullable NSArray<NSFileVersion *> *)unresolvedConflictVersionsOfItemAtURL:(NSURL *)url {
    NSString *path = [url path];
    if (path == nil) {
        return nil;
    }
    BOOL isDirectory = NO;
    if (!_FileExists(path, &isDirectory)) {
        return nil;
    }
    NSArray<NSFileVersion *> *all = [self _versionsForItemPath:path conflictsOnly:YES];
    NSMutableArray<NSFileVersion *> *unresolved = [[NSMutableArray alloc] init];
    for (NSFileVersion *version in all) {
        if (![version isResolved]) {
            [unresolved addObject:version];
        }
    }
    return unresolved;
}

/* Enumerate the stored snapshots of an item.  If conflictsOnly is YES, only
 * snapshots whose name carries the conflict marker are returned. */
+ (NSArray<NSFileVersion *> *)_versionsForItemPath:(NSString *)path conflictsOnly:(BOOL)conflictsOnly {
    NSString *storeDir = _StoreDirectoryForPath(path);
    NSFileManager *fm = [NSFileManager defaultManager];
    NSArray<NSString *> *names = [fm contentsOfDirectoryAtPath:storeDir error:NULL];
    NSMutableArray<NSFileVersion *> *versions = [[NSMutableArray alloc] init];
    for (NSString *name in names) {
        if ([name hasPrefix:@"."]) {
            continue;
        }
        BOOL isConflict = [name hasSuffix:@"-conflict"];
        if (conflictsOnly && !isConflict) {
            continue;
        }
        NSString *snapshotPath = [storeDir stringByAppendingPathComponent:name];
        NSFileVersion *version = [[NSFileVersion alloc] init];
        version->_URL = [NSURL fileURLWithPath:snapshotPath];
        version->_itemPath = [path copy];
        version->_snapshotName = [name copy];
        version->_modificationDate = _ModificationDateForPath(snapshotPath);
        version->_isCurrent = NO;
        version->_isConflict = isConflict;
        version->_resolved = isConflict ? NO : YES;
        [versions addObject:version];
    }
    return versions;
}

+ (void)getNonlocalVersionsOfItemAtURL:(NSURL *)url completionHandler:(void (^)(NSArray<NSFileVersion *> * _Nullable, NSError * _Nullable))completionHandler {
    /* The port's version store is entirely local, so there are never any
     * non-local versions. */
    if (completionHandler != nil) {
        completionHandler([NSArray array], nil);
    }
}

+ (nullable NSFileVersion *)versionOfItemAtURL:(NSURL *)url forPersistentIdentifier:(id)persistentIdentifier {
    if (![persistentIdentifier isKindOfClass:[NSString class]]) {
        return nil;
    }
    NSString *path = [url path];
    if (path == nil) {
        return nil;
    }
    NSArray<NSString *> *fields = [(NSString *)persistentIdentifier componentsSeparatedByString:kNSFileVersionFieldSeparator];
    if ([fields count] < 2 || ![fields[1] isEqualToString:path]) {
        return nil;
    }
    NSString *kind = fields[0];
    if ([kind isEqualToString:@"C"]) {
        return [self currentVersionOfItemAtURL:url];
    }
    if ([fields count] < 3) {
        return nil;
    }
    NSString *snapshotName = fields[2];
    NSString *snapshotPath = [_StoreDirectoryForPath(path) stringByAppendingPathComponent:snapshotName];
    BOOL isDirectory = NO;
    if (!_FileExists(snapshotPath, &isDirectory)) {
        return nil;
    }
    NSFileVersion *version = [[NSFileVersion alloc] init];
    version->_URL = [NSURL fileURLWithPath:snapshotPath];
    version->_itemPath = [path copy];
    version->_snapshotName = [snapshotName copy];
    version->_modificationDate = _ModificationDateForPath(snapshotPath);
    version->_isCurrent = NO;
    version->_isConflict = [snapshotName hasSuffix:@"-conflict"];
    version->_resolved = version->_isConflict ? NO : YES;
    return version;
}

#pragma mark *** Adding and removing versions ***

+ (nullable NSFileVersion *)addVersionOfItemAtURL:(NSURL *)url withContentsOfURL:(NSURL *)contentsURL options:(NSFileVersionAddingOptions)options error:(NSError **)outError {
    NSString *path = [url path];
    NSString *contentsPath = [contentsURL path];
    if (path == nil || contentsPath == nil) {
        if (outError) {
            *outError = _Error(NSFileNoSuchFileError, path);
        }
        return nil;
    }

    NSFileManager *fm = [NSFileManager defaultManager];
    NSString *storeDir = _StoreDirectoryForPath(path);
    if (![fm fileExistsAtPath:storeDir]) {
        if (![fm createDirectoryAtPath:storeDir withIntermediateDirectories:YES attributes:nil error:outError]) {
            return nil;
        }
    }

    NSString *stamp = [NSString stringWithFormat:@"%.0f", [[NSDate date] timeIntervalSince1970] * 1000.0];
    NSString *snapshotName = [NSString stringWithFormat:@"%@-%@", stamp, [[NSUUID UUID] UUIDString]];
    NSString *snapshotPath = [storeDir stringByAppendingPathComponent:snapshotName];

    NSData *contents = [fm contentsAtPath:contentsPath];
    if (contents == nil) {
        if (outError) {
            *outError = _Error(NSFileReadNoSuchFileError, contentsPath);
        }
        return nil;
    }
    if (![fm createFileAtPath:snapshotPath contents:contents attributes:nil]) {
        if (outError) {
            *outError = _Error(NSFileWriteUnknownError, snapshotPath);
        }
        return nil;
    }

    if (options & NSFileVersionAddingByMoving) {
        NSError *removeError = nil;
        if (![fm removeItemAtPath:contentsPath error:&removeError]) {
            [fm removeItemAtPath:snapshotPath error:NULL];
            if (outError) {
                *outError = removeError;
            }
            return nil;
        }
    }

    NSFileVersion *version = [[NSFileVersion alloc] init];
    version->_URL = [NSURL fileURLWithPath:snapshotPath];
    version->_itemPath = [path copy];
    version->_snapshotName = [snapshotName copy];
    version->_modificationDate = _ModificationDateForPath(snapshotPath);
    version->_isCurrent = NO;
    version->_isConflict = NO;
    version->_resolved = YES;
    return version;
}

+ (NSURL *)temporaryDirectoryURLForNewVersionOfItemAtURL:(NSURL *)url {
    NSString *name = [NSString stringWithFormat:@"NSFileVersion-%@", [[NSUUID UUID] UUIDString]];
    NSString *dir = [NSTemporaryDirectory() stringByAppendingPathComponent:name];
    [[NSFileManager defaultManager] createDirectoryAtPath:dir withIntermediateDirectories:YES attributes:nil error:NULL];
    return [NSURL fileURLWithPath:dir isDirectory:YES];
}

- (nullable NSURL *)replaceItemAtURL:(NSURL *)url options:(NSFileVersionReplacingOptions)options error:(NSError **)error {
    if (_isCurrent) {
        return url;
    }
    NSString *destination = [url path];
    if (destination == nil) {
        if (error) {
            *error = _Error(NSFileNoSuchFileError, nil);
        }
        return nil;
    }
    NSFileManager *fm = [NSFileManager defaultManager];
    NSData *contents = [fm contentsAtPath:[_URL path]];
    if (contents == nil) {
        if (error) {
            *error = _Error(NSFileReadNoSuchFileError, [_URL path]);
        }
        return nil;
    }
    if (![fm createFileAtPath:destination contents:contents attributes:nil]) {
        if (error) {
            *error = _Error(NSFileWriteUnknownError, destination);
        }
        return nil;
    }
    if (options & NSFileVersionReplacingByMoving) {
        [fm removeItemAtPath:[_URL path] error:NULL];
    }
    return url;
}

- (BOOL)removeAndReturnError:(NSError **)outError {
    if (_isCurrent) {
        [NSException raise:NSInternalInconsistencyException
                    format:@"-[NSFileVersion removeAndReturnError:] may not be sent to the current version. Use -[NSFileManager removeItemAtURL:error:] for that."];
    }
    if (_snapshotName == nil) {
        if (outError) {
            *outError = _Error(NSFileNoSuchFileError, _itemPath);
        }
        return NO;
    }
    NSString *snapshotPath = [_StoreDirectoryForPath(_itemPath) stringByAppendingPathComponent:_snapshotName];
    return [[NSFileManager defaultManager] removeItemAtPath:snapshotPath error:outError];
}

+ (BOOL)removeOtherVersionsOfItemAtURL:(NSURL *)url error:(NSError **)outError {
    NSString *path = [url path];
    if (path == nil) {
        if (outError) {
            *outError = _Error(NSFileNoSuchFileError, nil);
        }
        return NO;
    }
    NSString *storeDir = _StoreDirectoryForPath(path);
    NSFileManager *fm = [NSFileManager defaultManager];
    if (![fm fileExistsAtPath:storeDir]) {
        return YES;
    }
    NSArray<NSString *> *names = [fm contentsOfDirectoryAtPath:storeDir error:outError];
    if (names == nil) {
        return NO;
    }
    for (NSString *name in names) {
        NSString *snapshotPath = [storeDir stringByAppendingPathComponent:name];
        if (![fm removeItemAtPath:snapshotPath error:outError]) {
            return NO;
        }
    }
    return YES;
}

#pragma mark *** Accessors ***

- (NSURL *)URL {
    return _URL;
}

- (nullable NSString *)localizedName {
    if (_itemPath == nil) {
        return nil;
    }
    return [_itemPath lastPathComponent];
}

- (nullable NSString *)localizedNameOfSavingComputer {
    return nil;
}

- (nullable NSPersonNameComponents *)originatorNameComponents {
    return nil;
}

- (nullable NSDate *)modificationDate {
    return _modificationDate;
}

- (id<NSCoding>)persistentIdentifier {
    NSString *identifier;
    if (_isCurrent) {
        identifier = [NSString stringWithFormat:@"C%@%@", kNSFileVersionFieldSeparator, _itemPath];
    } else {
        identifier = [NSString stringWithFormat:@"V%@%@%@%@", kNSFileVersionFieldSeparator, _itemPath, kNSFileVersionFieldSeparator, _snapshotName];
    }
    return (id<NSCoding>)identifier;
}

- (BOOL)isConflict {
    return _isConflict;
}

- (BOOL)isResolved {
    return _resolved;
}

- (void)setResolved:(BOOL)resolved {
    if (!resolved) {
        [NSException raise:NSInvalidArgumentException
                    format:@"Once a version's conflict has been resolved it cannot be made unresolved again."];
    }
    _resolved = YES;
}

- (BOOL)isDiscardable {
    if (_isCurrent) {
        [NSException raise:NSInternalInconsistencyException
                    format:@"The current version of an item is never discardable."];
    }
    return _discardable;
}

- (void)setDiscardable:(BOOL)discardable {
    if (_isCurrent) {
        [NSException raise:NSInternalInconsistencyException
                    format:@"The current version of an item is never discardable."];
    }
    if (!discardable) {
        [NSException raise:NSInvalidArgumentException
                    format:@"Once a version has been marked discardable it cannot be made undiscardable again."];
    }
    _discardable = YES;
}

- (BOOL)hasLocalContents {
    return YES;
}

- (BOOL)hasThumbnail {
    return NO;
}

#pragma mark *** Identity ***

- (BOOL)isEqual:(id)other {
    if (self == other) {
        return YES;
    }
    if (![other isKindOfClass:[NSFileVersion class]]) {
        return NO;
    }
    NSFileVersion *version = other;
    if (![_itemPath isEqualToString:version->_itemPath]) {
        return NO;
    }
    if (_isCurrent != version->_isCurrent) {
        return NO;
    }
    if (_isCurrent) {
        return YES;
    }
    return [_snapshotName isEqualToString:version->_snapshotName];
}

- (NSUInteger)hash {
    return [(NSString *)[self persistentIdentifier] hash];
}

@end
