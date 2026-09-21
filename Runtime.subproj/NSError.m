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
#import <Foundation/NSCoder.h>
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

/* The constant values deliberately drop the "Key"/"ErrorKey" suffix from the
 * symbol name: they are the strings Apple stores in the userInfo dictionary,
 * not the macro spelling. A dictionary printed by -description therefore shows
 * NSLocalizedFailureReason rather than NSLocalizedFailureReasonErrorKey. */
NSErrorUserInfoKey const NSLocalizedDescriptionKey = @"NSLocalizedDescription";
NSErrorUserInfoKey const NSLocalizedFailureReasonErrorKey = @"NSLocalizedFailureReason";
NSErrorUserInfoKey const NSLocalizedRecoverySuggestionErrorKey = @"NSLocalizedRecoverySuggestion";
NSErrorUserInfoKey const NSLocalizedRecoveryOptionsErrorKey = @"NSLocalizedRecoveryOptions";
NSErrorUserInfoKey const NSRecoveryAttempterErrorKey = @"NSRecoveryAttempter";
NSErrorUserInfoKey const NSHelpAnchorErrorKey = @"NSHelpAnchor";
NSErrorUserInfoKey const NSUnderlyingErrorKey = @"NSUnderlyingError";

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
    return [NSString stringWithFormat:@"The operation couldn\u2019t be completed. (%@ error %ld.)",
                                      _domain, (long)_code];
}

- (NSString *)localizedFailureReason {
    return [_userInfo objectForKey:NSLocalizedFailureReasonErrorKey];
}

- (NSString *)localizedRecoverySuggestion {
    return [_userInfo objectForKey:NSLocalizedRecoverySuggestionErrorKey];
}

- (NSArray *)localizedRecoveryOptions {
    return [_userInfo objectForKey:NSLocalizedRecoveryOptionsErrorKey];
}

- (id)recoveryAttempter {
    return [_userInfo objectForKey:NSRecoveryAttempterErrorKey];
}

- (NSString *)helpAnchor {
    return [_userInfo objectForKey:NSHelpAnchorErrorKey];
}

- (id)copyWithZone:(NSZone *)zone {
    return self;
}

- (void)encodeWithCoder:(NSCoder *)coder {
    if ([coder allowsKeyedCoding]) {
        [coder encodeObject:_domain forKey:@"NSDomain"];
        [coder encodeInteger:_code forKey:@"NSCode"];
        [coder encodeObject:_userInfo forKey:@"NSUserInfo"];
    } else {
        [coder encodeObject:_domain];
        [coder encodeValueOfObjCType:@encode(NSInteger) at:&_code];
        [coder encodeObject:_userInfo];
    }
}

- (instancetype)initWithCoder:(NSCoder *)coder {
    NSString *domain = nil;
    NSInteger code = 0;
    NSDictionary *userInfo = nil;

    if ([coder allowsKeyedCoding]) {
        domain = [coder decodeObjectForKey:@"NSDomain"];
        code = [coder decodeIntegerForKey:@"NSCode"];
        userInfo = [coder decodeObjectForKey:@"NSUserInfo"];
    } else {
        domain = [coder decodeObject];
        [coder decodeValueOfObjCType:@encode(NSInteger) at:&code size:sizeof(code)];
        userInfo = [coder decodeObject];
    }
    return [self initWithDomain:domain code:code userInfo:userInfo];
}

+ (BOOL)supportsSecureCoding {
    return YES;
}

- (BOOL)isEqual:(id)other {
    if (other == self) {
        return YES;
    }
    if (![other isKindOfClass:[NSError class]]) {
        return NO;
    }
    NSError *error = other;
    if (_code != error->_code) {
        return NO;
    }
    if (_domain != error->_domain && ![_domain isEqualToString:error->_domain]) {
        return NO;
    }
    if (_userInfo == error->_userInfo) {
        return YES;
    }
    return [_userInfo isEqualToDictionary:error->_userInfo];
}

- (NSUInteger)hash {
    /* The domain is content-hashed by length because NSString does not yet
     * override -hash; two errors with equal strings but distinct instances
     * still hash together. */
    return (NSUInteger)_code ^ ((NSUInteger)[_domain length] << 8);
}

- (NSString *)description {
    NSString *described = nil;
    if (_userInfo != nil) {
        described = [_userInfo objectForKey:NSLocalizedDescriptionKey];
    }
    if (_userInfo == nil) {
        return [NSString stringWithFormat:@"Error Domain=%@ Code=%ld \"%@\"",
                                          _domain, (long)_code, described];
    }
    return [NSString stringWithFormat:@"Error Domain=%@ Code=%ld \"%@\" UserInfo=%@",
                                      _domain, (long)_code, described, _userInfo];
}

@end
