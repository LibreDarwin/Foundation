/*
 * Copyright (C) 2026, LibreDarwin.
 *
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */

#import <Foundation/NSObject.h>

@class NSMethodSignature;

@interface NSInvocation : NSObject <NSCoding> {
    NSMethodSignature *_signature;

    NSUInteger _returnSize;
    uint8_t *_returnValue;

    NSUInteger _argumentFrameSize;
    NSUInteger *_argumentSizes;
    NSUInteger *_argumentOffsets;
    uint8_t *_argumentFrame;

    BOOL _retainArguments;
}

+ (NSInvocation *)invocationWithMethodSignature:(NSMethodSignature *)signature;

- (NSMethodSignature *)methodSignature;

- (void)getReturnValue:(void *)pointerToValue;
- (void)setReturnValue:(void *)pointerToValue;

- (void)getArgument:(void *)pointerToValue atIndex:(NSInteger)index;
- (void)setArgument:(void *)pointerToValue atIndex:(NSInteger)index;

- (void)retainArguments;
- (BOOL)argumentsRetained;

- (SEL)selector;
- (void)setSelector:(SEL)selector;

- target;
- (void)setTarget:target;

- (void)invoke;
- (void)invokeWithTarget:target;

@end
