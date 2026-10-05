/*
 * Copyright (C) 2026, PureDarwin Project.
 *
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */

#import <Foundation/NSException.h>
#import <Foundation/NSArray.h>
#import <Foundation/NSDictionary.h>
#import <Foundation/NSNumber.h>
#import <Foundation/NSString.h>
#include <string.h>
#include <execinfo.h>
#include <stdlib.h>

NSExceptionName const NSGenericException = @"NSGenericException";
NSExceptionName const NSRangeException = @"NSRangeException";
NSExceptionName const NSInvalidArgumentException = @"NSInvalidArgumentException";
NSExceptionName const NSInternalInconsistencyException = @"NSInternalInconsistencyException";
NSExceptionName const NSMallocException = @"NSMallocException";
NSExceptionName const NSObjectNotAvailableException = @"NSObjectNotAvailableException";
NSExceptionName const NSDestinationInvalidException = @"NSDestinationInvalidException";
NSExceptionName const NSInvalidArchiveOperationException = @"NSInvalidArchiveOperationException";
NSExceptionName const NSInvalidUnarchiveOperationException = @"NSInvalidUnarchiveOperationException";

static NSUncaughtExceptionHandler *_uncaughtHandler = NULL;

NSUncaughtExceptionHandler *NSGetUncaughtExceptionHandler(void) {
    return _uncaughtHandler;
}

void NSSetUncaughtExceptionHandler(NSUncaughtExceptionHandler *handler) {
    _uncaughtHandler = handler;
}

@implementation NSException {
    NSExceptionName _name;
    NSString *_reason;
    NSDictionary *_userInfo;
    void *_returnAddresses[128];
    int _returnAddressCount;
}

/* This file is built with -fno-objc-arc (it is listed in MRC_GATE_PAT in
 * Common.mk), so the ownership of the three object ivars has to be spelled out
 * by hand: acquired in -init... and released in -dealloc.  Without this the
 * exception kept its name, reason and userInfo unretained and leaked the whole
 * object on every raise. */

+ (instancetype)exceptionWithName:(NSExceptionName)name
                           reason:(NSString *)reason
                         userInfo:(NSDictionary *)userInfo {
    return [[[self alloc] initWithName:name reason:reason userInfo:userInfo] autorelease];
}

+ (void)raise:(NSExceptionName)name format:(NSString *)format, ... {
    va_list args;
    va_start(args, format);
    [self raise:name format:format arguments:args];
    va_end(args);
}

+ (void)raise:(NSExceptionName)name format:(NSString *)format arguments:(va_list)args {
    /* -raise throws, so the reason cannot be released after the call; it is
     * autoreleased instead and handed off to the enclosing pool. */
    NSString *reason = [[[NSString alloc] initWithFormat:format arguments:args] autorelease];
    [[self exceptionWithName:name reason:reason userInfo:nil] raise];
}

- (instancetype)initWithName:(NSExceptionName)name
                      reason:(NSString *)reason
                    userInfo:(NSDictionary *)userInfo {
    self = [super init];
    if (self != nil) {
        _name = [name retain];
        _reason = [reason retain];
        _userInfo = [userInfo retain];
    }
    return self;
}

- (void)dealloc {
    [_name release];
    [_reason release];
    [_userInfo release];
    [super dealloc];
}

- (void)raise {
    if (_returnAddressCount == 0) {
        _returnAddressCount = backtrace(_returnAddresses, 128);
    }
    if (_uncaughtHandler != NULL) {
        _uncaughtHandler(self);
    }
    @throw self;
}

- (NSExceptionName)name {
    return _name;
}

- (NSString *)reason {
    return _reason;
}

- (NSDictionary *)userInfo {
    return _userInfo;
}

- (NSArray *)callStackReturnAddresses {
    NSMutableArray *addresses = [NSMutableArray arrayWithCapacity:(NSUInteger)_returnAddressCount];
    for (int i = 0; i < _returnAddressCount; i++) {
        [addresses addObject:[NSNumber numberWithUnsignedLongLong:(unsigned long long)(uintptr_t)_returnAddresses[i]]];
    }
    return addresses;
}

- (NSArray *)callStackSymbols {
    NSMutableArray<NSString *> *symbols = [NSMutableArray arrayWithCapacity:(NSUInteger)_returnAddressCount];
    char **names = backtrace_symbols(_returnAddresses, _returnAddressCount);
    if (names == NULL) {
        return symbols;
    }

    for (int i = 0; i < _returnAddressCount; i++) {
        /* Autoreleased: the array holds the only strong reference, and this is
         * a non-new accessor, so the strings are handed to the enclosing pool
         * rather than left at +1. */
        NSString *symbol = [[[NSString alloc] initWithBytes:names[i]
                                                    length:strlen(names[i])
                                                  encoding:NSUTF8StringEncoding] autorelease];
        [symbols addObject:symbol];
    }
    free(names);
    return symbols;
}

- (NSString *)description {
    return _reason;
}

- (BOOL)isEqual:(id)object {
    if (object == self) {
        return YES;
    }
    if (![object isKindOfClass:[NSException class]]) {
        return NO;
    }
    NSException *ex = (NSException *)object;
    return (_name == [ex name] || [_name isEqual:[ex name]])
        && (_reason == [ex reason] || [_reason isEqual:[ex reason]]);
}

- (NSUInteger)hash {
    return [_name hash] ^ [_reason hash];
}

- (id)copyWithZone:(NSZone *)zone {
    (void)zone;
    /* NSException is immutable, so -copy legitimately returns the same object,
     * but it must still hand back a +1 reference.  Returning bare `self` made
     * every caller over-release; that stayed invisible only while this file had
     * no -dealloc, and became a use-after-free as soon as one was added. */
    return [self retain];
}

@end

void NSAssertionFailure(const char *function, const char *file, int line,
                        NSString *format, ...) {
    va_list args;
    va_start(args, format);
    NSString *reason = [[[NSString alloc] initWithFormat:format arguments:args] autorelease];
    va_end(args);

    /* Both strings are autoreleased rather than left owned by a leaked +1,
     * because -raise throws and never returns to release them. */
    NSString *final = [[[NSString alloc] initWithFormat:@"%s (%s:%d): %@",
                        function, file, line, reason] autorelease];
    [[NSException exceptionWithName:NSInternalInconsistencyException
                             reason:final
                           userInfo:nil] raise];
}
