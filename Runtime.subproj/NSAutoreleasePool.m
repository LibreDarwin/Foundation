/*
 * Copyright (C) 2026, PureDarwin Project.
 *
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */

#import <Foundation/NSAutoreleasePool.h>
#import <Foundation/NSAutoreleasePoolInternal.h>
#import <Foundation/NSException.h>
#include <CoreFoundation/CFBase.h>
#include <pthread.h>
#include <stdint.h>
#include <stdlib.h>
#include <string.h>

/* The runtime's autorelease pool entry points.  They are declared in
 * <objc/objc-internal.h>, which is not a public SDK header, but the
 * Internal SDK's libobjc.A.tbd exports all three. */
extern void *objc_autoreleasePoolPush(void);
extern void objc_autoreleasePoolPop(void *token);
extern void objc_autorelease(id object);

/* ---------------------------------------------------------------------
 * Storage for the instance -addObject: list.
 *
 * Apple hands an object to a specific pool with
 * objc_autoreleasePoolAddObject(token, obj), which pushes onto that pool's
 * own runtime page.  The runtime does not export that entry point, so the
 * list cannot live in a runtime page here.  It also cannot be an ivar: the
 * instance layout is Apple's four pointer ivars and nothing more, so adding
 * one would change instanceSize from 40 to 48 and every caller compiled
 * against Apple's Foundation would read the wrong offsets.
 *
 * So the list hangs off a process-global side table keyed by the pool
 * pointer.  A single lock covers it: pools are thread-local in practice, but
 * -addObject: takes an arbitrary object and may be reached from any thread.
 *
 * Known deviation: Apple's -addObject: and its runtime page share one LIFO
 * stack, so the two kinds of object are released interleaved.  Here the
 * runtime page is popped first and the side list afterwards, so a caller
 * that mixes +[NSAutoreleasePool addObject:] with -[addObject:] on a
 * non-top pool sees a different dealloc order.  Everything else - the
 * ownership transfer, the LIFO order within the list, and the "this pool is
 * gone, ignore the add" rule - matches.
 * --------------------------------------------------------------------- */

typedef struct {
    NSAutoreleasePool *pool;
    id *objects;
    size_t count;
    size_t capacity;
} __NSAutoreleasePoolEntry;

static __NSAutoreleasePoolEntry *__NSAutoreleasePoolEntries = NULL;
static size_t __NSAutoreleasePoolEntryCount = 0;
static pthread_mutex_t __NSAutoreleasePoolLock = PTHREAD_MUTEX_INITIALIZER;

/* Takes ownership of anObject: no retain, matching -addObject:. */
static void __NSAutoreleasePoolAddObject(NSAutoreleasePool *pool, id anObject) {
    pthread_mutex_lock(&__NSAutoreleasePoolLock);

    __NSAutoreleasePoolEntry *entry = NULL;
    for (size_t i = 0; i < __NSAutoreleasePoolEntryCount; i++) {
        if (__NSAutoreleasePoolEntries[i].pool == pool) {
            entry = &__NSAutoreleasePoolEntries[i];
            break;
        }
    }

    if (entry == NULL) {
        __NSAutoreleasePoolEntry *grown =
            realloc(__NSAutoreleasePoolEntries,
                    (__NSAutoreleasePoolEntryCount + 1) * sizeof(__NSAutoreleasePoolEntry));
        if (grown == NULL) {
            pthread_mutex_unlock(&__NSAutoreleasePoolLock);
            [NSException raise:NSMallocException
                        format:@"*** -[NSAutoreleasePool addObject:]: cannot grow the pool table"];
            return;
        }
        __NSAutoreleasePoolEntries = grown;
        entry = &__NSAutoreleasePoolEntries[__NSAutoreleasePoolEntryCount++];
        entry->pool = pool;
        entry->objects = NULL;
        entry->count = 0;
        entry->capacity = 0;
    }

    if (entry->count == entry->capacity) {
        size_t capacity = entry->capacity == 0 ? 16 : entry->capacity * 2;
        if (capacity <= entry->capacity) {
            pthread_mutex_unlock(&__NSAutoreleasePoolLock);
            [NSException raise:NSMallocException
                        format:@"*** -[NSAutoreleasePool addObject:]: pool list overflow"];
            return;
        }
        id *grown = realloc(entry->objects, capacity * sizeof(id));
        if (grown == NULL) {
            pthread_mutex_unlock(&__NSAutoreleasePoolLock);
            [NSException raise:NSMallocException
                        format:@"*** -[NSAutoreleasePool addObject:]: cannot grow the pool list"];
            return;
        }
        entry->objects = grown;
        entry->capacity = capacity;
    }

    entry->objects[entry->count++] = anObject;

    pthread_mutex_unlock(&__NSAutoreleasePoolLock);
}

/* Detaches the pool's list and hands it back for release outside the lock:
 * a -dealloc reached from objc_autoreleasePoolPop below can add to another
 * pool, and that must not deadlock. */
static id *__NSAutoreleasePoolTakeObjects(NSAutoreleasePool *pool, size_t *count) {
    pthread_mutex_lock(&__NSAutoreleasePoolLock);

    id *objects = NULL;
    *count = 0;

    for (size_t i = 0; i < __NSAutoreleasePoolEntryCount; i++) {
        if (__NSAutoreleasePoolEntries[i].pool != pool) {
            continue;
        }
        objects = __NSAutoreleasePoolEntries[i].objects;
        *count = __NSAutoreleasePoolEntries[i].count;
        __NSAutoreleasePoolEntries[i].objects = NULL;
        __NSAutoreleasePoolEntries[i].count = 0;
        __NSAutoreleasePoolEntries[i].capacity = 0;
        __NSAutoreleasePoolEntries[i].pool = NULL;

        if (i + 1 < __NSAutoreleasePoolEntryCount) {
            memmove(&__NSAutoreleasePoolEntries[i], &__NSAutoreleasePoolEntries[i + 1],
                    (__NSAutoreleasePoolEntryCount - i - 1) * sizeof(__NSAutoreleasePoolEntry));
        }
        __NSAutoreleasePoolEntryCount--;
        break;
    }

    pthread_mutex_unlock(&__NSAutoreleasePoolLock);
    return objects;
}

static void __NSAutoreleasePoolReleaseObjects(id *objects, size_t count) {
    /* LIFO, like the runtime page it stands in for. */
    while (count > 0) {
        [objects[--count] release];
    }
    free(objects);
}

/* ---------------------------------------------------------------------
 * Debug hooks.  Inert on a modern runtime: the pool is now
 * objc_autoreleasePoolPush/-Pop inside libobjc and keeps none of these
 * counters.  Apple's Foundation exports them and answers 0/NO, so this
 * matches exactly.  -[NSAutoreleasePool showPools] is the one place that
 * cannot match: Apple's reaches CF's private pool printer, and
 * objc_autoreleasePoolPrint is listed in libobjc.A.tbd but absent from the
 * running dyld, so +showPools logs nothing here.
 * --------------------------------------------------------------------- */

void *__NSAutoreleasePoolGetRubyToken(void) {
    return (void *)(uintptr_t)62;
}

void __NSAutoreleasePoolSetRubyToken(void *token) {
    (void)token;
}

unsigned long _NSAutoreleasePoolCount(void) {
    return 0;
}

@implementation NSAutoreleasePool

+ (void)addObject:(id)anObject {
    /* Apple passes a NULL pool, which means "the current thread's top pool".
     * That is exactly objc_autorelease's contract. */
    objc_autorelease(anObject);
}

- (instancetype)init {
    _token = objc_autoreleasePoolPush();
    _reserved3 = NULL;
    _reserved2 = NULL;
    _reserved = NULL;
    return self;
}

- (instancetype)initWithCapacity:(NSUInteger)capacity {
    (void)capacity;
    NSLog(@"*** -[NSAutoreleasePool initWithCapacity:]: Do not use this init method.");
    return [self init];
}

- (void)addObject:(id)anObject {
    /* The counter is process-global and its cadence is Apple's: the log
     * fires on calls 1, 17, 33, ... because the value returned by the atomic
     * add is tested against 0xf. */
    static int64_t addCount;
    if ((__sync_fetch_and_add(&addCount, 1) & 0xf) == 0) {
        NSLog(@"*** -[NSAutoreleasePool addObject:]: Do not use this instance method on specific pools -- just use -autorelease instead.");
    }

    if (_token == NULL) {
        /* Drained or released: Apple drops the add silently, and only after
         * logging the line above. */
        return;
    }
    __NSAutoreleasePoolAddObject(self, anObject);
}

- (void)drain {
    if (_reserved2 != NULL) {
        NSLog(@"*** -[NSAutoreleasePool drain]: This pool has already been released, do not drain it (double release).");
    }
    if (_reserved3 != NULL) {
        NSLog(@"*** -[NSAutoreleasePool drain]: This pool has already been drained, do not release it (double release).");
    }

    void *token = _token;
    _token = NULL;
    _reserved3 = (void *)-1;

    if (token != NULL) {
        objc_autoreleasePoolPop(token);
    }

    size_t count;
    id *objects = __NSAutoreleasePoolTakeObjects(self, &count);
    __NSAutoreleasePoolReleaseObjects(objects, count);
}

- (void)release {
    if (_reserved2 != NULL) {
        NSLog(@"*** -[NSAutoreleasePool release]: This pool has already been released, do not drain it (double release).");
    }
    if (_reserved3 != NULL) {
        NSLog(@"*** -[NSAutoreleasePool release]: This pool has already been drained, do not release it (double release).");
    }

    void *token = _token;
    _reserved2 = (void *)-1;
    _token = NULL;

    if (token != NULL) {
        objc_autoreleasePoolPop(token);
    }

    size_t count;
    id *objects = __NSAutoreleasePoolTakeObjects(self, &count);
    __NSAutoreleasePoolReleaseObjects(objects, count);
}

- (instancetype)retain {
    [[NSException exceptionWithName:NSInvalidArgumentException
                              reason:@"*** -[NSAutoreleasePool retain]: Cannot retain an autorelease pool"
                            userInfo:nil] raise];
    return self;
}

- (NSUInteger)retainCount {
    return 1;
}

- (instancetype)autorelease {
    [[NSException exceptionWithName:NSInvalidArgumentException
                              reason:@"*** -[NSAutoreleasePool autorelease]: Cannot autorelease an autorelease pool"
                            userInfo:nil] raise];
    return self;
}

- (void)dealloc {
    NSLog(@"*** -[NSAutoreleasePool dealloc]: WARNING: Do not call this method directly.");
}

+ (void)showPools {
}

+ (void)releaseAllPools {
}

+ (unsigned long)autoreleasedObjectCount {
    return 0;
}

+ (NSUInteger)topAutoreleasePoolCount {
    return 0;
}

+ (BOOL)autoreleasePoolExists {
    return NO;
}

+ (void)enableRelease:(BOOL)flag {
    (void)flag;
}

+ (void)enableFreedObjectCheck:(BOOL)flag {
    (void)flag;
}

+ (unsigned long)poolCountHighWaterMark {
    return 0;
}

+ (void)setPoolCountHighWaterMark:(unsigned long)mark {
    (void)mark;
}

+ (unsigned long)poolCountHighWaterResolution {
    return 0;
}

+ (void)setPoolCountHighWaterResolution:(unsigned long)resolution {
    (void)resolution;
}

+ (unsigned long)totalAutoreleasedObjects {
    return 0;
}

+ (void)resetTotalAutoreleasedObjects {
}

@end