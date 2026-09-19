/*
 * Copyright (C) 2026, PureDarwin Project.
 *
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */

#ifndef NSJSONSerialization_h
#define NSJSONSerialization_h

#import <Foundation/NSObject.h>
#import <Foundation/NSData.h>
#import <Foundation/NSStream.h>

@class NSError, NSInputStream, NSOutputStream;

typedef NS_OPTIONS(NSUInteger, NSJSONReadingOptions) {
    NSJSONReadingMutableContainers = 1UL << 0,
    NSJSONReadingMutableLeaves = 1UL << 1,
    NSJSONReadingAllowFragments = 1UL << 2,
};

typedef NS_OPTIONS(NSUInteger, NSJSONWritingOptions) {
    NSJSONWritingPrettyPrinted = 1UL << 0,
    NSJSONWritingSortedKeys = 1UL << 1,
};

FOUNDATION_EXPORT BOOL NSJSONSerializationIsValidJSONObject(id object);

@interface NSJSONSerialization : NSObject

+ (id)JSONObjectWithData:(NSData *)data options:(NSJSONReadingOptions)options error:(NSError **)error;
+ (id)JSONObjectWithStream:(NSInputStream *)stream options:(NSJSONReadingOptions)options error:(NSError **)error;
+ (NSData *)dataWithJSONObject:(id)object options:(NSJSONWritingOptions)options error:(NSError **)error;
+ (BOOL)writeJSONObject:(id)object toStream:(NSOutputStream *)stream options:(NSJSONWritingOptions)options error:(NSError **)error;

@end

#endif /* NSJSONSerialization_h */
