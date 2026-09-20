/*
 * Copyright (C) 2026, Samuel Zormeister.
 *
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */

#ifndef NSError_h
#define NSError_h

#import <Foundation/NSObject.h>
#import <Foundation/NSObjCRuntime.h>

@class NSString;

/* NSErrorDomain and NSErrorUserInfoKey are typed NSString aliases; code that
 * declares an error domain constant spells it with the alias. */
typedef NSString *NSErrorDomain;
typedef NSString *NSErrorUserInfoKey;

/* The domain for the codes in FoundationErrors.h. */
FOUNDATION_EXPORT NSErrorDomain const NSCocoaErrorDomain;
FOUNDATION_EXPORT NSErrorDomain const NSPOSIXErrorDomain;
FOUNDATION_EXPORT NSErrorDomain const NSOSStatusErrorDomain;
FOUNDATION_EXPORT NSErrorDomain const NSMachErrorDomain;

/* The standard userInfo keys. */
FOUNDATION_EXPORT NSErrorUserInfoKey const NSLocalizedDescriptionKey;
FOUNDATION_EXPORT NSErrorUserInfoKey const NSLocalizedFailureReasonErrorKey;
FOUNDATION_EXPORT NSErrorUserInfoKey const NSLocalizedRecoverySuggestionErrorKey;
FOUNDATION_EXPORT NSErrorUserInfoKey const NSUnderlyingErrorKey;

@interface NSError : NSObject

+ (instancetype)errorWithDomain:(NSString *)domain code:(NSInteger)code;
+ (instancetype)errorWithDomain:(NSString *)domain
                           code:(NSInteger)code
                       userInfo:(NSDictionary *)userInfo;

- (instancetype)initWithDomain:(NSString *)domain
                          code:(NSInteger)code
                      userInfo:(NSDictionary *)userInfo NS_DESIGNATED_INITIALIZER;

- (NSInteger)code;
- (NSString *)domain;
- (NSDictionary *)userInfo;
- (NSString *)localizedDescription;

@end

#endif /* NSError_h */
