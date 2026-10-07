/*
 * Copyright (C) 2026, Samuel Zormeister.
 *
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */

#import <Foundation/NSKeyValueCoding.h>
#import <Foundation/NSString.h>
#import <Foundation/NSNumber.h>
#import <Foundation/NSArray.h>
#import <objc/runtime.h>

/* Capitalise the first character of a key, matching the <Key> fragment
 * Apple's accessor search builds ("foo" -> "Foo"). */
static NSString *NSKVCCapitalizedKey(NSString *key) {
    if ([key length] == 0) {
        return key;
    }
    NSString *head = [[key substringToIndex:1] uppercaseString];
    return [head stringByAppendingString:[key substringFromIndex:1]];
}

/* Invoke an accessor and box the result.  The return type is read from the
 * method's type encoding so scalar accessors come back as NSNumber rather
 * than through a mismatched cast. */
static id NSKVCBoxedAccessor(id object, SEL selector) {
    Method method = class_getInstanceMethod(object_getClass(object), selector);
    if (method == NULL) {
        return nil;
    }
    char type[16] = {0};
    method_getReturnType(method, type, sizeof(type));
    IMP imp = [object methodForSelector:selector];
    switch (type[0]) {
        case '@':
        case '#':
            return ((id (*)(id, SEL))imp)(object, selector);
        case 'c': return @(((char (*)(id, SEL))imp)(object, selector));
        case 'i': return @(((int (*)(id, SEL))imp)(object, selector));
        case 's': return @(((short (*)(id, SEL))imp)(object, selector));
        case 'l': return @(((long (*)(id, SEL))imp)(object, selector));
        case 'q': return @(((long long (*)(id, SEL))imp)(object, selector));
        case 'C': return @(((unsigned char (*)(id, SEL))imp)(object, selector));
        case 'I': return @(((unsigned int (*)(id, SEL))imp)(object, selector));
        case 'S': return @(((unsigned short (*)(id, SEL))imp)(object, selector));
        case 'L': return @(((unsigned long (*)(id, SEL))imp)(object, selector));
        case 'Q': return @(((unsigned long long (*)(id, SEL))imp)(object, selector));
        case 'B': return @(((BOOL (*)(id, SEL))imp)(object, selector));
        case 'f': return @(((float (*)(id, SEL))imp)(object, selector));
        case 'd': return @(((double (*)(id, SEL))imp)(object, selector));
        default:
            return nil;
    }
}

/* Read an instance variable by name and box it.  Returns nil when the ivar
 * is absent or holds an unrepresentable C type. */
static id NSKVCBoxedIvar(id object, NSString *ivarName) {
    Ivar ivar = NULL;
    for (Class cls = object_getClass(object); cls != Nil; cls = class_getSuperclass(cls)) {
        ivar = class_getInstanceVariable(cls, [ivarName UTF8String]);
        if (ivar != NULL) {
            break;
        }
    }
    if (ivar == NULL) {
        return nil;
    }
    const char *type = ivar_getTypeEncoding(ivar);
    ptrdiff_t offset = ivar_getOffset(ivar);
    char *base = (char *)(__bridge void *)object;
    switch (type[0]) {
        case '@':
        case '#':
            return object_getIvar(object, ivar);
        case 'c': return @(*(char *)(base + offset));
        case 'i': return @(*(int *)(base + offset));
        case 's': return @(*(short *)(base + offset));
        case 'l': return @(*(long *)(base + offset));
        case 'q': return @(*(long long *)(base + offset));
        case 'C': return @(*(unsigned char *)(base + offset));
        case 'I': return @(*(unsigned int *)(base + offset));
        case 'S': return @(*(unsigned short *)(base + offset));
        case 'L': return @(*(unsigned long *)(base + offset));
        case 'Q': return @(*(unsigned long long *)(base + offset));
        case 'B': return @(*(BOOL *)(base + offset));
        case 'f': return @(*(float *)(base + offset));
        case 'd': return @(*(double *)(base + offset));
        default:
            return nil;
    }
}

@implementation NSObject (NSKeyValueCoding)

- (id)valueForKey:(NSString *)key {
    if ([key isEqualToString:@"self"]) {
        return self;
    }
    if ([key length] == 0) {
        return nil;
    }

    if ([key hasPrefix:@"@"]) {
        if ([key isEqualToString:@"@count"] && [self respondsToSelector:@selector(count)]) {
            return NSKVCBoxedAccessor(self, @selector(count));
        }
        return nil;
    }

    NSString *suffix = NSKVCCapitalizedKey(key);
    NSArray *accessors = @[
        [NSString stringWithFormat:@"get%@", suffix],
        key,
        [NSString stringWithFormat:@"is%@", suffix],
    ];
    for (NSString *name in accessors) {
        SEL selector = NSSelectorFromString(name);
        if ([self respondsToSelector:selector]) {
            return NSKVCBoxedAccessor(self, selector);
        }
    }

    NSString *ivars[4] = {
        [@"_" stringByAppendingString:key],
        [@"_is" stringByAppendingString:suffix],
        key,
        [@"is" stringByAppendingString:suffix],
    };
    for (int i = 0; i < 4; i++) {
        id value = NSKVCBoxedIvar(self, ivars[i]);
        if (value != nil) {
            return value;
        }
    }
    return nil;
}

- (id)valueForKeyPath:(NSString *)keyPath {
    id value = self;
    NSArray *components = [keyPath componentsSeparatedByString:@"."];
    NSUInteger count = [components count];
    for (NSUInteger i = 0; i < count; i++) {
        if (value == nil) {
            return nil;
        }
        value = [value valueForKey:[components objectAtIndex:i]];
    }
    return value;
}

@end