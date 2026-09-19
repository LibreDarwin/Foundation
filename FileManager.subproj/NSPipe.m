/*
 * Copyright (C) 2026, PureDarwin Project.
 *
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 *
 * The endpoint design follows Cocotron/ravynOS NSPipe by Christopher J. W.
 * Lloyd, used under its MIT license, and uses this tree's NSFileHandle.
 */

#import <Foundation/NSPipe.h>
#include <unistd.h>

@implementation NSPipe

+ (instancetype)pipe {
    NSPipe *pipe = [[self alloc] init];
#if __has_feature(objc_arc)
    return pipe;
#else
    return [pipe autorelease];
#endif
}

- (instancetype)init {
    self = [super init];
    if (self != nil) {
        int descriptors[2];
        if (pipe(descriptors) != 0) {
#if !__has_feature(objc_arc)
            [self release];
#endif
            return nil;
        }
        _fileHandleForReading = [[NSFileHandle alloc] initWithFileDescriptor:descriptors[0]
                                                               closeOnDealloc:YES];
        _fileHandleForWriting = [[NSFileHandle alloc] initWithFileDescriptor:descriptors[1]
                                                                closeOnDealloc:YES];
    }
    return self;
}

- (NSFileHandle *)fileHandleForReading { return _fileHandleForReading; }
- (NSFileHandle *)fileHandleForWriting { return _fileHandleForWriting; }

- (void)dealloc {
#if !__has_feature(objc_arc)
    [_fileHandleForReading release];
    [_fileHandleForWriting release];
    [super dealloc];
#endif
}

@end
