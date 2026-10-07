/*
 * Copyright (C) 2026, LibreDarwin.
 *
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */

#import <Foundation/NSObject.h>

@class NSString, NSMutableArray;

@interface NSMethodSignature : NSObject {
    char *_typesCString;
    char *_returnType;
    NSUInteger _numberOfArguments;
    char **_types;

    void *_closure;
    void *_closureInfo;
}

+ (NSMethodSignature *)signatureWithObjCTypes:(const char *)types;

- (BOOL)isOneway;
- (NSUInteger)frameLength;
- (NSUInteger)methodReturnLength;

- (const char *)methodReturnType;

- (NSUInteger)numberOfArguments;

- (const char *)getArgumentTypeAtIndex:(NSUInteger)index;

@end
