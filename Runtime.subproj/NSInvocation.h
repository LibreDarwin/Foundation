/*
 * Copyright (C) 2026, LibreDarwin.
 *
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */

#import <Foundation/NSObject.h>

@class NSMethodSignature;

/*
 * The first nine ivars reproduce the instance layout CoreFoundation reads
 * directly when it drives forwarding (offsets are relative to the object
 * pointer, i.e. after NSObject's isa):
 *
 *     _frame          +0x08   argument frame
 *     _retdata        +0x10   return-value / backing buffer
 *     _signature      +0x18
 *     _container      +0x20
 *     _replacedByPointerBacking +0x28
 *     _pac_signature  +0x30
 *     _magic          +0x38
 *     _retainedArgs   +0x3c
 *     _stackAllocated +0x3d
 *
 * Anything after those is private to this implementation.
 */
@interface NSInvocation : NSObject <NSCoding> {
    void *_frame;                        /* +0x08 */
    void *_retdata;                      /* +0x10 */
    NSMethodSignature *_signature;       /* +0x18 */
    id _container;                       /* +0x20 */
    void *_replacedByPointerBacking;     /* +0x28 */
    unsigned long long _pac_signature;   /* +0x30 */
    unsigned _magic;                     /* +0x38 */
    unsigned char _retainedArgs;         /* +0x3c */
    unsigned char _stackAllocated;       /* +0x3d */

    NSUInteger _returnSize;
    NSUInteger _bufferSize;
    BOOL _retainArguments;
}

+ (NSInvocation *)invocationWithMethodSignature:(NSMethodSignature *)signature;
+ (NSInvocation *)invocationWithMethodSignature:(NSMethodSignature *)signature arguments:(void *)arguments;

- (NSMethodSignature *)methodSignature;

- (void)getReturnValue:(void *)pointerToValue;
- (void)setReturnValue:(void *)pointerToValue;

- (void)getArgument:(void *)pointerToValue atIndex:(NSInteger)index;
- (void)setArgument:(void *)pointerToValue atIndex:(NSInteger)index;

- (void)retainArguments;
- (BOOL)argumentsRetained;

- (SEL)selector;
- (void)setSelector:(SEL)selector;

- (id)target;
- (void)setTarget:(id)target;

- (void)invoke;
- (void)invokeWithTarget:(id)target;

/* Private, CoreFoundation-compatible entry points. */
+ (NSInvocation *)_invocationWithMethodSignature:(NSMethodSignature *)signature
                                           frame:(void *)frame;
- (id)_initWithMethodSignature:(NSMethodSignature *)signature
                         frame:(void *)frame
                        buffer:(void *)buffer
                          size:(NSUInteger)size;

@end