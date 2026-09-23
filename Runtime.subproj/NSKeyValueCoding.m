/*
 * Copyright (C) 2026, Samuel Zormeister.
 *
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */

#import <Foundation/NSKeyValueCoding.h>
#import <Foundation/NSString.h>

@implementation NSObject (NSKeyValueCoding)

- (id)valueForKey:(NSString *)key {
    if ([key isEqualToString:@"self"]) {
        return self;
    }
    return nil;
}

- (id)valueForKeyPath:(NSString *)keyPath {
    id value = self;
    NSRange dot = [keyPath rangeOfString:@"."];
    if (dot.location == NSNotFound) {
        return [value valueForKey:keyPath];
    }
    NSString *remaining = keyPath;
    while (value != nil && (dot = [remaining rangeOfString:@"."]).location != NSNotFound) {
        value = [value valueForKey:[remaining substringToIndex:dot.location]];
        remaining = [remaining substringFromIndex:dot.location + 1];
    }
    if (value != nil) {
        value = [value valueForKey:remaining];
    }
    return value;
}

@end