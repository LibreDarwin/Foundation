/*
 * Copyright (C) 2026, LibreDarwin.
 *
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */
#import <Foundation/NSInvocation.h>
#import <Foundation/NSMethodSignature.h>
#import <Foundation/NSCoder.h>
#import <Foundation/NSString.h>
#import <Foundation/NSException.h>
#import <Foundation/NSZone.h>
#import <Foundation/NSObjCRuntime.h>

#include <string.h>
#include <stdlib.h>
#include <objc/runtime.h>

/*
 * AArch64 register/stack call shim.  NSInvocation cannot use the
 * GNU-runtime objc_msgSendv (not present in Apple's libobjc), and
 * __builtin_apply/__builtin_apply_args are unavailable on arm64 clang.
 * So we marshal the arguments ourselves and make the call from a small
 * assembly trampoline.
 *
 *   void NSInvocationPerformCall(void *fn,
 *                                const uint64_t gp[8],   // x0..x7
 *                                const double   fp[8],   // d0..d7
 *                                const void    *stack,   // spilled args
 *                                size_t         stackSize,
 *                                void          *result); // [0]=x0 [8]=d0
 */
extern void NSInvocationPerformCall(void *fn, const uint64_t gp[8],
                                    const double fp[8], const void *stack,
                                    size_t stackSize, void *result);

__asm__(
".text\n"
".p2align 2\n"
".globl _NSInvocationPerformCall\n"
"_NSInvocationPerformCall:\n"
"    stp x29, x30, [sp, #-16]!\n"
"    mov x29, sp\n"
"    stp x19, x20, [sp, #-16]!\n"
"    stp x21, x22, [sp, #-16]!\n"
"    mov x19, x0\n"          // fn
"    mov x20, x5\n"          // result
"    mov x21, x1\n"          // gp array
"    mov x22, x2\n"          // fp array
"    add x9, x4, #15\n"      // round stack size up to 16
"    and x9, x9, #-16\n"
"    sub sp, sp, x9\n"
"    mov x10, sp\n"          // copy spilled args onto the stack
"0:  cbz x4, 1f\n"
"    ldrb w11, [x3], #1\n"
"    strb w11, [x10], #1\n"
"    subs x4, x4, #1\n"
"    b 0b\n"
"1:\n"
"    ldp d0, d1, [x22, #0]\n"
"    ldp d2, d3, [x22, #16]\n"
"    ldp d4, d5, [x22, #32]\n"
"    ldp d6, d7, [x22, #48]\n"
"    ldp x9,  x10, [x21, #0]\n"
"    ldp x11, x12, [x21, #16]\n"
"    ldp x13, x14, [x21, #32]\n"
"    ldp x15, x16, [x21, #48]\n"
"    mov x0, x9\n"
"    mov x1, x10\n"
"    mov x2, x11\n"
"    mov x3, x12\n"
"    mov x4, x13\n"
"    mov x5, x14\n"
"    mov x6, x15\n"
"    mov x7, x16\n"
"    blr x19\n"
"    str x0, [x20, #0]\n"    // integer / pointer return
"    str d0, [x20, #8]\n"    // floating point return
"    mov sp, x29\n"
"    sub sp, sp, #32\n"
"    ldp x21, x22, [sp], #16\n"
"    ldp x19, x20, [sp], #16\n"
"    ldp x29, x30, [sp], #16\n"
"    ret\n"
);

/* Frame layout constants, mirroring NSMethodSignature.m. */
#define NSFRAME_GP_LIMIT 0x40
#define NSFRAME_FP_BASE  0x50
#define NSFRAME_FP_LIMIT 0xd0
#define NSFRAME_STACK    0xe0
#define NSINVOCATION_BUFFER_HEADROOM 0x140
#define NSINVOCATION_MAGIC 0x29332568u

static uint64_t NSPACGA(uint64_t modifier, uint64_t data) {
    uint64_t result;

    __asm__ volatile("pacga %0, %1, %2" : "=r"(result) : "r"(modifier), "r"(data));

    return result;
}

@interface NSInvocation (LibreDarwinPrivate)
- (uint64_t)_ns_computeInvocationChecksum;
@end

/*
 * CoreFoundation derives a PAC checksum over a handful of invocation fields
 * and re-derives it before dispatching a forwarded message.  We reproduce the
 * same chain so our value stays consistent with its verification.
 */
@implementation NSInvocation (LibreDarwinPrivate)

- (uint64_t)_ns_computeInvocationChecksum {
    uint64_t hash = NSPACGA((uint64_t)[_signature numberOfArguments], 0x1f99ULL);

    hash = NSPACGA(_magic, hash);
    hash = NSPACGA((uint64_t)(uintptr_t)_signature, hash);
    hash = NSPACGA((uint64_t)(uintptr_t)object_getClass(self), hash);
    hash = NSPACGA((uint64_t)[_signature frameLength], hash);

    if ([_signature frameLength] != 0) {
        const uint64_t *frame = (const uint64_t *)_frame;
        unsigned i;

        for (i = 0; i < 8; i++)
            hash = NSPACGA(frame[i], hash);
    }

    hash = NSPACGA((uint64_t)(uintptr_t)self, hash);

    return hash;
}

@end

@implementation NSInvocation

+ (NSInvocation *)invocationWithMethodSignature:(NSMethodSignature *)signature {
    return [[[self allocWithZone:NULL] initWithMethodSignature:signature] autorelease];
}

+ (NSInvocation *)invocationWithMethodSignature:(NSMethodSignature *)signature
                                      arguments:(void *)arguments {
    return [[[self allocWithZone:NULL] initWithMethodSignature:signature
                                                      arguments:arguments] autorelease];
}

- (id)initWithMethodSignature:(NSMethodSignature *)signature {
    if (signature == nil) {
        [NSException raise:NSInvalidArgumentException
                    format:@"nil signature in NSInvocation creation"];
        return nil;
    }

    NSUInteger size = [signature frameLength] + NSINVOCATION_BUFFER_HEADROOM;

    _signature = [signature retain];
    _container = nil;
    _retdata = NSZoneCalloc(NULL, size, 1);
    _frame = (uint8_t *)_retdata + NSINVOCATION_BUFFER_HEADROOM;
    _magic = NSINVOCATION_MAGIC;
    _retainedArgs = 0;
    _stackAllocated = 0;
    _returnSize = [signature methodReturnLength];
    _bufferSize = size;
    _retainArguments = NO;
    _pac_signature = [self _ns_computeInvocationChecksum];

    return self;
}

- (id)initWithMethodSignature:(NSMethodSignature *)signature arguments:(void *)arguments {
    NSUInteger frameLength;

    if ([self initWithMethodSignature:signature] == nil)
        return nil;

    frameLength = [signature frameLength];
    if (arguments != NULL && frameLength > 0)
        memcpy(_frame, arguments, frameLength);

    return self;
}

- (id)initWithCoder:(NSCoder *)coder {
    void  *buffer = NULL;
    const char *type;
    NSInteger   i, count;

    _signature = [[coder decodeObject] retain];

    NSUInteger size = [_signature frameLength] + NSINVOCATION_BUFFER_HEADROOM;
    _retdata = NSZoneCalloc(NULL, size, 1);
    _frame = (uint8_t *)_retdata + NSINVOCATION_BUFFER_HEADROOM;
    _container = nil;
    _magic = NSINVOCATION_MAGIC;
    _retainedArgs = 0;
    _stackAllocated = 0;
    _returnSize = [_signature methodReturnLength];
    _bufferSize = size;
    _retainArguments = NO;

    if ([_signature methodReturnLength] > 0) {
        NSUInteger retSize, retAlign;

        type = [_signature methodReturnType];
        NSGetSizeAndAlignment(type, &retSize, &retAlign);
        buffer = NSZoneMalloc(NULL, retSize);
        [coder decodeValueOfObjCType:type at:buffer];
        [self setReturnValue:buffer];
        NSZoneFree(NULL, buffer);
        buffer = NULL;
    }

    count = [_signature numberOfArguments];
    for (i = 0; i < count; i++) {
        NSUInteger argSize, argAlign;

        type = [_signature getArgumentTypeAtIndex:i];
        NSGetSizeAndAlignment(type, &argSize, &argAlign);
        buffer = NSZoneMalloc(NULL, argSize);
        [coder decodeValueOfObjCType:type at:buffer];
        [self setArgument:buffer atIndex:i];
        NSZoneFree(NULL, buffer);
        buffer = NULL;
    }

    _pac_signature = [self _ns_computeInvocationChecksum];

    return self;
}

- (void)encodeWithCoder:(NSCoder *)coder {
    void  *buffer = NULL;
    const char *type;
    NSInteger   i, count;

    [coder encodeObject:_signature];

    if ([_signature methodReturnLength] > 0) {
        NSUInteger retSize, retAlign;

        type = [_signature methodReturnType];
        NSGetSizeAndAlignment(type, &retSize, &retAlign);
        buffer = NSZoneMalloc(NULL, retSize);
        [self getReturnValue:buffer];
        [coder encodeValueOfObjCType:type at:buffer];
        NSZoneFree(NULL, buffer);
        buffer = NULL;
    }

    count = [_signature numberOfArguments];
    for (i = 0; i < count; i++) {
        NSUInteger argSize, argAlign;

        type = [_signature getArgumentTypeAtIndex:i];
        NSGetSizeAndAlignment(type, &argSize, &argAlign);
        buffer = NSZoneMalloc(NULL, argSize);
        [self getArgument:buffer atIndex:i];
        [coder encodeValueOfObjCType:type at:buffer];
        NSZoneFree(NULL, buffer);
        buffer = NULL;
    }
}

- (void)dealloc {
    if (_retainArguments) {
        NSInteger i, count = [_signature numberOfArguments];

        for (i = 0; i < count; ++i) {
            const char *type = [_signature getArgumentTypeAtIndex:i];

            if (type[0] == '@') {
                id object;

                [self getArgument:&object atIndex:i];
                [object release];
            }
        }
    }

    if (!_stackAllocated && _retdata != NULL)
        NSZoneFree(NULL, _retdata);

    [_signature release];
    [super dealloc];
}

- (NSMethodSignature *)methodSignature {
    return _signature;
}

- (void)getReturnValue:(void *)pointerToValue {
    [self getArgument:pointerToValue atIndex:-1];
}

- (void)setReturnValue:(void *)pointerToValue {
    [self setArgument:pointerToValue atIndex:-1];
}

- (void)getArgument:(void *)pointerToValue atIndex:(NSInteger)index {
    NSMethodFrameArgInfo *info = [_signature _argInfo:index];
    void *base = (index < 0) ? _retdata : _frame;

    memcpy(pointerToValue, (uint8_t *)base + info->offset, info->size);
}

- (void)setArgument:(void *)pointerToValue atIndex:(NSInteger)index {
    NSMethodFrameArgInfo *info = [_signature _argInfo:index];
    void *base = (index < 0) ? _retdata : _frame;

    memcpy((uint8_t *)base + info->offset, pointerToValue, info->size);
}

- (void)retainArguments {
    NSInteger i, count;

    if (_retainArguments)
        return;

    _retainArguments = YES;
    _retainedArgs = 1;

    count = [_signature numberOfArguments];
    for (i = 0; i < count; i++) {
        const char *type = [_signature getArgumentTypeAtIndex:i];

        if (type[0] == '@') {
            id object;

            [self getArgument:&object atIndex:i];
            [object retain];
        } else if (type[0] == '*') {
            char *ptr;
            char *copy;

            [self getArgument:&ptr atIndex:i];
            copy = NSZoneMalloc(NULL, strlen(ptr) + 1);
            strcpy(copy, ptr);
            [self setArgument:&copy atIndex:i];
        }
    }
}

- (BOOL)argumentsRetained {
    return _retainArguments;
}

- (SEL)selector {
    SEL selector;

    [self getArgument:&selector atIndex:1];
    return selector;
}

- (void)setSelector:(SEL)selector {
    [self setArgument:&selector atIndex:1];
}

- (id)target {
    id target;

    [self getArgument:&target atIndex:0];
    return target;
}

- (void)setTarget:(id)target {
    [self setArgument:&target atIndex:0];
}

- (void)invoke {
    id target = [self target];
    SEL selector = [self selector];

    NSMethodFrameArgInfo *returnInfo = [_signature _argInfo:-1];

    if (target == nil) {
        if (returnInfo->size > 0)
            memset((uint8_t *)_retdata + returnInfo->offset, 0, returnInfo->size);
        return;
    }

    const char *returnType = [_signature methodReturnType];

    if (returnType[0] == '{' || returnType[0] == '(' || returnType[0] == '[')
        [NSException raise:NSInvalidArgumentException
                    format:@"NSInvocation: struct/union/array return values are not supported"];

    uint64_t gp[8] = {0, 0, 0, 0, 0, 0, 0, 0};
    double   fp[8] = {0, 0, 0, 0, 0, 0, 0, 0};

    NSInteger count = [_signature numberOfArguments];
    NSUInteger frameLength = [_signature frameLength];
    NSUInteger stackBytes = (frameLength > NSFRAME_STACK) ? frameLength - NSFRAME_STACK : 0;
    uint8_t *stack = NSZoneMalloc(NULL, stackBytes ? stackBytes : 1);
    NSInteger i;

    if (stackBytes > 0)
        memcpy(stack, (uint8_t *)_frame + NSFRAME_STACK, stackBytes);

    for (i = 0; i < count; i++) {
        NSMethodFrameArgInfo *info = [_signature _argInfo:i];
        const char *type = info->type;

        if (type[0] == '{' || type[0] == '(' || type[0] == '[') {
            NSZoneFree(NULL, stack);
            [NSException raise:NSInvalidArgumentException
                        format:@"NSInvocation: struct/union/array arguments are not supported"];
        }

        uint8_t *src = (uint8_t *)_frame + info->offset;
        NSUInteger size = info->size > 8 ? 8 : info->size;

        if (info->offset >= NSFRAME_FP_BASE && info->offset < NSFRAME_FP_LIMIT)
            memcpy(&fp[(info->offset - NSFRAME_FP_BASE) / 16], src, size);
        else if (info->offset < NSFRAME_GP_LIMIT)
            memcpy(&gp[info->offset / 8], src, size);
    }

    IMP fn = [target methodForSelector:selector];
    uint64_t result[2] = {0, 0};

    NSInvocationPerformCall((void *)fn, gp, fp, stack, stackBytes, result);

    NSZoneFree(NULL, stack);

    if (returnInfo->offset >= NSFRAME_FP_BASE && returnInfo->offset < NSFRAME_FP_LIMIT)
        memcpy((uint8_t *)_retdata + returnInfo->offset, (uint8_t *)result + 8, returnInfo->size);
    else
        memcpy((uint8_t *)_retdata + returnInfo->offset, (uint8_t *)result, returnInfo->size);
}

- (void)invokeWithTarget:(id)target {
    [self setTarget:target];
    [self invoke];
}

+ (NSInvocation *)_invocationWithMethodSignature:(NSMethodSignature *)signature
                                           frame:(void *)frame {
    if (signature == nil) {
        [NSException raise:NSInvalidArgumentException
                    format:@"nil signature in NSInvocation creation"];
        return nil;
    }

    NSUInteger frameLength = [signature frameLength];
    NSUInteger size = frameLength + NSINVOCATION_BUFFER_HEADROOM;
    NSInvocation *invocation = [self alloc];
    void *buffer = NSZoneCalloc(NULL, size, 1);

    invocation->_signature = [signature retain];
    invocation->_container = nil;
    invocation->_retdata = buffer;
    invocation->_frame = (uint8_t *)buffer + NSINVOCATION_BUFFER_HEADROOM;
    invocation->_magic = NSINVOCATION_MAGIC;
    invocation->_retainedArgs = 0;
    invocation->_stackAllocated = 0;
    invocation->_returnSize = [signature methodReturnLength];
    invocation->_bufferSize = size;
    invocation->_retainArguments = NO;

    if (frame != NULL && frameLength > 0)
        memmove(invocation->_frame, frame, frameLength);

    invocation->_pac_signature = [invocation _ns_computeInvocationChecksum];

    return [invocation autorelease];
}

- (id)_initWithMethodSignature:(NSMethodSignature *)signature
                         frame:(void *)frame
                        buffer:(void *)buffer
                          size:(NSUInteger)size {
    if (signature == nil)
        return nil;

    NSUInteger frameLength = [signature frameLength];

    if (buffer == NULL || size < frameLength + NSINVOCATION_BUFFER_HEADROOM)
        return nil;

    _signature = [signature retain];
    _container = nil;
    _retdata = buffer;
    bzero(buffer, size);
    _frame = (uint8_t *)buffer + NSINVOCATION_BUFFER_HEADROOM;
    _magic = NSINVOCATION_MAGIC;
    _retainedArgs = 0;
    _stackAllocated = 1;
    _returnSize = [signature methodReturnLength];
    _bufferSize = size;
    _retainArguments = NO;

    if (frame != NULL && frameLength > 0)
        memmove(_frame, frame, frameLength);

    _pac_signature = [self _ns_computeInvocationChecksum];

    return self;
}

- (id)description {
    return [NSString stringWithFormat:@"<%@ with signature %@>", [super description], [_signature description]];
}

@end

@implementation NSObject (NSForwarding)

- (NSMethodSignature *)methodSignatureForSelector:(SEL)selector {
    Method method = class_getInstanceMethod(object_getClass(self), selector);

    if (method == NULL)
        return nil;

    return [NSMethodSignature signatureWithObjCTypes:method_getTypeEncoding(method)];
}

- (void)forwardInvocation:(NSInvocation *)invocation {
    [NSException raise:NSInvalidArgumentException
                format:@"*** -[%@ %@]: selector not recognized",
                       NSStringFromClass(object_getClass(self)),
                       NSStringFromSelector([invocation selector])];
}

- (id)forwardingTargetForSelector:(SEL)selector {
    return nil;
}

@end