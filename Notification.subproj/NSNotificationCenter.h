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

@class NSMutableArray;
@class NSOperationQueue;

@interface NSNotificationCenter : NSObject {
    NSMutableArray *_observers;
}

+ (NSNotificationCenter *)defaultCenter;

- (void)addObserver:observer selector:(SEL)selector name:(NSString *)name object:object;
- (id <NSObject>)addObserverForName:(NSString *)name object:object queue:(NSOperationQueue *)queue usingBlock:(void (^)(NSNotification *note))block;

- (void)removeObserver:observer;
- (void)removeObserver:observer name:(NSString *)name object:object;

- (void)postNotification:(NSNotification *)notification;
- (void)postNotificationName:(NSString *)name object:object;
- (void)postNotificationName:(NSString *)name object:object userInfo:(NSDictionary *)userInfo;

@end