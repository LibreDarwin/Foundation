/* Copyright (c) 2006-2007 Christopher J. W. Lloyd, 2008 Johannes Fortmann

Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the "Software"), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE. */

#include <sys/param.h>
#include <pthread.h>
#include <sched.h>
#include <errno.h>
#include <time.h>
#include <math.h>
#include <string.h>
#include <execinfo.h>
#include <objc/runtime.h>
#include <objc/message.h>

#import "NSThread.h"
#import <Foundation/NSException.h>
#import <Foundation/NSString.h>
#import <Foundation/NSArray.h>
#import <Foundation/NSDictionary.h>
#import <Foundation/NSValue.h>
#import <Foundation/NSLock.h>

/* Adaptation notes:
 *
 * - The reference implementation routes current-thread storage through
 *   NSPlatform (NSPlatformSetCurrentThread/NSPlatformCurrentThread). This
 *   tree has no NSPlatform, so that role is played by a pthread-specific key
 *   here (positive key value = an NSThread object for that pthread).
 *
 * - There is no NSNotificationCenter in this Foundation build, so the three
 *   notification names are exported for API compatibility but never posted.
 *
 * - There is no NSAutoreleasePool in this build. The thread entry function
 *   wraps its work in @autoreleasepool instead, and -main is invoked via a
 *   typed objc_msgSend trampoline (the ARC performSelector: warning applies
 *   to the selector-with-object family, not to direct messenger calls).
 *
 * - NSThreadSharedInstance()/NSThreadSharedInstanceDoNotCreate() are
 *   retained because cryptographic consumers like NSRunLoop (once ported)
 *   and the old exception machinery use them.
 */

NSString *const NSDidBecomeSingleThreadedNotification = @"NSDidBecomeSingleThreadedNotification";
NSString *const NSWillBecomeMultiThreadedNotification = @"NSWillBecomeMultiThreadedNotification";
NSString *const NSThreadWillExitNotification = @"NSThreadWillExitNotification";

@implementation NSThread

static BOOL isMultiThreaded = NO;
static NSThread *mainThread = nil;
static pthread_mutex_t mainThreadLock = PTHREAD_MUTEX_INITIALIZER;

static pthread_key_t currentThreadKey;
static pthread_once_t currentThreadKeyOnce = PTHREAD_ONCE_INIT;

static void NSThreadMakeCurrentThreadKey(void) {
    pthread_key_create(&currentThreadKey, NULL);
}

static void NSPlatformSetCurrentThread(NSThread *thread) {
    pthread_once(&currentThreadKeyOnce, NSThreadMakeCurrentThreadKey);
    pthread_setspecific(currentThreadKey, (__bridge const void *)thread);
}

static NSThread *NSPlatformCurrentThread(void) {
    pthread_once(&currentThreadKeyOnce, NSThreadMakeCurrentThreadKey);
    return (__bridge NSThread *)pthread_getspecific(currentThreadKey);
}

+ (BOOL)isMultiThreaded {
    return isMultiThreaded;
}

+ (BOOL)isMainThread {
    return NSCurrentThread() == mainThread;
}

+ (NSThread *)mainThread {
    pthread_mutex_lock(&mainThreadLock);
    if (mainThread == nil) {
        mainThread = [[self alloc] init];
        /* Bind the singleton to the main pthread only. If +mainThread is
         * first touched from a worker, the key is left unset; the main thread
         * picks it up on its own first +currentThread/+mainThread call. */
        if (pthread_main_np() != 0)
            NSPlatformSetCurrentThread(mainThread);
    }
    pthread_mutex_unlock(&mainThreadLock);
    return mainThread;
}

- (id)initWithTarget:(id)aTarget selector:(SEL)aSelector object:(id)anArgument {
    self = [self init];
    if (self) {
        _target = aTarget;
        _selector = aSelector;
        _argument = anArgument;
    }
    return self;
}

- init {
    _dictionary = [NSMutableDictionary new];
    _sharedObjects = [NSMutableDictionary new];
    if (isMultiThreaded)
        _sharedObjectLock = [NSLock new];
    return self;
}

static void *NSThreadMain(void *arg) {
    /* -start handed ownership of the NSThread to us; consume it. */
    NSThread *thread = (__bridge_transfer NSThread *)arg;
    NSPlatformSetCurrentThread(thread);
    thread->_executing = YES;
    @autoreleasepool {
        @try {
            [thread main];
        } @catch (NSException *exception) {
            /* There is no NSLog in this Foundation build; the reference
             * implementation logs and swallows, so we swallow. */
        }
    }
    thread->_executing = NO;
    thread->_finished = YES;
    NSPlatformSetCurrentThread(nil);
    return NULL;
}

+ (void)detachNewThreadSelector:(SEL)selector toTarget:(id)target withObject:(id)argument {
    NSThread *thread = [[self alloc] initWithTarget:target selector:selector object:argument];
    [thread start];
}

+ (NSThread *)currentThread {
    NSThread *thread = NSPlatformCurrentThread();
    if (thread == nil) {
        if (pthread_main_np() != 0)
            return [self mainThread];
        thread = [[self alloc] init];
        NSPlatformSetCurrentThread(thread);
    }
    return thread;
}

+ (NSArray *)callStackReturnAddresses {
    NSMutableArray *result = [NSMutableArray array];
    void *callstack[128];
    int frameCount = backtrace(callstack, 128);
    /* ignore current frame */
    for (int i = 1; i < frameCount; i++) {
        [result addObject:[NSValue valueWithPointer:callstack[i]]];
    }
    return result;
}

+ (NSArray *)callStackSymbols {
    NSMutableArray *result = [NSMutableArray array];
    void *callstack[128];
    int frameCount = backtrace(callstack, 128);
    char **symbols = backtrace_symbols(callstack, frameCount);
    /* ignore current frame */
    for (int i = 1; i < frameCount; i++) {
        [result addObject:[NSString stringWithUTF8String:symbols[i]]];
    }
    free(symbols);
    return result;
}

+ (double)threadPriority {
    struct sched_param scheduling;
    int policy;
    if (pthread_getschedparam(pthread_self(), &policy, &scheduling) != 0)
        return 0.0;
    int min = sched_get_priority_min(policy);
    int max = sched_get_priority_max(policy);
    if (max <= min)
        return 0.0; /* policy without a meaningful range (SCHED_OTHER on Darwin) */
    return (double)(scheduling.sched_priority - min) / (double)(max - min);
}

+ (BOOL)setThreadPriority:(double)value {
    value = MAX(0, MIN(value, 1.0));
    struct sched_param scheduling;
    int policy;
    if (pthread_getschedparam(pthread_self(), &policy, &scheduling) != 0)
        return NO;
    int min = sched_get_priority_min(policy);
    int max = sched_get_priority_max(policy);
    if (max <= min)
        return NO;
    scheduling.sched_priority = (int)lround(min + (max - min) * value);
    return pthread_setschedparam(pthread_self(), policy, &scheduling) == 0;
}

+ (void)sleepUntilDate:(NSDate *)date {
    [self sleepForTimeInterval:[date timeIntervalSinceNow]];
}

+ (void)sleepForTimeInterval:(NSTimeInterval)value {
    if (value <= 0.0)
        return;
    struct timespec ts;
    ts.tv_sec = (time_t)value;
    ts.tv_nsec = (long)((value - (NSTimeInterval)ts.tv_sec) * 1000000000.0);
    while (nanosleep(&ts, &ts) != 0 && errno == EINTR) { }
}

+ (void)exit {
    /* NSThreadWillExitNotification is not posted (no NSNotificationCenter). */
    pthread_exit(NULL);
}

- (void)dealloc {
    if ([self isExecuting])
        [NSException raise:NSInternalInconsistencyException
                    format:@"NSThread deallocated while executing"];
}

- (void)start {
    if (_executing || _finished)
        [NSException raise:NSInvalidArgumentException
                    format:@"thread has already been started"];
    if (!isMultiThreaded) {
        isMultiThreaded = YES;
        /* NSWillBecomeMultiThreadedNotification is not posted (no
         * NSNotificationCenter in this build). */
        if (_sharedObjectLock == nil)
            _sharedObjectLock = [NSLock new];
        if (mainThread != nil && mainThread->_sharedObjectLock == nil)
            mainThread->_sharedObjectLock = [NSLock new];
    }
    if (_sharedObjectLock == nil)
        _sharedObjectLock = [NSLock new];

    void *arg = (__bridge_retained void *)self;
    pthread_t tid;
    int rc;
    if (_stackSize > 0) {
        pthread_attr_t attr;
        pthread_attr_init(&attr);
        pthread_attr_setstacksize(&attr, _stackSize);
        rc = pthread_create(&tid, &attr, NSThreadMain, arg);
        pthread_attr_destroy(&attr);
    } else {
        rc = pthread_create(&tid, NULL, NSThreadMain, arg);
    }
    if (rc != 0) {
        /* pthread_create failed; reclaim the +1 that was never handed off. */
        NSThread *reclaim = (__bridge_transfer NSThread *)arg;
        (void)reclaim;
        [NSException raise:NSGenericException
                    format:@"NSThread: pthread_create failed: %s", strerror(rc)];
    }
    /* Detached: the thread function owns the NSThread reference and the
     * pthread is reclaimed when it returns. */
}

- (BOOL)isMainThread {
    return self == mainThread;
}

- (BOOL)isCancelled {
    return _cancelled;
}

- (BOOL)isExecuting {
    return _executing;
}

- (BOOL)isFinished {
    return _finished;
}

- (void)cancel {
    _cancelled = YES;
}

- (NSString *)name {
    return _name;
}

- (NSUInteger)stackSize {
    return _stackSize;
}

- (NSMutableDictionary *)threadDictionary {
    return _dictionary;
}

- (void)setName:(NSString *)value {
    _name = [value copy];
}

- (void)setStackSize:(NSUInteger)value {
    _stackSize = value;
}

- (void)main {
    if (_target == nil || _selector == NULL)
        return;
    void (*fn)(id, SEL, id) = (void (*)(id, SEL, id))objc_msgSend;
    fn(_target, _selector, _argument);
}

- (NSMutableDictionary *)sharedDictionary {
    return _sharedObjects;
}

static inline id _NSThreadSharedInstance(NSThread *thread, NSString *className, BOOL create) {
    NSMutableDictionary *shared = thread->_sharedObjects;
    if (shared == nil)
        return nil;
    id result = nil;
    [thread->_sharedObjectLock lock];
    result = [shared objectForKey:className];
    [thread->_sharedObjectLock unlock];

    if (result == nil && create) {
        /* do not hold the lock during object allocation */
        result = [NSClassFromString(className) new];
        [thread->_sharedObjectLock lock];
        [shared setObject:result forKey:className];
        [thread->_sharedObjectLock unlock];
    }
    return result;
}

id NSThreadSharedInstance(NSString *className) {
    return _NSThreadSharedInstance(NSPlatformCurrentThread(), className, YES);
}

id NSThreadSharedInstanceDoNotCreate(NSString *className) {
    return _NSThreadSharedInstance(NSPlatformCurrentThread(), className, NO);
}

- sharedObjectForClassName:(NSString *)className {
    return _NSThreadSharedInstance(self, className, YES);
}

- (void)setSharedObject:(id)object forClassName:(NSString *)className {
    [_sharedObjectLock lock];
    if (object == nil)
        [_sharedObjects removeObjectForKey:className];
    else
        [_sharedObjects setObject:object forKey:className];
    [_sharedObjectLock unlock];
}

- (NSString *)description {
    return [NSString stringWithFormat:@"<%@: %p threadDictionary: %@>", object_getClass(self), self, _dictionary];
}

@end

@implementation NSObject (NSThread)

- (void)performSelector:(SEL)selector onThread:(NSThread *)thread withObject:(id)object waitUntilDone:(BOOL)waitUntilDone modes:(NSArray *)modes {
    if (thread == nil) {
        [NSException raise:NSInvalidArgumentException
                    format:@"-%s: thread is nil", sel_getName(_cmd)];
        return;
    }
    /* Cross-thread delivery requires a run loop on the target thread.
     * NSRunLoop is not implemented in this Foundation build, so the
     * same-thread synchronous case is handled directly and everything else
     * raises, matching Apple's failure mode for a thread without a run loop. */
    if (waitUntilDone && thread == [NSThread currentThread]) {
        void (*fn)(id, SEL, id) = (void (*)(id, SEL, id))objc_msgSend;
        fn(self, selector, object);
        return;
    }
    [NSException raise:NSInvalidArgumentException
                format:@"-%s: thread has no run loop (NSRunLoop is not implemented in this Foundation build)", sel_getName(_cmd)];
}

- (void)performSelector:(SEL)selector onThread:(NSThread *)thread withObject:(id)object waitUntilDone:(BOOL)waitUntilDone {
    /* modes are only consulted by run-loop delivery, which this build cannot
     * perform, so nil is equivalent to the reference's NSRunLoopCommonModes. */
    [self performSelector:selector onThread:thread withObject:object waitUntilDone:waitUntilDone modes:nil];
}

- (void)performSelectorOnMainThread:(SEL)selector withObject:(id)object waitUntilDone:(BOOL)waitUntilDone modes:(NSArray *)modes {
    [self performSelector:selector onThread:[NSThread mainThread] withObject:object waitUntilDone:waitUntilDone modes:modes];
}

- (void)performSelectorOnMainThread:(SEL)selector withObject:(id)object waitUntilDone:(BOOL)waitUntilDone {
    [self performSelectorOnMainThread:selector withObject:object waitUntilDone:waitUntilDone modes:nil];
}

- (void)performSelectorInBackground:(SEL)selector withObject:(id)object {
    [NSThread detachNewThreadSelector:selector toTarget:self withObject:object];
}

@end

NSThread *NSCurrentThread(void) {
    return NSPlatformCurrentThread();
}