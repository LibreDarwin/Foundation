/*
 * Copyright (C) 2026, LibreDarwin.
 *
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */

#import <Foundation/NSObject.h>

@class NSString, NSMutableArray;

/*
 * Runtime frame descriptors, ABI-compatible with the ones CoreFoundation
 * builds for its private forwarding machinery.  The offsets baked into
 * these structs (and into the ivar layout of NSMethodSignature /
 * NSInvocation below) match the layout observed on arm64 macOS, because
 * CoreFoundation reads the descriptor and instance fields directly by
 * offset.
 */
typedef struct NSMethodFrameArgInfo {
    struct NSMethodFrameArgInfo *subInfo; /* +0x00 */
    struct NSMethodFrameArgInfo *forward; /* +0x08 */
    unsigned size;                        /* +0x10 */
    unsigned field14;                     /* +0x14 */
    unsigned field18;                     /* +0x18 */
    unsigned offset;                      /* +0x1c */
    unsigned char field20;                /* +0x20 */
    unsigned char field21;                /* +0x21 */
    unsigned short flags;                 /* +0x22 */
    unsigned char field24;                /* +0x24 */
    char type[1];                         /* +0x25 */
} NSMethodFrameArgInfo;

typedef struct NSMethodFrameDescriptor {
    NSMethodFrameArgInfo *returnInfo;      /* +0x00 */
    NSMethodFrameArgInfo *argumentInfo;    /* +0x08 */
    unsigned numberOfArguments;            /* +0x10 */
    unsigned frameLength;                  /* +0x14 */
} NSMethodFrameDescriptor;

@interface NSMethodSignature : NSObject {
    NSMethodFrameDescriptor *_frameDescriptor; /* +0x08 */
    char *_typeString;                         /* +0x10 */
    unsigned long _flags;                      /* +0x18 */
}

+ (NSMethodSignature *)signatureWithObjCTypes:(const char *)types;

- (BOOL)isOneway;
- (NSUInteger)frameLength;
- (NSUInteger)methodReturnLength;

- (const char *)methodReturnType;

- (NSUInteger)numberOfArguments;

- (const char *)getArgumentTypeAtIndex:(NSUInteger)index;

/* Private, CoreFoundation-compatible accessors. */
- (NSMethodFrameDescriptor *)_frameDescriptor;
- (NSMethodFrameArgInfo *)_argInfo:(NSInteger)index;

@end
