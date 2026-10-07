/*
 * Copyright (C) 2026, LibreDarwin.
 *
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */

#import <Foundation/NSMethodSignature.h>
#import <Foundation/NSString.h>
#import <Foundation/NSException.h>
#import <Foundation/NSObjCRuntime.h>
#import <Foundation/NSZone.h>
#include <string.h>
#include <stdlib.h>
#include <stddef.h>

/*
 * AArch64 call-frame model, matching what CoreFoundation's
 * ___forwarding___ trampoline lays out in its register save frame:
 *
 *     x0..x8  (self, _cmd, then GP scalars/pointers)   at 0x00 + 8*k
 *     q0..q7  (float/double)                           at 0x50 + 16*k
 *     stack arguments                                  at 0xe0 onward
 *
 * frameLength is that layout size rounded up to 8 bytes.  CoreFoundation
 * uses it to size the buffer it hands to
 * -_initWithMethodSignature:frame:buffer:size:, and our own -invoke:
 * consumes the same offsets, so the two agree.
 */
#define NSFRAME_GP_BASE  0x00
#define NSFRAME_FP_BASE  0x50
#define NSFRAME_STACK    0xe0

static NSUInteger NSStringHashZeroTerminatedASCII(const char *string) {
    NSUInteger hash = 0;
    while (*string)
        hash = hash * 31 + (unsigned char)*string++;
    return hash;
}

static const char *MSSSkipQualifiers(const char *type) {
    while (*type == 'r' || *type == 'n' || *type == 'N' || *type == 'o' ||
           *type == 'O' || *type == 'R' || *type == 'V')
        type++;
    return type;
}

static BOOL MSSIsFloatType(const char *type) {
    const char *t = MSSSkipQualifiers(type);
    return (*t == 'f' || *t == 'd' || *t == 'D') ? YES : NO;
}

static unsigned short MSSFlagsForType(const char *type, NSUInteger size) {
    const char *t = MSSSkipQualifiers(type);

    if (t[0] == 'f' || t[0] == 'd' || t[0] == 'D')
        return 0x0200;
    if (t[0] == '@')
        return 0x2000;
    if (t[0] == '{' || t[0] == '(') {
        unsigned short flags = 0x0400;
        if (size > 16)
            flags |= 0x0080; /* indirect (memory) return */
        return flags;
    }
    if (t[0] == '[')
        return 0x0400;
    return 0x0100;
}

static NSUInteger MSSAlignUp(NSUInteger value, NSUInteger align) {
    if (align < 1)
        align = 1;
    return (value + align - 1) & ~(align - 1);
}

@implementation NSMethodSignature

-initWithTypes:(const char *)typesCString {
    size_t length = strlen(typesCString);

    _typeString = NSZoneMalloc(NULL, length + 1);
    strcpy(_typeString, typesCString);

    /* Split the encoding into the return type followed by each argument
     * type, recording each type's size and natural alignment. */
    NSUInteger maxTypes = length + 1;
    const char **types = NSZoneMalloc(NULL, sizeof(char *) * maxTypes);
    NSUInteger *sizes = NSZoneMalloc(NULL, sizeof(NSUInteger) * maxTypes);
    NSUInteger *aligns = NSZoneMalloc(NULL, sizeof(NSUInteger) * maxTypes);
    NSUInteger count = 0;

    const char *cursor = _typeString;
    const char *last = cursor;
    const char *next;
    NSUInteger size, align;

    while ((next = NSGetSizeAndAlignment(cursor, &size, &align)) != last &&
           next != cursor) {
        NSUInteger typeLength = (NSUInteger)(next - cursor);
        char *copy = NSZoneMalloc(NULL, typeLength + 1);

        memcpy(copy, cursor, typeLength);
        copy[typeLength] = '\0';

        types[count] = copy;
        sizes[count] = size;
        aligns[count] = align ? align : 1;
        count++;

        last = next;
        cursor = next;
        while (*cursor >= '0' && *cursor <= '9')
            cursor++;
        if (*cursor == '\0')
            break;
        last = cursor;
    }

    if (count == 0) {
        NSZoneFree(NULL, types);
        NSZoneFree(NULL, sizes);
        NSZoneFree(NULL, aligns);
        [NSException raise:NSInvalidArgumentException
                    format:@"+[NSMethodSignature signatureWithObjCTypes:]: invalid types \"%s\"",
                           typesCString];
        return nil;
    }

    NSUInteger nArgs = count - 1;

    /* Lay out the descriptor followed by one ArgInfo per type. */
    NSUInteger infoOffsets[maxTypes];
    NSUInteger blockSize = sizeof(NSMethodFrameDescriptor);
    NSUInteger i;

    for (i = 0; i < count; i++) {
        infoOffsets[i] = blockSize;
        NSUInteger infoSize = offsetof(NSMethodFrameArgInfo, type) + strlen(types[i]) + 1;
        blockSize = MSSAlignUp(blockSize + infoSize, 8);
    }

    char *block = NSZoneCalloc(NULL, blockSize, 1);
    NSMethodFrameDescriptor *desc = (NSMethodFrameDescriptor *)block;

    desc->numberOfArguments = (unsigned)nArgs;

    /* Return value info: GP return lives at offset 0, FP at 0x50. */
    NSMethodFrameArgInfo *retInfo = (NSMethodFrameArgInfo *)(block + infoOffsets[0]);
    retInfo->subInfo = NULL;
    retInfo->forward = (count > 1) ? (NSMethodFrameArgInfo *)(block + infoOffsets[1]) : NULL;
    retInfo->size = (unsigned)sizes[0];
    retInfo->offset = MSSIsFloatType(types[0]) ? NSFRAME_FP_BASE : 0;
    retInfo->flags = MSSFlagsForType(types[0], sizes[0]);
    strcpy(retInfo->type, types[0]);
    desc->returnInfo = retInfo;

    /* Argument infos: GP registers, then FP registers, then the stack. */
    NSUInteger gp = 0, fp = 0, stack = NSFRAME_STACK;

    for (i = 0; i < nArgs; i++) {
        NSUInteger typeIndex = i + 1;
        NSMethodFrameArgInfo *ai = (NSMethodFrameArgInfo *)(block + infoOffsets[typeIndex]);

        ai->subInfo = NULL;
        ai->forward = (i + 1 < nArgs)
            ? (NSMethodFrameArgInfo *)(block + infoOffsets[typeIndex + 1]) : NULL;
        ai->size = (unsigned)sizes[typeIndex];

        if (MSSIsFloatType(types[typeIndex])) {
            if (fp < 8) {
                ai->offset = (unsigned)(NSFRAME_FP_BASE + 16 * fp);
                fp++;
            } else {
                stack = MSSAlignUp(stack, aligns[typeIndex]);
                ai->offset = (unsigned)stack;
                stack += sizes[typeIndex];
            }
        } else {
            if (gp < 8) {
                ai->offset = (unsigned)(NSFRAME_GP_BASE + 8 * gp);
                gp++;
            } else {
                stack = MSSAlignUp(stack, aligns[typeIndex]);
                ai->offset = (unsigned)stack;
                stack += sizes[typeIndex];
            }
        }

        ai->flags = MSSFlagsForType(types[typeIndex], sizes[typeIndex]);
        strcpy(ai->type, types[typeIndex]);

        if (i == 0)
            desc->argumentInfo = ai;
    }

    desc->frameLength = (unsigned)MSSAlignUp(stack, 8);
    _frameDescriptor = desc;

    for (i = 0; i < count; i++)
        NSZoneFree(NULL, (void *)types[i]);
    NSZoneFree(NULL, types);
    NSZoneFree(NULL, sizes);
    NSZoneFree(NULL, aligns);

    return self;
}

-(void)dealloc {
    if (_frameDescriptor != NULL) {
        NSZoneFree(NULL, _frameDescriptor);
        _frameDescriptor = NULL;
    }

    if (_typeString != NULL) {
        NSZoneFree(NULL, _typeString);
        _typeString = NULL;
    }

    [super dealloc];
}

+(NSMethodSignature *)signatureWithObjCTypes:(const char *)typesCString {
    return [[[NSMethodSignature allocWithZone:NULL] initWithTypes:typesCString] autorelease];
}

-(NSString *)description {
    return [NSString stringWithFormat:@"<NSMethodSignature: -(%s)%s>",
                                      [self methodReturnType], _typeString];
}

-(NSUInteger)hash {
    return NSStringHashZeroTerminatedASCII(_typeString);
}

-(BOOL)isEqual:otherObject {
    if (self == otherObject)
        return YES;

    if ([otherObject isKindOfClass:[NSMethodSignature class]])
        return strcmp(_typeString, ((NSMethodSignature *)otherObject)->_typeString) == 0;

    return NO;
}

-(BOOL)isOneway {
    return (_frameDescriptor->returnInfo->type[0] == 'V') ? YES : NO;
}

-(NSUInteger)frameLength {
    return _frameDescriptor->frameLength;
}

-(NSUInteger)methodReturnLength {
    return _frameDescriptor->returnInfo->size;
}

-(const char *)methodReturnType {
    return _frameDescriptor->returnInfo->type;
}

-(NSUInteger)numberOfArguments {
    return _frameDescriptor->numberOfArguments;
}

-(const char *)getArgumentTypeAtIndex:(NSUInteger)index {
    if (index >= _frameDescriptor->numberOfArguments) {
        [NSException raise:NSInvalidArgumentException
                    format:@"index (%lu) is beyond number of arguments (%lu)",
                           (unsigned long)index,
                           (unsigned long)_frameDescriptor->numberOfArguments];
        return NULL;
    }

    return [self _argInfo:(NSInteger)index]->type;
}

-(NSMethodFrameDescriptor *)_frameDescriptor {
    return _frameDescriptor;
}

-(NSMethodFrameArgInfo *)_argInfo:(NSInteger)index {
    if (index < 0)
        return _frameDescriptor->returnInfo;

    NSMethodFrameArgInfo *info = _frameDescriptor->argumentInfo;
    NSInteger i;

    for (i = 0; i < index; i++)
        info = info->forward;

    return info;
}

@end