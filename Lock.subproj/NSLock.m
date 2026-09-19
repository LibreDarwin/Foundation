/* Copyright (c) 2006-2007 Christopher J. W. Lloyd

 Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the "Software"), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:

 The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.

 THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE. */

#import "NSLock.h"
#import "NSLockSupport.h"

#import <Foundation/NSException.h>
#import <Foundation/NSString.h>

#import <pthread.h>

/* CoreFoundation-free build of the Cocotron/ravynOS NSLock_posix, with the
 * NSPlatform machinery removed. */
@implementation NSLock {
    pthread_mutex_t _mutex;
    NSString *_name;
}

- (instancetype)init {
    if ((self = [super init]) != nil) {
        if (pthread_mutex_init(&_mutex, NULL) != 0) {
            [NSException raise:NSGenericException
                        format:@"NSLock: unable to initialise the mutex"];
        }
    }
    return self;
}

- (void)dealloc {
    pthread_mutex_destroy(&_mutex);
}

- (void)lock {
    if (pthread_mutex_lock(&_mutex) != 0) {
        [NSException raise:NSGenericException
                    format:@"NSLock: failed to acquire the lock"];
    }
}

- (void)unlock {
    if (pthread_mutex_unlock(&_mutex) != 0) {
        [NSException raise:NSGenericException
                    format:@"NSLock: failed to release the lock"];
    }
}

- (BOOL)tryLock {
    return pthread_mutex_trylock(&_mutex) == 0;
}

- (BOOL)lockBeforeDate:(NSDate *)limit {
    return NSLockTimedAcquire(&_mutex, limit);
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