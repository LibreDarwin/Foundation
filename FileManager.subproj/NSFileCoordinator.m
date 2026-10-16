/*
 * Copyright (C) 2026, PureDarwin Project.
 *
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */

#import <Foundation/NSFileCoordinator.h>
#import <Foundation/NSFilePresenter.h>
#import <Foundation/NSError.h>
#import <Foundation/NSException.h>
#import <Foundation/NSDictionary.h>
#import <Foundation/NSUUID.h>
#import <Foundation/NSOperationQueue.h>

/* NSCocoaErrorDomain code for a cancelled coordinated operation.  Apple's
 * NSUserCancelledError lives in the Cocoa error domain at 3072. */
enum {
    NSUserCancelledError = 3072,
};

#pragma mark *** NSFileAccessIntent ***

@interface NSFileAccessIntent ()
- (instancetype)_initWithURL:(NSURL *)url options:(NSUInteger)options writing:(BOOL)writing;
@end

@implementation NSFileAccessIntent {
    NSURL *_URL;
    NSUInteger _options;
    BOOL _writing;
}

+ (instancetype)readingIntentWithURL:(NSURL *)url options:(NSFileCoordinatorReadingOptions)options {
    return [[self alloc] _initWithURL:url options:options writing:NO];
}

+ (instancetype)writingIntentWithURL:(NSURL *)url options:(NSFileCoordinatorWritingOptions)options {
    return [[self alloc] _initWithURL:url options:options writing:YES];
}

- (instancetype)_initWithURL:(NSURL *)url options:(NSUInteger)options writing:(BOOL)writing {
    self = [super init];
    if (self) {
        _URL = [url copy];
        _options = options;
        _writing = writing;
    }
    return self;
}

- (NSURL *)URL {
    return _URL;
}

@end

#pragma mark *** NSFileCoordinator ***

/* The process-wide presenter registry.  Apple keeps this in a service so every
 * process sees every presenter; the port keeps it in-process. */
static NSMutableArray<id<NSFilePresenter>> *_filePresenters = nil;

@implementation NSFileCoordinator {
    id<NSFilePresenter> _filePresenter;
    NSString *_purposeIdentifier;
    NSMutableDictionary *_movedItems;
    BOOL _purposeIdentifierSet;
    BOOL _isCancelled;
}

+ (void)addFilePresenter:(id<NSFilePresenter>)filePresenter {
    if (filePresenter == nil) {
        return;
    }
    @synchronized ([NSFileCoordinator class]) {
        if (_filePresenters == nil) {
            _filePresenters = [[NSMutableArray alloc] init];
        }
        if (![_filePresenters containsObject:filePresenter]) {
            [_filePresenters addObject:filePresenter];
        }
    }
}

+ (void)removeFilePresenter:(id<NSFilePresenter>)filePresenter {
    if (filePresenter == nil) {
        return;
    }
    @synchronized ([NSFileCoordinator class]) {
        [_filePresenters removeObject:filePresenter];
    }
}

+ (NSArray<id<NSFilePresenter>> *)filePresenters {
    @synchronized ([NSFileCoordinator class]) {
        if (_filePresenters == nil) {
            return [NSArray array];
        }
        return [[NSArray alloc] initWithArray:_filePresenters];
    }
}

- (instancetype)init {
    return [self initWithFilePresenter:nil];
}

- (instancetype)initWithFilePresenter:(id<NSFilePresenter>)filePresenterOrNil {
    self = [super init];
    if (self) {
        _filePresenter = filePresenterOrNil;
        _movedItems = [[NSMutableDictionary alloc] init];
        _purposeIdentifier = [[NSUUID UUID] UUIDString];
        _purposeIdentifierSet = NO;
        _isCancelled = NO;
    }
    return self;
}

- (NSString *)purposeIdentifier {
    return _purposeIdentifier;
}

- (void)setPurposeIdentifier:(NSString *)purposeIdentifier {
    if (_purposeIdentifierSet || _filePresenter != nil) {
        [NSException raise:NSInternalInconsistencyException
                    format:@"The purpose identifier of an NSFileCoordinator can be set only once, and never for a coordinator created with -initWithFilePresenter:."];
    }
    if (purposeIdentifier == nil || [purposeIdentifier length] == 0) {
        [NSException raise:NSInvalidArgumentException
                    format:@"A purpose identifier may not be nil or a zero-length string."];
    }
    _purposeIdentifier = [purposeIdentifier copy];
    _purposeIdentifierSet = YES;
}

- (NSError *)_cancelledError {
    return [NSError errorWithDomain:NSCocoaErrorDomain code:NSUserCancelledError];
}

#pragma mark *** Asynchronous File Coordination ***

- (void)coordinateAccessWithIntents:(NSArray<NSFileAccessIntent *> *)intents queue:(NSOperationQueue *)queue byAccessor:(void (^)(NSError * _Nullable error))accessor {
    if (queue == nil) {
        [NSException raise:NSInvalidArgumentException
                    format:@"The queue passed to -coordinateAccessWithIntents:queue:byAccessor: must not be nil."];
    }
    if (_isCancelled) {
        accessor([self _cancelledError]);
        return;
    }
    accessor(nil);
}

#pragma mark *** Synchronous File Coordination ***

- (void)coordinateReadingItemAtURL:(NSURL *)url options:(NSFileCoordinatorReadingOptions)options error:(NSError **)outError byAccessor:(void (NS_NOESCAPE ^)(NSURL *newURL))reader {
    if (_isCancelled) {
        if (outError) {
            *outError = [self _cancelledError];
        }
        return;
    }
    reader(url);
}

- (void)coordinateWritingItemAtURL:(NSURL *)url options:(NSFileCoordinatorWritingOptions)options error:(NSError **)outError byAccessor:(void (NS_NOESCAPE ^)(NSURL *newURL))writer {
    if (_isCancelled) {
        if (outError) {
            *outError = [self _cancelledError];
        }
        return;
    }
    writer(url);
}

- (void)coordinateReadingItemAtURL:(NSURL *)readingURL options:(NSFileCoordinatorReadingOptions)readingOptions writingItemAtURL:(NSURL *)writingURL options:(NSFileCoordinatorWritingOptions)writingOptions error:(NSError **)outError byAccessor:(void (NS_NOESCAPE ^)(NSURL *newReadingURL, NSURL *newWritingURL))readerWriter {
    if (_isCancelled) {
        if (outError) {
            *outError = [self _cancelledError];
        }
        return;
    }
    readerWriter(readingURL, writingURL);
}

- (void)coordinateWritingItemAtURL:(NSURL *)url1 options:(NSFileCoordinatorWritingOptions)options1 writingItemAtURL:(NSURL *)url2 options:(NSFileCoordinatorWritingOptions)options2 error:(NSError **)outError byAccessor:(void (NS_NOESCAPE ^)(NSURL *newURL1, NSURL *newURL2))writer {
    if (_isCancelled) {
        if (outError) {
            *outError = [self _cancelledError];
        }
        return;
    }
    writer(url1, url2);
}

#pragma mark *** Batched File Coordination ***

- (void)prepareForReadingItemsAtURLs:(NSArray<NSURL *> *)readingURLs options:(NSFileCoordinatorReadingOptions)readingOptions writingItemsAtURLs:(NSArray<NSURL *> *)writingURLs options:(NSFileCoordinatorWritingOptions)writingOptions error:(NSError **)outError byAccessor:(void (NS_NOESCAPE ^)(void (^completionHandler)(void)))batchAccessor {
    if (_isCancelled) {
        if (outError) {
            *outError = [self _cancelledError];
        }
        return;
    }
    batchAccessor(^{
        /* The port has no asynchronous presenter handshake to complete. */
    });
}

#pragma mark *** Renaming and Moving Notification ***

- (void)itemAtURL:(NSURL *)oldURL willMoveToURL:(NSURL *)newURL {
    /* A sandbox-access announcement under Apple's implementation.  The port is
     * not sandboxed, so there is nothing to record. */
}

- (void)itemAtURL:(NSURL *)oldURL didMoveToURL:(NSURL *)newURL {
    NSArray *presenters = [NSFileCoordinator filePresenters];
    for (id<NSFilePresenter> presenter in presenters) {
        if (presenter == _filePresenter) {
            continue;
        }
        if ([presenter respondsToSelector:@selector(presentedItemDidMoveToURL:)]) {
            NSURL *presented = nil;
            if ([presenter respondsToSelector:@selector(presentedItemURL)]) {
                presented = [presenter presentedItemURL];
            }
            if (presented != nil && [presented isEqual:oldURL]) {
                [presenter presentedItemDidMoveToURL:newURL];
            }
        }
    }
}

#pragma mark *** Ubiquity Attribute Change Notification ***

- (void)itemAtURL:(NSURL *)url didChangeUbiquityAttributes:(NSSet<NSString *> *)attributes {
    NSArray *presenters = [NSFileCoordinator filePresenters];
    for (id<NSFilePresenter> presenter in presenters) {
        if (presenter == _filePresenter) {
            continue;
        }
        if ([presenter respondsToSelector:@selector(presentedItemDidChangeUbiquityAttributes:)]) {
            NSURL *presented = nil;
            if ([presenter respondsToSelector:@selector(presentedItemURL)]) {
                presented = [presenter presentedItemURL];
            }
            if (presented != nil && [presented isEqual:url]) {
                [presenter presentedItemDidChangeUbiquityAttributes:attributes];
            }
        }
    }
}

#pragma mark *** Cancellation ***

- (void)cancel {
    _isCancelled = YES;
}

@end
