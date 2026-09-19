/*
 * Copyright (C) 2026, Samuel Zormeister.
 *
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */

#ifndef NSLockSupport_h
#define NSLockSupport_h

#import <Foundation/NSDate.h>

#import <math.h>
#import <pthread.h>
#import <time.h>

/* Absolute CLOCK_REALTIME deadline for an NSTimeInterval measured from now.
 * Shared by NSLock, NSCondition and NSConditionLock so every timed
 * acquisition applies the same deadline arithmetic. */
static inline struct timespec NSLockDeadline(NSTimeInterval interval) {
    struct timespec deadline;

    clock_gettime(CLOCK_REALTIME, &deadline);
    if (interval <= 0) {
        /* Already expired; the caller will get an immediate timeout. */
        return deadline;
    }

    deadline.tv_sec += (time_t)interval;
    long nanos = (long)(fmod(interval, 1.0) * 1000000000.0);
    deadline.tv_nsec += nanos;
    if (deadline.tv_nsec >= 1000000000L) {
        deadline.tv_nsec -= 1000000000L;
        deadline.tv_sec += 1;
    }
    return deadline;
}

/* Darwin has pthread_cond_timedwait but no pthread_mutex_timedlock, so timed
 * mutex acquisition polls trylock until the deadline. 20 ms granularity keeps
 * the overshoot well inside what the "lock before date" contract tolerates. */
static inline BOOL NSLockTimedAcquire(pthread_mutex_t *mutex, NSDate *limit) {
    struct timespec deadline = NSLockDeadline([limit timeIntervalSinceNow]);

    for (;;) {
        if (pthread_mutex_trylock(mutex) == 0) {
            return YES;
        }
        struct timespec now;
        clock_gettime(CLOCK_REALTIME, &now);
        if (now.tv_sec > deadline.tv_sec ||
            (now.tv_sec == deadline.tv_sec && now.tv_nsec >= deadline.tv_nsec)) {
            return NO;
        }
        struct timespec pause = {0, 20000000L};
        nanosleep(&pause, NULL);
    }
}

#endif /* NSLockSupport_h */