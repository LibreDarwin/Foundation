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

#import <Foundation/NSNotificationCenter.h>
#import <Foundation/NSArray.h>
#import <Foundation/NSException.h>
#import <Foundation/NSString.h>
#import <objc/message.h>

// Adapted for this tree (ARC, no CoreFoundation):
// upstream's _nameToRegistry (name -> NSObjectToObservers, backed by NSMapTable)
// is replaced with a single flat _observers array of registration records that
// carry their own name/object filters; NSMapTable does not compile under ARC
// in this tree. @synchronized(self) is retained for all mutation and dispatch.
//
// Added for this tree: addObserverForName:object:queue:usingBlock:. queue is
// required to be nil (there is no NSOperationQueue here yet) and raises
// NSInvalidArgumentException otherwise. The returned token is the registration
// record; observers are unretained (Darwin semantics - unregister before the
// observer goes away).

// One registration record. Selector registrations message _observer;
// block registrations use the record itself as the token (_observer == self)
// and invoke _block.
@interface NSNotificationObserver : NSObject {
    __unsafe_unretained id _observer;
    SEL _selector;
    NSString *_name;
    id _object;
    void (^_block)(NSNotification *note);
    BOOL _removed;
}

- initWithObserver:observer selector:(SEL)selector name:(NSString *)name object:object;
- initWithBlock:(void (^)(NSNotification *note))block name:(NSString *)name object:object;

- (id)observer;
- (NSString *)name;
- (id)object;
- (BOOL)isRemoved;
- (void)markRemoved;
- (BOOL)matchesName:(NSString *)name object:object;
- (void)postNotification:(NSNotification *)notification;

@end

@implementation NSNotificationObserver

- initWithObserver:observer selector:(SEL)selector name:(NSString *)name object:object {
    if ((self = [super init]) != nil) {
        _observer = observer;
        _selector = selector;
        _name = name;
        _object = object;
    }
    return self;
}

- initWithBlock:(void (^)(NSNotification *note))block name:(NSString *)name object:object {
    if ((self = [super init]) != nil) {
        _observer = self; // token identity; ivar is __unsafe_unretained, so no self-retain
        _selector = NULL;
        _name = name;
        _object = object;
        _block = block; // strong block storage, copied on assignment
    }
    return self;
}

- (id)observer {
    return _observer;
}

- (NSString *)name {
    return _name;
}

- (id)object {
    return _object;
}

- (BOOL)isRemoved {
    return _removed;
}

- (void)markRemoved {
    _removed = YES;
}

- (BOOL)matchesName:(NSString *)name object:object {
    if (_name != nil && ![_name isEqual:name])
        return NO;
    if (_object != nil && _object != object)
        return NO;
    return YES;
}

- (void)postNotification:(NSNotification *)notification {
    if (_selector != NULL) {
        void (*trampoline)(id, SEL, id) = (void (*)(id, SEL, id))objc_msgSend;
        trampoline(_observer, _selector, notification);
    } else if (_block != NULL) {
        _block(notification);
    }
}

@end

@implementation NSNotificationCenter

static NSNotificationCenter *_defaultCenter = nil;

+ (NSNotificationCenter *)defaultCenter {
    @synchronized(self) {
        if (_defaultCenter == nil)
            _defaultCenter = [NSNotificationCenter new];
    }
    return _defaultCenter;
}

- init {
    if ((self = [super init]) != nil) {
        _observers = [NSMutableArray new];
    }
    return self;
}

- (void)addObserver:observer selector:(SEL)selector name:(NSString *)name object:object {
    @synchronized(self) {
        NSNotificationObserver *record = [[NSNotificationObserver alloc] initWithObserver:observer selector:selector name:name object:object];
        [_observers addObject:record];
    }
}

- (id <NSObject>)addObserverForName:(NSString *)name object:object queue:(NSOperationQueue *)queue usingBlock:(void (^)(NSNotification *note))block {
    // Validate before taking the lock: the exception unwinds without a held
    // @synchronized block.
    if (queue != nil) {
        [NSException raise:NSInvalidArgumentException format:@"addObserverForName:object:queue:usingBlock: queue must be nil; this Foundation has no NSOperationQueue"];
    }
    @synchronized(self) {
        NSNotificationObserver *record = [[NSNotificationObserver alloc] initWithBlock:block name:name object:object];
        [_observers addObject:record];
        return record;
    }
}

- (void)removeObserver:observer {
    [self removeObserver:observer name:nil object:nil];
}

- (void)removeObserver:observer name:(NSString *)name object:object {
    @synchronized(self) {
        NSInteger i = [_observers count];
        while (--i >= 0) {
            NSNotificationObserver *record = [_observers objectAtIndex:i];
            if ([record observer] != observer)
                continue;
            if (name != nil && ![[record name] isEqual:name])
                continue;
            if (object != nil && [record object] != object)
                continue;
            [record markRemoved];
            [_observers removeObjectAtIndex:i];
        }
    }
}

- (void)postNotification:(NSNotification *)notification {
    @autoreleasepool {
        @synchronized(self) {
            NSUInteger count = [_observers count];
            NSMutableArray *snapshot = [NSMutableArray arrayWithCapacity:count];
            for (NSUInteger i = 0; i < count; i++)
                [snapshot addObject:[_observers objectAtIndex:i]];

            for (NSUInteger i = 0; i < count; i++) {
                NSNotificationObserver *record = [snapshot objectAtIndex:i];
                if ([record isRemoved])
                    continue;
                if ([record matchesName:[notification name] object:[notification object]])
                    [record postNotification:notification];
            }
        }
    }
}

- (void)postNotificationName:(NSString *)name object:object {
    [self postNotification:[NSNotification notificationWithName:name object:object]];
}

- (void)postNotificationName:(NSString *)name object:object userInfo:(NSDictionary *)userInfo {
    [self postNotification:[NSNotification notificationWithName:name object:object userInfo:userInfo]];
}

@end