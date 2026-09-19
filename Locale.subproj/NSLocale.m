/*
 * Copyright (C) 2026, Samuel Zormeister.
 *
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */

#import <Foundation/NSLocale.h>
#include <CoreFoundation/CFLocale.h>

#if __has_feature(objc_arc)
#define NSLOCALE_TRANSFER(value) ((__bridge_transfer id)(value))
#define NSLOCALE_BORROWED(value) ((__bridge id)(value))
#define NSLOCALE_CF(type, value) ((__bridge type)(value))
#else
#define NSLOCALE_TRANSFER(value) ((id)(value))
#define NSLOCALE_BORROWED(value) ((id)(value))
#define NSLOCALE_CF(type, value) ((type)(value))
#endif

NSLocaleKey const NSLocaleIdentifier = @"kCFLocaleIdentifierKey";
NSLocaleKey const NSLocaleLanguageCode = @"kCFLocaleLanguageCodeKey";
NSLocaleKey const NSLocaleCountryCode = @"kCFLocaleCountryCodeKey";
NSLocaleKey const NSLocaleScriptCode = @"kCFLocaleScriptCodeKey";
NSLocaleKey const NSLocaleVariantCode = @"kCFLocaleVariantCodeKey";
NSLocaleKey const NSLocaleCalendar = @"kCFLocaleCalendarKey";
NSLocaleKey const NSLocaleCollationIdentifier = @"kCFLocaleCollationIdentifierKey";
NSLocaleKey const NSLocaleCurrencyCode = @"kCFLocaleCurrencyCodeKey";
NSLocaleKey const NSLocaleCurrencySymbol = @"kCFLocaleCurrencySymbolKey";
NSLocaleKey const NSLocaleDecimalSeparator = @"kCFLocaleDecimalSeparatorKey";
NSLocaleKey const NSLocaleGroupingSeparator = @"kCFLocaleGroupingSeparatorKey";
NSLocaleKey const NSLocaleMeasurementSystem = @"kCFLocaleMeasurementSystemKey";
NSLocaleKey const NSLocaleUsesMetricSystem = @"kCFLocaleUsesMetricSystemKey";

static CFStringRef NSLocaleCFKey(NSLocaleKey key) {
    if (key == NSLocaleIdentifier) return kCFLocaleIdentifier;
    if (key == NSLocaleLanguageCode) return kCFLocaleLanguageCode;
    if (key == NSLocaleCountryCode) return kCFLocaleCountryCode;
    if (key == NSLocaleScriptCode) return kCFLocaleScriptCode;
    if (key == NSLocaleVariantCode) return kCFLocaleVariantCode;
    if (key == NSLocaleCalendar) return kCFLocaleCalendar;
    if (key == NSLocaleCollationIdentifier) return kCFLocaleCollationIdentifier;
    if (key == NSLocaleCurrencyCode) return kCFLocaleCurrencyCode;
    if (key == NSLocaleCurrencySymbol) return kCFLocaleCurrencySymbol;
    if (key == NSLocaleDecimalSeparator) return kCFLocaleDecimalSeparator;
    if (key == NSLocaleGroupingSeparator) return kCFLocaleGroupingSeparator;
    if (key == NSLocaleMeasurementSystem) return kCFLocaleMeasurementSystem;
    if (key == NSLocaleUsesMetricSystem) return kCFLocaleUsesMetricSystem;
    return NSLOCALE_CF(CFStringRef, key);
}

@implementation NSLocale

+ (instancetype)currentLocale {
    return NSLOCALE_TRANSFER(CFLocaleCopyCurrent());
}

+ (instancetype)systemLocale {
    return NSLOCALE_TRANSFER(CFLocaleCreateCopy(kCFAllocatorDefault, CFLocaleGetSystem()));
}

+ (instancetype)localeWithLocaleIdentifier:(NSString *)identifier {
    return NSLOCALE_TRANSFER(CFLocaleCreate(kCFAllocatorDefault,
                                             NSLOCALE_CF(CFStringRef, identifier)));
}

- (instancetype)initWithLocaleIdentifier:(NSString *)identifier {
    return NSLOCALE_TRANSFER(CFLocaleCreate(kCFAllocatorDefault,
                                             NSLOCALE_CF(CFStringRef, identifier)));
}

- (NSString *)localeIdentifier {
    return NSLOCALE_BORROWED(CFLocaleGetIdentifier(NSLOCALE_CF(CFLocaleRef, self)));
}

- (id)objectForKey:(NSLocaleKey)key {
    CFStringRef cfKey = NSLocaleCFKey(key);
    return NSLOCALE_BORROWED(CFLocaleGetValue(NSLOCALE_CF(CFLocaleRef, self), cfKey));
}

- (NSString *)displayNameForKey:(NSLocaleKey)key value:(id)value {
    CFStringRef result = CFLocaleCopyDisplayNameForPropertyValue(
        NSLOCALE_CF(CFLocaleRef, self), NSLocaleCFKey(key), NSLOCALE_CF(CFStringRef, value));
    return NSLOCALE_TRANSFER(result);
}

- (id)copyWithZone:(NSZone *)zone {
    (void)zone;
    return NSLOCALE_TRANSFER(CFLocaleCreateCopy(kCFAllocatorDefault,
                                                NSLOCALE_CF(CFLocaleRef, self)));
}

- (BOOL)isEqual:(id)object {
    return object != nil && CFEqual(NSLOCALE_CF(CFTypeRef, self),
                                    NSLOCALE_CF(CFTypeRef, object));
}

- (NSUInteger)hash {
    return (NSUInteger)CFHash(NSLOCALE_CF(CFTypeRef, self));
}

@end

#if DEPLOYMENT_RUNTIME_OBJC
__attribute__((constructor))
static void __NSCFLocaleBridgeInit(void) {
    _CFRuntimeBridgeClasses(CFLocaleGetTypeID(), "NSLocale");
}
#endif
