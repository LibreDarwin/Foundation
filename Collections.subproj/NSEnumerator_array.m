/*
 * Copyright (c) 2006-2007 Christopher J. W. Lloyd
 *
 * Ported into the xnuports Foundation from the ravynOS Frameworks/Foundation
 * tree (itself upstream Cocotron), which carries this license:
 *
 * Permission is hereby granted, free of charge, to any person obtaining a copy
 * of this software and associated documentation files (the "Software"), to deal
 * in the Software without restriction, including without limitation the rights
 * to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
 * copies of the Software, and to permit persons to whom the Software is
 * furnished to do so, subject to the following conditions:
 *
 * The above copyright notice and this permission notice shall be included in
 * all copies or substantial portions of the Software.
 *
 * THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
 * IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
 * FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
 * AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
 * LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
 * OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
 * SOFTWARE.
 */

#import "NSEnumerator_array.h"
#import <Foundation/NSArray.h>

/* ARC-adapted from ravynOS's NSArray/NSEnumerator_array.m and
 * NSArray/NSEnumerator_arrayReverse.m: the originals went through
 * NSAllocateObject and held the array with a manual retain.  Under ARC the
 * ivar owns the array directly, and the reverse enumerator uses an unsigned
 * index with an explicit emptiness check rather than a signed underflow. */

@implementation NSEnumerator_array

- (instancetype)initWithArray:(NSArray *)array {
    if ((self = [super init]) != nil) {
        _index = 0;
        _array = array;
    }
    return self;
}

- (nullable id)nextObject {
    if (_index >= [_array count]) {
        return nil;
    }
    return [_array objectAtIndex:_index++];
}

@end

@implementation NSEnumerator_arrayReverse

- (instancetype)initWithArray:(NSArray *)array {
    if ((self = [super init]) != nil) {
        _index = [array count];
        _array = array;
    }
    return self;
}

- (nullable id)nextObject {
    if (_index == 0) {
        return nil;
    }
    return [_array objectAtIndex:--_index];
}

@end