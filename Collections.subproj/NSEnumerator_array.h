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

#ifndef NSEnumerator_array_h
#define NSEnumerator_array_h

#import <Foundation/NSEnumerator.h>

/* Concrete, and rare enough to stay private: ravynOS splits these into
 * NSEnumerator_array and NSEnumerator_arrayReverse; both are kept here so the
 * array source alone describes the pair. */

@interface NSEnumerator_array : NSEnumerator {
    NSUInteger _index;
    NSArray *_array;
}

- (instancetype)initWithArray:(NSArray *)array;

@end

@interface NSEnumerator_arrayReverse : NSEnumerator {
    NSUInteger _index;
    NSArray *_array;
}

- (instancetype)initWithArray:(NSArray *)array;

@end

#endif /* NSEnumerator_array_h */