/*
 * Copyright (C) 2026, Samuel Zormeister.
 *
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */

#import <Foundation/NSError.h>
#import <Foundation/NSString.h>
#import <Foundation/NSDictionary.h>
#include <CoreFoundation/CFString.h>

#if __has_feature(objc_arc)
#define NSERROR_TRANSFER(value) (__bridge_transfer NSString *)(value)
#else
#define NSERROR_TRANSFER(value) [(NSString *)(value) autorelease]
#endif

NSErrorDomain const NSCocoaErrorDomain = @"NSCocoaErrorDomain";
NSErrorDomain const NSPOSIXErrorDomain = @"NSPOSIXErrorDomain";
NSErrorDomain const NSOSStatusErrorDomain = @"NSOSStatusErrorDomain";
NSErrorDomain const NSMachErrorDomain = @"NSMachErrorDomain";

NSErrorUserInfoKey const NSLocalizedDescriptionKey = @"NSLocalizedDescriptionKey";
NSErrorUserInfoKey const NSLocalizedFailureReasonErrorKey = @"NSLocalizedFailureReasonErrorKey";
NSErrorUserInfoKey const NSLocalizedRecoverySuggestionErrorKey = @"NSLocalizedRecoverySuggestionErrorKey";
NSErrorUserInfoKey const NSUnderlyingErrorKey = @"NSUnderlyingErrorKey";

@implementation NSError {
    NSString *_domain;
    NSInteger _code;
    NSDictionary *_userInfo;
}

+ (instancetype)errorWithDomain:(NSString *)domain code:(NSInteger)code {
    return [self errorWithDomain:domain code:code userInfo:nil];
}

+ (instancetype)errorWithDomain:(NSString *)domain
                           code:(NSInteger)code
                       userInfo:(NSDictionary *)userInfo {
    return [[self alloc] initWithDomain:domain code:code userInfo:userInfo];
}

- (instancetype)initWithDomain:(NSString *)domain
                          code:(NSInteger)code
                      userInfo:(NSDictionary *)userInfo {
    self = [super init];
    if (self != nil) {
        _domain = [domain copy];
        _code = code;
        _userInfo = [userInfo copy];
    }
    return self;
}

#if !__has_feature(objc_arc)
- (void)dealloc {
    [_domain release];
    [_userInfo release];
    [super dealloc];
}
#endif

- (NSInteger)code {
    return _code;
}

- (NSString *)domain {
    return _domain;
}

- (NSDictionary *)userInfo {
    return _userInfo;
}

- (NSString *)localizedDescription {
    if (_userInfo != nil) {
        NSString *described = [_userInfo objectForKey:NSLocalizedDescriptionKey];
        if (described != nil) {
            return described;
        }
    }
    return NSERROR_TRANSFER(CFStringCreateWithFormat(kCFAllocatorDefault, NULL,
                                                      CFSTR("%@ error %ld."),
                                                      (CFStringRef)_domain, (long)_code));
}

@end
