/* Copyright (c) 2007 Christopher J. W. Lloyd

 Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the "Software"), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:

 The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.

 THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE. */

#import "NSConditionLock.h"
#import "NSLockSupport.h"

#import <Foundation/NSException.h>
#import <Foundation/NSString.h>

#import <errno.h>
#import <pthread.h>

/* CoreFoundation-free build of the Cocotron/ravynOS NSConditionLock_posix.
 * The NSThread-based lock ownership is tracked with pthread_t instead.
 *
 * Two bugs in the original are corrected here:
 *  - -tryLockWhenCondition: returned NO when the lock had actually been
 *    acquired (a stray "if ([self tryLock]) return NO;").
 *  - -lockBeforeDate:/-lockWhenCondition:beforeDate: acquired the mutex with
 *    a blocking pthread_mutex_lock() and only applied the deadline to the
 *    subsequent condition wait, so a held lock could block the caller past
 *    the deadline. Timed acquisition now polls pthread_mutex_trylock up to
 *    the deadline (there is no pthread_mutex_timedlock on Darwin), so the
 *    deadline is honoured end to end. */
@implementation NSConditionLock {
    pthread_cond_t _condition;
    pthread_mutex_t _mutex;
    NSInteger _value;
    pthread_t _lockingThread;
}

- (instancetype)init {
    return [self initWithCondition:0];
}

- (instancetype)initWithCondition:(NSInteger)condition {
    if ((self = [super init]) != nil) {
        if (pthread_cond_init(&_condition, NULL) != 0 ||
            pthread_mutex_init(&_mutex, NULL) != 0) {
            [NSException raise:NSGenericException
                        format:@"NSConditionLock: unable to initialise the condition pair"];
        }
        _value = condition;
        _lockingThread = (pthread_t)0;
    }
    return self;
}

- (void)dealloc {
    pthread_cond_destroy(&_condition);
    pthread_mutex_destroy(&_mutex);
}

- (NSInteger)condition {
    return _value;
}

- (void)lock {
    if (pthread_mutex_lock(&_mutex) != 0) {
        [NSException raise:NSGenericException
                    format:@"NSConditionLock: failed to acquire the lock"];
    }
    _lockingThread = pthread_self();
}

- (void)unlock {
    if (!pthread_equal(_lockingThread, pthread_self())) {
        [NSException raise:NSInvalidArgumentException
                    format:@"NSConditionLock: attempted to unlock from a thread that does not hold the lock"];
        return;
    }
    _lockingThread = (pthread_t)0;
    pthread_mutex_unlock(&_mutex);
}

- (BOOL)tryLock {
    if (pthread_mutex_trylock(&_mutex) != 0) {
        return NO;
    }
    _lockingThread = pthread_self();
    return YES;
}

- (BOOL)tryLockWhenCondition:(NSInteger)condition {
    if (![self tryLock]) {
        return NO;
    }
    if (_value == condition) {
        return YES;
    }
    [self unlock];
    return NO;
}

- (void)lockWhenCondition:(NSInteger)condition {
    if (pthread_mutex_lock(&_mutex) != 0) {
        [NSException raise:NSGenericException
                    format:@"NSConditionLock: failed to acquire the lock"];
    }
    while (_value != condition) {
        if (pthread_cond_wait(&_condition, &_mutex) != 0) {
            [NSException raise:NSGenericException
                        format:@"NSConditionLock: failed to wait for the condition"];
        }
    }
    _lockingThread = pthread_self();
}

- (void)unlockWithCondition:(NSInteger)condition {
    if (!pthread_equal(_lockingThread, pthread_self())) {
        [NSException raise:NSInvalidArgumentException
                    format:@"NSConditionLock: attempted to unlock from a thread that does not hold the lock"];
        return;
    }
    _lockingThread = (pthread_t)0;
    _value = condition;
    pthread_mutex_unlock(&_mutex);
    pthread_cond_broadcast(&_condition);
}

- (BOOL)lockBeforeDate:(NSDate *)limit {
    if (!NSLockTimedAcquire(&_mutex, limit)) {
        return NO;
    }
    _lockingThread = pthread_self();
    return YES;
}

- (BOOL)lockWhenCondition:(NSInteger)condition beforeDate:(NSDate *)limit {
    if (!NSLockTimedAcquire(&_mutex, limit)) {
        return NO;
    }

    while (_value != condition) {
        struct timespec deadline = NSLockDeadline([limit timeIntervalSinceNow]);
        int result = pthread_cond_timedwait(&_condition, &_mutex, &deadline);
        if (result == ETIMEDOUT) {
            pthread_mutex_unlock(&_mutex);
            return NO;
        }
        if (result != 0) {
            pthread_mutex_unlock(&_mutex);
            [NSException raise:NSGenericException
                        format:@"NSConditionLock: failed to wait for the condition before %@", limit];
            return NO;
        }
    }
    _lockingThread = pthread_self();
    return YES;
}

- (NSString *)name {
    return _name;
}

- (void)setName:(NSString *)value {
    if (value != _name) {
        _name = [value copy];
    }
}

@end