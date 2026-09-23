/*
 * Copyright (C) 2026, Samuel Zormeister.
 *
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */

#ifndef NSKeyValueCoding_h
#define NSKeyValueCoding_h

#import <Foundation/NSObject.h>

/* A deliberately-lite subset of the NSKeyValueCoding protocol, enough for
 * NSSortDescriptor to resolve its keys. Apple's real KVC does a full
 * getter/setter/property/compliance walk and raises NSUnknownKeyException
 * for non-compliant keys; this port walks valueForKey: only. */
@interface NSObject (NSKeyValueCoding)

- (nullable id)valueForKey:(NSString *)key;
- (nullable id)valueForKeyPath:(NSString *)keyPath;

@end

#endif /* NSKeyValueCoding_h */