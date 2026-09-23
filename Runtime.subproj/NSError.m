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
#include <CoreFoundation/CFArray.h>
#include <CoreFoundation/CFString.h>
#include <string.h>

static CFComparisonResult NSErrorUserInfoKeyCompare(const void *a, const void *b, void *ctx) {
    (void)ctx;
    return CFStringCompare((CFStringRef)a, (CFStringRef)b, 0);
}

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
        /* Apple never exposes a nil userInfo: an omitted dictionary becomes an
         * (equal) empty dictionary so -userInfo is non-nil and -description
         * drops the clause uniformly when nothing is present. (Not [NSDictionary
         * new]: +new through the runtime-resolved class object is unsafe in the
         * dual-class gate environment, unlike the @{} literal.) */
        _userInfo = (userInfo != nil) ? [userInfo copy] : @{};
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
    id described = nil;
    if (_userInfo != nil) {
        described = [_userInfo objectForKey:NSLocalizedDescriptionKey];
    }
    if (described != nil) {
        return described;
    }
    if ([_domain isEqualToString:NSPOSIXErrorDomain]) {
        return [NSString stringWithFormat:@"The operation couldn\u2019t be completed. %s",
                                          strerror((int)_code)];
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
    return [[[self class] allocWithZone:zone] initWithDomain:_domain code:_code userInfo:_userInfo];
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
    BOOL hasUserInfo = (_userInfo != nil && [_userInfo count] > 0);
    if (hasUserInfo) {
        described = [_userInfo objectForKey:NSLocalizedDescriptionKey];
    }

    NSString *quoted;
    if (described != nil) {
        quoted = described;
    } else if ([_domain isEqualToString:NSPOSIXErrorDomain]) {
        quoted = [NSString stringWithUTF8String:strerror((int)_code)];
    } else {
        quoted = @"(null)";
    }

    NSString *userInfoPart = @"";
    if (hasUserInfo) {
        NSArray *keys = [_userInfo allKeys];
        CFMutableArrayRef sorted = CFArrayCreateMutable(kCFAllocatorDefault,
                                                        (CFIndex)[keys count],
                                                        &kCFTypeArrayCallBacks);
        for (NSUInteger i = 0; i < [keys count]; i++) {
            CFArrayAppendValue(sorted, (__bridge CFTypeRef)[keys objectAtIndex:i]);
        }
        CFArraySortValues(sorted, CFRangeMake(0, CFArrayGetCount(sorted)),
                          NSErrorUserInfoKeyCompare, NULL);

        NSString *clause = @"";
        BOOL first = YES;
        CFIndex n = CFArrayGetCount(sorted);
        for (CFIndex i = 0; i < n; i++) {
            NSString *key = (__bridge NSString *)CFArrayGetValueAtIndex(sorted, i);
            id value = [_userInfo objectForKey:key];
            NSString *rendered = [value isKindOfClass:[NSString class]] ? value : [value description];
            NSString *pair = [NSString stringWithFormat:@"%@=%@", key, rendered];
            clause = first ? pair : [clause stringByAppendingFormat:@", %@", pair];
            first = NO;
        }
        CFRelease(sorted);

        userInfoPart = [NSString stringWithFormat:@" UserInfo={%@}", clause];
    }

    return [NSString stringWithFormat:@"Error Domain=%@ Code=%ld \"%@\"%@",
                                      _domain, (long)_code, quoted, userInfoPart];
}

@end
