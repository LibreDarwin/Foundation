/* Copyright (c) 2010 Sven Weidauer

 Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the "Software"), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:

 The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.

 THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE. */

#import "NSCondition.h"
#import "NSLockSupport.h"

#import <Foundation/NSException.h>
#import <Foundation/NSString.h>

#import <errno.h>
#import <pthread.h>

/* CoreFoundation-free build of the Cocotron/ravynOS NSCondition_posix,
 * extended with -waitUntilDate: (the timed variant the original lacked). */
@implementation NSCondition {
    pthread_mutex_t _mutex;
    pthread_cond_t _condition;
    NSString *_name;
}

- (instancetype)init {
    if ((self = [super init]) != nil) {
        if (pthread_mutex_init(&_mutex, NULL) != 0 ||
            pthread_cond_init(&_condition, NULL) != 0) {
            [NSException raise:NSGenericException
                        format:@"NSCondition: unable to initialise the condition pair"];
        }
    }
    return self;
}

- (void)dealloc {
    pthread_cond_destroy(&_condition);
    pthread_mutex_destroy(&_mutex);
}

- (void)lock {
    if (pthread_mutex_lock(&_mutex) != 0) {
        [NSException raise:NSGenericException
                    format:@"NSCondition: failed to acquire the lock"];
    }
}

- (void)unlock {
    if (pthread_mutex_unlock(&_mutex) != 0) {
        [NSException raise:NSGenericException
                    format:@"NSCondition: failed to release the lock"];
    }
}

- (void)wait {
    if (pthread_cond_wait(&_condition, &_mutex) != 0) {
        [NSException raise:NSGenericException
                    format:@"NSCondition: failed to wait"];
    }
}

- (BOOL)waitUntilDate:(NSDate *)limit {
    struct timespec deadline = NSLockDeadline([limit timeIntervalSinceNow]);

    int result = pthread_cond_timedwait(&_condition, &_mutex, &deadline);
    if (result == 0) {
        return YES;
    }
    if (result == ETIMEDOUT) {
        return NO;
    }
    [NSException raise:NSGenericException
                format:@"NSCondition: failed to wait until %@", limit];
    return NO;
}

- (void)signal {
    if (pthread_cond_signal(&_condition) != 0) {
        [NSException raise:NSGenericException
                    format:@"NSCondition: failed to signal"];
    }
}

- (void)broadcast {
    if (pthread_cond_broadcast(&_condition) != 0) {
        [NSException raise:NSGenericException
                    format:@"NSCondition: failed to broadcast"];
    }
}

- (NSString *)name {
    return _name;
}

- (void)setName:(NSString *)newName {
    if (newName != _name) {
        _name = [newName copy];
    }
}

@end