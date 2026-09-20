/*
 * Copyright (C) 2026, LibreDarwin.
 *
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */

#ifndef NSPropertyList_h
#define NSPropertyList_h

#import <Foundation/NSObject.h>
#import <Foundation/NSData.h>
#import <Foundation/NSStream.h>

@class NSError, NSInputStream, NSOutputStream;

typedef NS_OPTIONS(NSUInteger, NSPropertyListMutabilityOptions) {
    NSPropertyListImmutable = 0,
    NSPropertyListMutableContainers = 1,
    NSPropertyListMutableContainersAndLeaves = 2,
};

typedef NSUInteger NSPropertyListReadOptions;
typedef NSUInteger NSPropertyListWriteOptions;

/* Values match CFPropertyListFormat one-for-one; NSPropertyListSerialization
 * is the CFPropertyList bridge, so they must not drift. */
typedef NS_ENUM(uint32_t, NSPropertyListFormat) {
    NSPropertyListOpenStepFormat = 1,
    NSPropertyListXMLFormat_v1_0 = 100,
    NSPropertyListBinaryFormat_v1_0 = 200,
};

@interface NSPropertyListSerialization : NSObject

+ (id)propertyListWithData:(NSData *)data
                   options:(NSPropertyListReadOptions)opt
                    format:(NSPropertyListFormat *)format
                     error:(NSError **)error;

+ (id)propertyListWithStream:(NSInputStream *)stream
                     options:(NSPropertyListReadOptions)opt
                      format:(NSPropertyListFormat *)format
                       error:(NSError **)error;

+ (NSData *)dataWithPropertyList:(id)plist
                          format:(NSPropertyListFormat)format
                         options:(NSPropertyListWriteOptions)opt
                           error:(NSError **)error;

+ (NSInteger)writePropertyList:(id)plist
                      toStream:(NSOutputStream *)stream
                        format:(NSPropertyListFormat)format
                       options:(NSPropertyListWriteOptions)opt
                         error:(NSError **)error;

+ (BOOL)propertyList:(id)plist
     isValidForFormat:(NSPropertyListFormat)format;

@end

#endif /* NSPropertyList_h */