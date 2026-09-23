/*
 * Copyright (C) 2026, Samuel Zormeister.
 *
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */

#import <Foundation/NSLocale.h>
#include <CoreFoundation/CFLocale.h>
#include <CoreFoundation/CFNumber.h>

#if __has_feature(objc_arc)
#define NSLOCALE_TRANSFER(value) ((__bridge_transfer id)(value))
#define NSLOCALE_BORROWED(value) ((__bridge id)(value))
#define NSLOCALE_CF(type, value) ((__bridge type)(value))
#else
#define NSLOCALE_TRANSFER(value) ((id)(value))
#define NSLOCALE_BORROWED(value) ((id)(value))
#define NSLOCALE_CF(type, value) ((type)(value))
#endif

@interface NSLocale () {
    CFLocaleRef _locale;
}
- (CFLocaleRef)_backingLocale;
- (instancetype)_initWithBackingLocale:(CFLocaleRef)backing;
@end

/* NSLocale is an owning wrapper, not toll-free with CFLocale: it was created
 * through the CoreFoundation constructor and answers through the CFLocale it
 * holds.  Every entry point unwraps that backing locale instead of casting
 * self, which on a host CoreFoundation would dispatch the message to the
 * bridged class. */
static CFLocaleRef NSLocaleBacking(NSLocale *locale) {
    if (locale == nil || ![locale isKindOfClass:[NSLocale class]]) return NULL;
    return [locale _backingLocale];
}

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

- (CFLocaleRef)_backingLocale {
    return _locale;
}

- (instancetype)_initWithBackingLocale:(CFLocaleRef)backing {
    if (backing == NULL) return nil;
    self = [super init];
    if (self != nil) {
        _locale = backing;
    }
    return self;
}

+ (instancetype)currentLocale {
    return [[NSLocale alloc] _initWithBackingLocale:CFLocaleCopyCurrent()];
}

+ (instancetype)systemLocale {
    return [[NSLocale alloc] _initWithBackingLocale:
        CFLocaleCreateCopy(kCFAllocatorDefault, CFLocaleGetSystem())];
}

+ (NSLocale *)autoupdatingCurrentLocale {
    /* Apple returns a proxy that tracks the current locale; this port's
     * equivalent is a snapshot of the current locale, which the gate pins. */
    return [self currentLocale];
}

+ (NSArray *)preferredLanguages {
    return NSLOCALE_TRANSFER(CFLocaleCopyPreferredLanguages());
}

+ (NSArray *)availableLocaleIdentifiers {
    return NSLOCALE_TRANSFER(CFLocaleCopyAvailableLocaleIdentifiers());
}

+ (NSArray *)ISOLanguageCodes {
    return NSLOCALE_TRANSFER(CFLocaleCopyISOLanguageCodes());
}

+ (NSArray *)ISOCountryCodes {
    return NSLOCALE_TRANSFER(CFLocaleCopyISOCountryCodes());
}

+ (NSArray *)ISOCurrencyCodes {
    return NSLOCALE_TRANSFER(CFLocaleCopyISOCurrencyCodes());
}

+ (NSArray *)commonISOCurrencyCodes {
    return NSLOCALE_TRANSFER(CFLocaleCopyCommonISOCurrencyCodes());
}

+ (instancetype)localeWithLocaleIdentifier:(NSString *)identifier {
    return [[NSLocale alloc] initWithLocaleIdentifier:identifier];
}

- (instancetype)initWithLocaleIdentifier:(NSString *)identifier {
    CFLocaleRef backing = CFLocaleCreate(kCFAllocatorDefault,
                                         NSLOCALE_CF(CFStringRef, identifier));
    if (backing == NULL) return nil;
    _locale = backing;
    return self;
}

- (void)dealloc {
    if (_locale != NULL) CFRelease(_locale);
}

- (NSString *)localeIdentifier {
    return NSLOCALE_BORROWED(CFLocaleGetIdentifier(NSLocaleBacking(self)));
}

- (id)objectForKey:(NSLocaleKey)key {
    /* The metric flag is stored as a CFBoolean; Apple's objectForKey: answers
     * the string form ("1"/"0"), not the raw boolean. */
    CFTypeRef value = CFLocaleGetValue(NSLocaleBacking(self), NSLocaleCFKey(key));
    if (value != NULL && CFGetTypeID(value) == CFBooleanGetTypeID()) {
        return CFBooleanGetValue((CFBooleanRef)value) ? @"1" : @"0";
    }
    return NSLOCALE_BORROWED(value);
}

- (NSString *)displayNameForKey:(NSLocaleKey)key value:(id)value {
    CFStringRef result = CFLocaleCopyDisplayNameForPropertyValue(
        NSLocaleBacking(self), NSLocaleCFKey(key), NSLOCALE_CF(CFStringRef, value));
    return NSLOCALE_TRANSFER(result);
}

- (id)copyWithZone:(NSZone *)zone {
    (void)zone;
    return [[NSLocale alloc] _initWithBackingLocale:
        CFLocaleCreateCopy(kCFAllocatorDefault, NSLocaleBacking(self))];
}

- (BOOL)isEqual:(id)object {
    if (object == nil) return NO;
    if (object == self) return YES;
    if (![object isKindOfClass:[NSLocale class]]) return NO;
    return CFEqual(NSLocaleBacking(self), NSLocaleBacking(object));
}

- (NSUInteger)hash {
    return (NSUInteger)CFHash(NSLocaleBacking(self));
}

@end
