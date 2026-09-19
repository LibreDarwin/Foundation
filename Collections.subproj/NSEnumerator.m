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

#import <Foundation/NSEnumerator.h>
#import <Foundation/NSArray.h>

@interface NSEnumerator () {
    NSMutableArray *_snapshot;
}
@end

@implementation NSEnumerator

- (nullable id)nextObject {
    return nil;
}

- (NSArray *)allObjects {
    NSMutableArray *array = [NSMutableArray array];
    id object;
    while ((object = [self nextObject]) != nil) {
        [array addObject:object];
    }
    return array;
}

/* Fast enumeration streams the remaining objects to the caller in chunks of up
 * to len.  The first invocation drains the rest of the stream into a snapshot
 * (so enumeration continues from wherever nextObject had already gotten to)
 * and the chunks are served from it.  state->extra[0] stays at zero and is
 * used only as the mutation counter so the runtime never sees a phantom
 * collection change; the chunk cursor lives in state->extra[1].  The snapshot
 * is released once the last chunk is handed out, so re-enumerating the same
 * (now exhausted) enumerator yields nothing.  (The ravynOS original re-scanned
 * the caller's buffer on every invocation, which would loop the caller
 * indefinitely; fixed here.) */
- (NSUInteger)countByEnumeratingWithState:(NSFastEnumerationState *)state
                                   objects:(id __unsafe_unretained _Nullable[_Nonnull])stackbuf
                                     count:(NSUInteger)len
{
    if (state->state == 0) {
        state->state = 1;
        state->mutationsPtr = &state->extra[0];

        if (_snapshot == nil) {
            _snapshot = [NSMutableArray array];
            id object;
            while ((object = [self nextObject]) != nil) {
                [_snapshot addObject:object];
            }
        }
    }

    state->itemsPtr = stackbuf;

    NSUInteger served = state->extra[1];
    NSUInteger total = [_snapshot count];
    NSUInteger filled = 0;

    while (served < total && filled < len) {
        stackbuf[filled++] = [_snapshot objectAtIndex:served++];
    }
    state->extra[1] = served;

    if (filled < len) {
        _snapshot = nil;
    }
    return filled;
}

@end