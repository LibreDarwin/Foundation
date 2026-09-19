/*
 * Copyright (c) 2002-2007 Christopher J. W. Lloyd
 *
 * Permission is hereby granted, free of charge, to any person obtaining a copy
 * of this software and associated documentation files (the "Software"), to deal
 * in the Software without restriction, including without limitation the rights
 * to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
 * copies of the Software, and to permit persons to whom the Software is
 * furnished to do so, subject to the following conditions:
 *
 * The above copyright notice and this permission notice shall be included in all
 * copies or substantial portions of the Software.
 *
 * THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
 * IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
 * FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
 * AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
 * LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
 * OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
 * SOFTWARE.
 */

#import <Foundation/NSNotification.h>

// Adapted for this tree (ARC, no CoreFoundation, no NSZone guarantees):
// the NSNotification_concrete subclass and its NSAllocateObject/zone backing
// are collapsed into the base class; NSCoding support is dropped (no NSCoder
// in this tree); +notificationWithName:object: is used by the center instead
// of the concrete allocator.

@implementation NSNotification

+ (NSNotification *)notificationWithName:(NSString *)name object:object {
    return [[NSNotification alloc] initWithName:name object:object userInfo:nil];
}

+ (NSNotification *)notificationWithName:(NSString *)name object:object userInfo:(NSDictionary *)userInfo {
    return [[NSNotification alloc] initWithName:name object:object userInfo:userInfo];
}

- initWithName:(NSString *)name object:object userInfo:(NSDictionary *)userInfo {
    _name = name;
    _object = object;
    _userInfo = userInfo;
    return self;
}

- (NSString *)name {
    return _name;
}

- (id)object {
    return _object;
}

- (NSDictionary *)userInfo {
    return _userInfo;
}

@end