/*
 * Copyright (C) 2026, Samuel Zormeister.
 *
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */

#ifndef NSLocale_h
#define NSLocale_h

#import <Foundation/NSObject.h>

@class NSString;

typedef NSString *NSLocaleKey;

FOUNDATION_EXPORT NSLocaleKey const NSLocaleIdentifier;
FOUNDATION_EXPORT NSLocaleKey const NSLocaleLanguageCode;
FOUNDATION_EXPORT NSLocaleKey const NSLocaleCountryCode;
FOUNDATION_EXPORT NSLocaleKey const NSLocaleScriptCode;
FOUNDATION_EXPORT NSLocaleKey const NSLocaleVariantCode;
FOUNDATION_EXPORT NSLocaleKey const NSLocaleCalendar;
FOUNDATION_EXPORT NSLocaleKey const NSLocaleCollationIdentifier;
FOUNDATION_EXPORT NSLocaleKey const NSLocaleCurrencyCode;
FOUNDATION_EXPORT NSLocaleKey const NSLocaleCurrencySymbol;
FOUNDATION_EXPORT NSLocaleKey const NSLocaleDecimalSeparator;
FOUNDATION_EXPORT NSLocaleKey const NSLocaleGroupingSeparator;
FOUNDATION_EXPORT NSLocaleKey const NSLocaleMeasurementSystem;
FOUNDATION_EXPORT NSLocaleKey const NSLocaleUsesMetricSystem;

@interface NSLocale : NSObject <NSCopying>

+ (instancetype)currentLocale;
+ (instancetype)systemLocale;
+ (instancetype)localeWithLocaleIdentifier:(NSString *)identifier;

- (instancetype)initWithLocaleIdentifier:(NSString *)identifier;
- (NSString *)localeIdentifier;
- (id)objectForKey:(NSLocaleKey)key;
- (NSString *)displayNameForKey:(NSLocaleKey)key value:(id)value;
- (id)copyWithZone:(NSZone *)zone;

@end

#endif /* NSLocale_h */
