/* Copyright (c) 2008 Johannes Fortmann

 Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the "Software"), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:

 The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.

 THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE. */

#import "NSRecursiveLock.h"
#import "NSLockSupport.h"

#import <Foundation/NSException.h>
#import <Foundation/NSString.h>

#import <pthread.h>

/* CoreFoundation-free build of the Cocotron/ravynOS NSRecursiveLock_posix.
 * The NSThread-based ownership is tracked with pthread_t instead; the lock is
 * a plain mutex, with re-entrancy handled by the owner/depth bookkeeping
 * rather than a PTHREAD_MUTEX_RECURSIVE attribute, so that -lockBeforeDate:
 * can apply a real deadline to the first (non-owned) acquisition. */
@implementation NSRecursiveLock {
    pthread_mutex_t _mutex;
    pthread_t _lockingThread;
    NSUInteger _numberOfLocks;
    NSString *_name;
}

- (instancetype)init {
    if ((self = [super init]) != nil) {
        if (pthread_mutex_init(&_mutex, NULL) != 0) {
            [NSException raise:NSGenericException
                        format:@"NSRecursiveLock: unable to initialise the mutex"];
        }
        _lockingThread = (pthread_t)0;
    }
    return self;
}

- (void)dealloc {
    pthread_mutex_destroy(&_mutex);
}

- (void)lock {
    if (pthread_equal(pthread_self(), _lockingThread)) {
        _numberOfLocks++;
        return;
    }
    if (pthread_mutex_lock(&_mutex) != 0) {
        [NSException raise:NSGenericException
                    format:@"NSRecursiveLock: failed to acquire the lock"];
    }
    _lockingThread = pthread_self();
    _numberOfLocks = 1;
}

- (void)unlock {
    if (pthread_equal(pthread_self(), _lockingThread)) {
        if (--_numberOfLocks == 0) {
            _lockingThread = (pthread_t)0;
            if (pthread_mutex_unlock(&_mutex) != 0) {
                [NSException raise:NSGenericException
                            format:@"NSRecursiveLock: failed to release the lock"];
            }
        }
    } else {
        [NSException raise:NSInvalidArgumentException
                    format:@"NSRecursiveLock: attempted to unlock from a thread that does not hold the lock"];
    }
}

- (BOOL)tryLock {
    if (pthread_equal(pthread_self(), _lockingThread)) {
        _numberOfLocks++;
        return YES;
    }
    if (pthread_mutex_trylock(&_mutex) == 0) {
        _lockingThread = pthread_self();
        _numberOfLocks = 1;
        return YES;
    }
    return NO;
}

- (BOOL)lockBeforeDate:(NSDate *)limit {
    if ([self tryLock]) {
        /* Already owned by this thread (depth incremented), or the mutex was
         * free and we won it outright. */
        return YES;
    }

    if (NSLockTimedAcquire(&_mutex, limit)) {
        _lockingThread = pthread_self();
        _numberOfLocks = 1;
        return YES;
    }
    return NO;
}

- (BOOL)isLocked {
    return _numberOfLocks != 0;
}

- (NSString *)name {
    return _name;
}

- (void)setName:(NSString *)name {
    if (name != _name) {
        _name = [name copy];
    }
}

@end