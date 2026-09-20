/*
 * Copyright (C) 2026, LibreDarwin.
 *
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */

#import <Foundation/NSPropertyList.h>
#import <Foundation/NSDictionary.h>
#import <Foundation/FoundationErrors.h>
#import <Foundation/NSError.h>
#include <CoreFoundation/CFPropertyList.h>
#include <CoreFoundation/CFStream.h>

/* Bridged straight onto CFPropertyList. Error codes line up with the
 * property-list range in FoundationErrors.h:
 *
 *   read  corrupt / unknown-version / stream  -> 3840 / 3841 / 3842
 *   write stream / invalid / unknown-version -> 3851 / 3852 / 3853
 *
 * CFPropertyListCreate* returns NULL on failure without distinguishing the
 * cause, so the data API reports 3840 and the stream API reports 3842, the
 * two cases that dominate in practice. OpenStep is a read-only format on
 * modern macOS: writing it always fails with 3852. */

static void PLSetError(NSError **error, NSInteger code, NSString *reason) {
    if (error) {
        *error = [NSError errorWithDomain:NSCocoaErrorDomain
                                     code:code
                                 userInfo:@{ NSLocalizedDescriptionKey: reason ?: @"" }];
    }
}

@implementation NSPropertyListSerialization

+ (id)propertyListWithData:(NSData *)data
                   options:(NSPropertyListReadOptions)opt
                    format:(NSPropertyListFormat *)format
                     error:(NSError **)error
{
    if (!data) {
        PLSetError(error, NSPropertyListReadCorruptError, @"The data could not be read because it is not valid.");
        return nil;
    }

    CFPropertyListFormat outFormat = kCFPropertyListXMLFormat_v1_0;
    CFPropertyListRef plist = CFPropertyListCreateWithData(
        kCFAllocatorDefault, (__bridge CFDataRef)data,
        (CFPropertyListMutabilityOptions)(opt & (NSPropertyListMutableContainersAndLeaves |
                                                  NSPropertyListMutableContainers)),
        &outFormat, NULL);

    if (!plist) {
        PLSetError(error, NSPropertyListReadCorruptError, @"The data could not be read because it is not valid.");
        return nil;
    }

    if (format) {
        *format = (NSPropertyListFormat)outFormat;
    }
#if __has_feature(objc_arc)
    return (__bridge_transfer id)plist;
#else
    return [(id)plist autorelease];
#endif
}

+ (id)propertyListWithStream:(NSInputStream *)stream
                     options:(NSPropertyListReadOptions)opt
                      format:(NSPropertyListFormat *)format
                       error:(NSError **)error
{
    if (!stream) {
        PLSetError(error, NSPropertyListReadStreamError, @"The stream could not be read because it is not valid.");
        return nil;
    }

    CFPropertyListFormat outFormat = kCFPropertyListXMLFormat_v1_0;
    CFPropertyListRef plist = CFPropertyListCreateWithStream(
        kCFAllocatorDefault, (__bridge CFReadStreamRef)stream, 0,
        (CFPropertyListMutabilityOptions)(opt & (NSPropertyListMutableContainersAndLeaves |
                                                  NSPropertyListMutableContainers)),
        &outFormat, NULL);

    if (!plist) {
        PLSetError(error, NSPropertyListReadStreamError, @"The stream could not be read because it is not valid.");
        return nil;
    }

    if (format) {
        *format = (NSPropertyListFormat)outFormat;
    }
#if __has_feature(objc_arc)
    return (__bridge_transfer id)plist;
#else
    return [(id)plist autorelease];
#endif
}

+ (NSData *)dataWithPropertyList:(id)plist
                          format:(NSPropertyListFormat)format
                         options:(NSPropertyListWriteOptions)opt
                           error:(NSError **)error
{
    if (!plist) {
        PLSetError(error, NSPropertyListWriteInvalidError, @"The property list is invalid.");
        return nil;
    }

    if (format == NSPropertyListOpenStepFormat) {
        PLSetError(error, NSPropertyListWriteInvalidError, @"The property list format is not writable.");
        return nil;
    }

    CFDataRef data = CFPropertyListCreateData(
        kCFAllocatorDefault, (__bridge CFPropertyListRef)plist,
        (CFPropertyListFormat)format, 0, NULL);

    if (!data) {
        PLSetError(error, NSPropertyListWriteInvalidError, @"The property list is invalid.");
        return nil;
    }

#if __has_feature(objc_arc)
    return (__bridge_transfer NSData *)data;
#else
    return [(NSData *)data autorelease];
#endif
}

+ (NSInteger)writePropertyList:(id)plist
                      toStream:(NSOutputStream *)stream
                        format:(NSPropertyListFormat)format
                       options:(NSPropertyListWriteOptions)opt
                         error:(NSError **)error
{
    if (!plist || !stream) {
        PLSetError(error, NSPropertyListWriteInvalidError, @"The property list is invalid.");
        return 0;
    }

    if (format == NSPropertyListOpenStepFormat) {
        PLSetError(error, NSPropertyListWriteInvalidError, @"The property list format is not writable.");
        return 0;
    }

    if (!CFPropertyListIsValid((__bridge CFPropertyListRef)plist, (CFPropertyListFormat)format)) {
        PLSetError(error, NSPropertyListWriteInvalidError, @"The property list is invalid.");
        return 0;
    }

    CFIndex written = CFPropertyListWrite(
        (__bridge CFPropertyListRef)plist, (__bridge CFWriteStreamRef)stream,
        (CFPropertyListFormat)format, 0, NULL);

    if (written == 0) {
        PLSetError(error, NSPropertyListWriteStreamError, @"The stream could not be written.");
        return 0;
    }

    return (NSInteger)written;
}

+ (BOOL)propertyList:(id)plist
     isValidForFormat:(NSPropertyListFormat)format
{
    if (!plist || format == NSPropertyListOpenStepFormat) {
        return NO;
    }
    return CFPropertyListIsValid((__bridge CFPropertyListRef)plist, (CFPropertyListFormat)format) ? YES : NO;
}

@end