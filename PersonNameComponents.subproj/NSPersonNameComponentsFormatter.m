/*
 * Copyright (C) 2026, LibreDarwin.
 *
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */

#import <Foundation/NSPersonNameComponentsFormatter.h>
#import <Foundation/NSPersonNameComponents.h>
#import <Foundation/NSString.h>
#import <Foundation/NSArray.h>
#import <Foundation/NSDictionary.h>
#import <Foundation/NSAttributedString.h>
#import <Foundation/NSLocale.h>
#import <Foundation/NSCharacterSet.h>

/* ============================================================================
 *  Script detection
 *
 *  Apple classifies every UTF-16 code unit into a "script index" drawn from a
 *  fixed BMP table; anything not covered is neutral (index 1).  Two indices
 *  matter to name formatting: 2 (Han / Kana, i.e. CJK) and 3 (Hangul).  The
 *  table below is the recovered 78-range map (verified against Apple).
 * ==========================================================================*/

typedef struct {
    unsigned short lo;
    unsigned short hi;
    signed char index;
} _PNCScriptRange;

static const _PNCScriptRange _pncScriptRanges[] = {
    {0x0000, 0x0040, 1},  {0x0041, 0x005A, 6},  {0x005B, 0x0060, 1},  {0x0061, 0x007A, 6},
    {0x007B, 0x00BF, 1},  {0x00C0, 0x00D6, 6},  {0x00D7, 0x00D7, 1},  {0x00D8, 0x00F6, 6},
    {0x00F7, 0x00F7, 1},  {0x00F8, 0x02AF, 6},  {0x02B0, 0x036F, 1},  {0x0370, 0x03FF, 7},
    {0x0400, 0x052F, 8},  {0x0530, 0x058F, 9},  {0x0590, 0x05FF, 10}, {0x0600, 0x06FF, 11},
    {0x0700, 0x08FF, 1},  {0x0900, 0x0963, 12}, {0x0964, 0x0965, 1},  {0x0966, 0x097F, 12},
    {0x0980, 0x09FF, 13}, {0x0A00, 0x0A7F, 14}, {0x0A80, 0x0AFF, 15}, {0x0B00, 0x0B7F, 16},
    {0x0B80, 0x0BFF, 17}, {0x0C00, 0x0C7F, 18}, {0x0C80, 0x0CFF, 19}, {0x0D00, 0x0D7F, 20},
    {0x0D80, 0x0DFF, 21}, {0x0E00, 0x0E7F, 22}, {0x0E80, 0x0EFF, 23}, {0x0F00, 0x0FFF, 24},
    {0x1000, 0x109F, 25}, {0x10A0, 0x10FF, 26}, {0x1100, 0x11FF, 3},  {0x1200, 0x139F, 27},
    {0x13A0, 0x13FF, 28}, {0x1400, 0x167F, 29}, {0x1680, 0x177F, 1},  {0x1780, 0x17FF, 30},
    {0x1800, 0x18AF, 31}, {0x18B0, 0x1CFF, 1},  {0x1D00, 0x1D25, 6},  {0x1D26, 0x1D2A, 7},
    {0x1D2B, 0x1D2B, 8},  {0x1D2C, 0x1D6A, 1},  {0x1D6B, 0x1D9A, 6},  {0x1D9B, 0x1DFF, 1},
    {0x1E00, 0x1EFF, 6},  {0x1F00, 0x1FFF, 7},  {0x2000, 0x2C5F, 1},  {0x2C60, 0x2C7F, 6},
    {0x2C80, 0x2E7F, 1},  {0x2E80, 0x312F, 2},  {0x3130, 0x318F, 3},  {0x3190, 0x9FFF, 2},
    {0xA000, 0xA71F, 1},  {0xA720, 0xA7FF, 6},  {0xA800, 0xA95F, 1},  {0xA960, 0xA97F, 3},
    {0xA980, 0xABFF, 1},  {0xAC00, 0xD7FF, 3},  {0xD800, 0xF8FF, 1},  {0xF900, 0xFAFF, 2},
    {0xFB00, 0xFB06, 6},  {0xFB07, 0xFB12, 1},  {0xFB13, 0xFB17, 9},  {0xFB18, 0xFB1C, 1},
    {0xFB1D, 0xFB4F, 10}, {0xFB50, 0xFDFF, 11}, {0xFE00, 0xFE0F, 1},  {0xFE10, 0xFE6F, 2},
    {0xFE70, 0xFEFE, 11}, {0xFEFF, 0xFEFF, 1},  {0xFF00, 0xFF9F, 2},  {0xFFA0, 0xFFDF, 3},
    {0xFFE0, 0xFFFB, 2},  {0xFFFC, 0xFFFF, 1},
};

static NSInteger _PNCScriptIndexForCodeUnit(unichar c) {
    for (size_t i = 0; i < sizeof(_pncScriptRanges) / sizeof(_pncScriptRanges[0]); i++) {
        if (c >= _pncScriptRanges[i].lo && c <= _pncScriptRanges[i].hi) {
            return _pncScriptRanges[i].index;
        }
    }
    return 1;
}

/* The script index of the first non-neutral code unit in the string, or the
 * neutral index (1) when the string is empty or entirely neutral. */
static NSInteger _PNCInferredScriptIndex(NSString *string) {
    NSUInteger length = [string length];
    for (NSUInteger i = 0; i < length; i++) {
        NSInteger index = _PNCScriptIndexForCodeUnit([string characterAtIndex:i]);
        if (index != 1) {
            return index;
        }
    }
    return 1;
}

static BOOL _PNCIsCJKIndex(NSInteger index) {
    return index == 2 || index == 3;
}

/* Katakana (full-width, half-width, and the phonetic extensions). */
static BOOL _PNCIsKatakana(NSString *string) {
    NSUInteger length = [string length];
    if (length == 0) {
        return NO;
    }
    for (NSUInteger i = 0; i < length; i++) {
        unichar c = [string characterAtIndex:i];
        BOOL isKana = (c >= 0x30A1 && c <= 0x30FA) || (c >= 0x30FD && c <= 0x30FF) ||
                      (c >= 0x31F0 && c <= 0x31FF) || (c >= 0xFF66 && c <= 0xFF9D) ||
                      (c >= 0x30A0 && c <= 0x30A0);
        if (!isKana) {
            return NO;
        }
    }
    return YES;
}

/* -[_NSPersonNameComponentsStyleFormatter _delimiterBetweenString:andString:isPhonetic:]
 * exactly as recovered: the separator depends on the "from" script, then the
 * "to" script, with the katakana middle dot reserved for katakana+katakana. */
static NSString *_PNCDelimiterBetween(NSString *from, NSString *to, BOOL isPhonetic) {
    if (isPhonetic) {
        return @" ";
    }
    NSInteger fromIndex = _PNCInferredScriptIndex(from);
    NSInteger toIndex = _PNCInferredScriptIndex(to);
    if (!(fromIndex == 2 || fromIndex == 3 || fromIndex == 4 || fromIndex == 5)) {
        return @" ";
    }
    if (toIndex == 3 || toIndex == 4 || toIndex == 5) {
        return @"";
    }
    if (toIndex != 2) {
        return @" ";
    }
    if (!_PNCIsKatakana(from) || !_PNCIsKatakana(to)) {
        return @"";
    }
    return @"\u30FB";
}

/* ============================================================================
 *  Locale name order
 * ==========================================================================*/

/* The 35 localizations Apple's name-defaults table knows about. */
static NSArray *_PNCSupportedNameLocalizationKeys(void) {
    static NSArray *keys = nil;
    if (keys == nil) {
        keys = @[@"ar", @"ca", @"cs", @"da", @"de", @"el", @"en", @"es", @"es_MX", @"fi",
                 @"fr", @"he", @"hi", @"hr", @"hu", @"id", @"it", @"ja", @"ko", @"ms",
                 @"nl", @"no", @"pl", @"pt", @"pt_PT", @"ro", @"ru", @"sk", @"sv", @"th",
                 @"tr", @"uk", @"vi", @"zh_CN", @"zh_TW"];
    }
    return keys;
}

/* Localizations whose default display order is family-name first. */
static NSArray *_PNCFamilyNameFirstKeys(void) {
    static NSArray *keys = nil;
    if (keys == nil) {
        keys = @[@"hu", @"ja", @"ko", @"vi", @"zh_CN", @"zh_TW"];
    }
    return keys;
}

/* NSBundle+preferredLocalizationsFromArray:forPreferences: restricted to the
 * name-defaults key set: an exact identifier match wins, else the language
 * code, else the language code as a best effort. */
static NSString *_PNCPreferredLocalization(NSLocale *locale) {
    NSArray *supported = _PNCSupportedNameLocalizationKeys();
    NSString *identifier = [locale localeIdentifier];
    if ([supported containsObject:identifier]) {
        return identifier;
    }
    NSString *language = [locale objectForKey:NSLocaleLanguageCode];
    if ([supported containsObject:language]) {
        return language;
    }
    return language ?: @"en";
}

static NSInteger _PNCNameOrderForLocale(NSLocale *locale) {
    NSString *key = _PNCPreferredLocalization(locale);
    return [_PNCFamilyNameFirstKeys() containsObject:key] ? 2 : 1;
}

/* ============================================================================
 *  Component helpers
 * ==========================================================================*/

static NSString *_PNCValueForKey(NSPersonNameComponents *components, NSString *key) {
    if ([key isEqualToString:@"namePrefix"]) return components.namePrefix;
    if ([key isEqualToString:@"givenName"]) return components.givenName;
    if ([key isEqualToString:@"middleName"]) return components.middleName;
    if ([key isEqualToString:@"familyName"]) return components.familyName;
    if ([key isEqualToString:@"nameSuffix"]) return components.nameSuffix;
    if ([key isEqualToString:@"nickname"]) return components.nickname;
    return nil;
}

static BOOL _PNCComponentsAreEmpty(NSPersonNameComponents *components) {
    return components.namePrefix == nil && components.givenName == nil &&
           components.middleName == nil && components.familyName == nil &&
           components.nameSuffix == nil && components.nickname == nil;
}

static NSInteger _PNCComponentsScriptIndex(NSPersonNameComponents *components) {
    NSArray *keys = @[@"namePrefix", @"givenName", @"middleName", @"familyName",
                      @"nameSuffix", @"nickname"];
    for (NSString *key in keys) {
        NSString *value = _PNCValueForKey(components, key);
        if (value != nil) {
            NSInteger index = _PNCInferredScriptIndex(value);
            if (index != 1) {
                return index;
            }
        }
    }
    return 1;
}

/* -[__computedNameOrderForComponents:]: empty components take the locale's
 * native order; all-CJK components force family-name first; otherwise the
 * locale's default order applies. */
static NSInteger _PNCNameOrder(NSPersonNameComponents *components, NSLocale *locale) {
    if (components == nil || _PNCComponentsAreEmpty(components)) {
        return _PNCNameOrderForLocale(locale);
    }
    NSInteger scriptIndex = _PNCComponentsScriptIndex(components);
    if (_PNCIsCJKIndex(scriptIndex)) {
        return 2;
    }
    return _PNCNameOrderForLocale(locale);
}

static NSArray *_PNCOrderedKeys(NSInteger order) {
    if (order == 2) {
        return @[@"namePrefix", @"familyName", @"givenName", @"middleName", @"nameSuffix"];
    }
    return @[@"namePrefix", @"givenName", @"middleName", @"familyName", @"nameSuffix"];
}

/* The first script-appropriate initial of the string ("" for nil/empty). */
static NSString *_PNCInitialForString(NSString *string) {
    if (string == nil || [string length] == 0) {
        return @"";
    }
    NSInteger index = _PNCInferredScriptIndex(string);
    NSString *initial = [string substringToIndex:1];
    if (index == 6) {
        return [initial uppercaseString];
    }
    return initial;
}

/* +__longestComponentFromComponents: over {familyName, givenName}, the longer
 * winning and family name winning a tie (used for CJK abbreviations). */
static NSString *_PNCLongestComponent(NSPersonNameComponents *components) {
    NSString *best = nil;
    NSUInteger bestLength = 0;
    for (NSString *value in @[components.familyName ?: @"", components.givenName ?: @""]) {
        if ([value length] > bestLength) {
            best = value;
            bestLength = [value length];
        }
    }
    return best ?: @"";
}

/* Joins the present values among keys with the script-appropriate delimiter. */
static NSString *_PNCCatenate(NSPersonNameComponents *components, NSArray *keys, BOOL isPhonetic) {
    NSMutableArray *parts = [NSMutableArray array];
    for (NSString *key in keys) {
        NSString *value = _PNCValueForKey(components, key);
        if (value != nil && [value length] > 0) {
            [parts addObject:value];
        }
    }
    if ([parts count] == 0) {
        return @"";
    }
    NSMutableString *result = [[NSMutableString alloc] initWithString:parts[0]];
    for (NSUInteger i = 1; i < [parts count]; i++) {
        [result appendString:_PNCDelimiterBetween(parts[i - 1], parts[i], isPhonetic)];
        [result appendString:parts[i]];
    }
    return result;
}

/* ============================================================================
 *  Private state
 * ==========================================================================*/

@interface _NSPersonNameComponentsFormatterPrivate : NSObject
@property NSPersonNameComponentsFormatterStyle style;
@property BOOL phonetic;
@property (copy, nullable) NSLocale *locale;
@end

@implementation _NSPersonNameComponentsFormatterPrivate
@end

/* A single run in an annotated string: the text it contributes and the
 * component name (one of the NSPersonNameComponent* constants) it is tagged
 * with.  Ranges are filled in once the runs are concatenated. */
@interface _PNCAnnotationSegment : NSObject
@property (copy) NSString *value;
@property (copy) NSString *name;
@property NSRange range;
@end

@implementation _PNCAnnotationSegment
@end

static _PNCAnnotationSegment *_PNCAnnotationSegmentMake(NSString *value, NSString *name) {
    _PNCAnnotationSegment *segment = [[_PNCAnnotationSegment alloc] init];
    segment.value = value;
    segment.name = name;
    return segment;
}

/* ============================================================================
 *  NSPersonNameComponentsFormatter
 * ==========================================================================*/

NSString * const NSPersonNameComponentKey = @"NSPersonNameComponentKey";
NSString * const NSPersonNameComponentGivenName = @"givenName";
NSString * const NSPersonNameComponentFamilyName = @"familyName";
NSString * const NSPersonNameComponentMiddleName = @"middleName";
NSString * const NSPersonNameComponentPrefix = @"namePrefix";
NSString * const NSPersonNameComponentSuffix = @"nameSuffix";
NSString * const NSPersonNameComponentNickname = @"nickname";
NSString * const NSPersonNameComponentDelimiter = @"delimiter";

@implementation NSPersonNameComponentsFormatter

- (_NSPersonNameComponentsFormatterPrivate *)_state {
    if (_private == nil) {
        _private = [[_NSPersonNameComponentsFormatterPrivate alloc] init];
    }
    return _private;
}

#pragma mark Properties

- (NSPersonNameComponentsFormatterStyle)style {
    return [self _state].style;
}

- (void)setStyle:(NSPersonNameComponentsFormatterStyle)style {
    [self _state].style = style;
}

- (BOOL)isPhonetic {
    return [self _state].phonetic;
}

- (void)setPhonetic:(BOOL)phonetic {
    [self _state].phonetic = phonetic;
}

- (NSLocale *)locale {
    NSLocale *locale = [self _state].locale;
    return locale != nil ? locale : [NSLocale autoupdatingCurrentLocale];
}

- (void)setLocale:(NSLocale *)locale {
    [self _state].locale = locale;
}

#pragma mark Formatting

+ (NSString *)localizedStringFromPersonNameComponents:(NSPersonNameComponents *)components
                                                style:(NSPersonNameComponentsFormatterStyle)nameFormatStyle
                                              options:(NSPersonNameComponentsFormatterOptions)nameOptions {
    NSPersonNameComponentsFormatter *formatter = [[NSPersonNameComponentsFormatter alloc] init];
    formatter.style = nameFormatStyle;
    formatter.phonetic = (nameOptions & NSPersonNameComponentsFormatterPhonetic) != 0;
    return [formatter stringFromPersonNameComponents:components];
}

- (NSString *)stringFromPersonNameComponents:(NSPersonNameComponents *)components {
    NSPersonNameComponents *subject = self.isPhonetic ? components.phoneticRepresentation : components;
    if (subject == nil) {
        return @"";
    }
    NSPersonNameComponentsFormatterStyle style = self.style;
    if (style == NSPersonNameComponentsFormatterStyleDefault ||
        style == NSPersonNameComponentsFormatterStyleMedium) {
        return [self _mediumStringForComponents:subject];
    }
    if (style == NSPersonNameComponentsFormatterStyleShort) {
        return [self _shortStringForComponents:subject];
    }
    if (style == NSPersonNameComponentsFormatterStyleLong) {
        return [self _longStringForComponents:subject];
    }
    if (style == NSPersonNameComponentsFormatterStyleAbbreviated) {
        return [self _abbreviatedStringForComponents:subject];
    }
    return @"";
}

- (NSString *)stringForObjectValue:(id)obj {
    if (![obj isKindOfClass:[NSPersonNameComponents class]]) {
        return nil;
    }
    return [self stringFromPersonNameComponents:obj];
}

/* Medium: the given and family name in display order (other components are
 * ignored). */
- (NSString *)_mediumStringForComponents:(NSPersonNameComponents *)components {
    NSInteger order = _PNCNameOrder(components, self.locale);
    NSArray *keys = order == 2 ? @[@"familyName", @"givenName"] : @[@"givenName", @"familyName"];
    return _PNCCatenate(components, keys, self.isPhonetic);
}

/* Short: nickname, else given, else family; CJK components concatenate the
 * given and family name instead. */
- (NSString *)_shortStringForComponents:(NSPersonNameComponents *)components {
    if (_PNCIsCJKIndex(_PNCComponentsScriptIndex(components))) {
        NSInteger order = _PNCNameOrder(components, self.locale);
        NSArray *keys = order == 2 ? @[@"familyName", @"givenName"] : @[@"givenName", @"familyName"];
        return _PNCCatenate(components, keys, self.isPhonetic);
    }
    if (components.nickname != nil) {
        return components.nickname;
    }
    if (components.givenName != nil) {
        return components.givenName;
    }
    if (components.familyName != nil) {
        return components.familyName;
    }
    return @"";
}

/* Long: every present component in display order. */
- (NSString *)_longStringForComponents:(NSPersonNameComponents *)components {
    NSInteger order = _PNCNameOrder(components, self.locale);
    return _PNCCatenate(components, _PNCOrderedKeys(order), self.isPhonetic);
}

/* Abbreviated: given + family initials in display order; CJK components use
 * the longest of the given and family names instead. */
- (NSString *)_abbreviatedStringForComponents:(NSPersonNameComponents *)components {
    if (_PNCIsCJKIndex(_PNCComponentsScriptIndex(components))) {
        return _PNCLongestComponent(components);
    }
    NSInteger order = _PNCNameOrder(components, self.locale);
    NSString *givenInitial = _PNCInitialForString(components.givenName);
    NSString *familyInitial = _PNCInitialForString(components.familyName);
    if (order == 2) {
        return [familyInitial stringByAppendingString:givenInitial];
    }
    return [givenInitial stringByAppendingString:familyInitial];
}

#pragma mark Annotation

- (NSAttributedString *)annotatedStringFromPersonNameComponents:(NSPersonNameComponents *)components {
    NSPersonNameComponents *subject = self.isPhonetic ? components.phoneticRepresentation : components;
    if (subject == nil) {
        return [[NSAttributedString alloc] initWithString:@""];
    }

    NSArray *segments = [self _annotationSegmentsForComponents:subject];

    NSMutableString *string = [NSMutableString string];
    for (_PNCAnnotationSegment *segment in segments) {
        NSUInteger location = [string length];
        [string appendString:segment.value];
        segment.range = NSMakeRange(location, [segment.value length]);
    }

    NSMutableAttributedString *attributed =
        [[NSMutableAttributedString alloc] initWithString:string];
    for (_PNCAnnotationSegment *segment in segments) {
        if (segment.range.length > 0) {
            [attributed addAttribute:NSPersonNameComponentKey
                               value:segment.name
                               range:segment.range];
        }
    }
    return [attributed copy];
}

/* Builds the ordered run list for the current style.  Component runs carry the
 * component's name; separators carry NSPersonNameComponentDelimiter. */
- (NSArray *)_annotationSegmentsForComponents:(NSPersonNameComponents *)components {
    NSMutableArray *segments = [NSMutableArray array];
    NSPersonNameComponentsFormatterStyle style = self.style;

    if (style == NSPersonNameComponentsFormatterStyleDefault ||
        style == NSPersonNameComponentsFormatterStyleMedium) {
        [self _appendComponentSegmentsForComponents:components
            keys:[self _orderedKeySetForComponents:components]
                                              to:segments];
    } else if (style == NSPersonNameComponentsFormatterStyleLong) {
        NSInteger order = _PNCNameOrder(components, self.locale);
        [self _appendComponentSegmentsForComponents:components keys:_PNCOrderedKeys(order) to:segments];
    } else if (style == NSPersonNameComponentsFormatterStyleShort) {
        NSString *value = [self _shortStringForComponents:components];
        if ([value length] > 0) {
            [segments addObject:_PNCAnnotationSegmentMake(value, [self _shortKeyForComponents:components])];
        }
    } else if (style == NSPersonNameComponentsFormatterStyleAbbreviated) {
        if (_PNCIsCJKIndex(_PNCComponentsScriptIndex(components))) {
            NSString *value = _PNCLongestComponent(components);
            if ([value length] > 0) {
                [segments addObject:_PNCAnnotationSegmentMake(value, NSPersonNameComponentFamilyName)];
            }
        } else {
            NSInteger order = _PNCNameOrder(components, self.locale);
            NSArray *keys = order == 2 ? @[@"familyName", @"givenName"] : @[@"givenName", @"familyName"];
            for (NSString *key in keys) {
                NSString *initial = _PNCInitialForString(_PNCValueForKey(components, key));
                if ([initial length] > 0) {
                    [segments addObject:_PNCAnnotationSegmentMake(
                        initial, [self _componentNameForKey:key])];
                }
            }
        }
    }
    return segments;
}

- (NSArray *)_orderedKeySetForComponents:(NSPersonNameComponents *)components {
    NSInteger order = _PNCNameOrder(components, self.locale);
    return order == 2 ? @[@"familyName", @"givenName"] : @[@"givenName", @"familyName"];
}

- (NSString *)_shortKeyForComponents:(NSPersonNameComponents *)components {
    if (components.nickname != nil) return NSPersonNameComponentNickname;
    if (components.givenName != nil) return NSPersonNameComponentGivenName;
    return NSPersonNameComponentFamilyName;
}

- (NSString *)_componentNameForKey:(NSString *)key {
    if ([key isEqualToString:@"givenName"]) return NSPersonNameComponentGivenName;
    if ([key isEqualToString:@"familyName"]) return NSPersonNameComponentFamilyName;
    if ([key isEqualToString:@"middleName"]) return NSPersonNameComponentMiddleName;
    if ([key isEqualToString:@"namePrefix"]) return NSPersonNameComponentPrefix;
    if ([key isEqualToString:@"nameSuffix"]) return NSPersonNameComponentSuffix;
    if ([key isEqualToString:@"nickname"]) return NSPersonNameComponentNickname;
    return key;
}

/* Appends the present values among keys, interleaving delimiter runs. */
- (void)_appendComponentSegmentsForComponents:(NSPersonNameComponents *)components
                                         keys:(NSArray *)keys
                                           to:(NSMutableArray *)segments {
    NSString *previous = nil;
    for (NSString *key in keys) {
        NSString *value = _PNCValueForKey(components, key);
        if (value == nil || [value length] == 0) {
            continue;
        }
        if (previous != nil) {
            [segments addObject:_PNCAnnotationSegmentMake(
                _PNCDelimiterBetween(previous, value, self.isPhonetic),
                NSPersonNameComponentDelimiter)];
        }
        [segments addObject:_PNCAnnotationSegmentMake(value, [self _componentNameForKey:key])];
        previous = value;
    }
}

#pragma mark Parsing

- (NSPersonNameComponents *)personNameComponentsFromString:(NSString *)string {
    /* NOTE: a byte-faithful port of Apple's NPNameParser requires its embedded
     * given-name, family-name, particle, prefix and suffix dictionaries.  Until
     * those are recovered this returns a best-effort split of the string. */
    if (![string isKindOfClass:[NSString class]]) {
        return nil;
    }
    NSArray *rawTokens = [string componentsSeparatedByString:@" "];
    NSMutableArray *tokens = [NSMutableArray array];
    for (NSString *token in rawTokens) {
        if ([token length] > 0) {
            [tokens addObject:token];
        }
    }
    if ([tokens count] == 0) {
        return [NSPersonNameComponents new];
    }
    NSPersonNameComponents *components = [NSPersonNameComponents new];
    if ([tokens count] == 1) {
        components.givenName = tokens[0];
        return components;
    }
    components.givenName = tokens[0];
    components.familyName = [tokens lastObject];
    if ([tokens count] > 2) {
        NSMutableString *middle = [[NSMutableString alloc] init];
        for (NSUInteger i = 1; i + 1 < [tokens count]; i++) {
            if ([middle length] > 0) {
                [middle appendString:@" "];
            }
            [middle appendString:tokens[i]];
        }
        components.middleName = middle;
    }
    return components;
}

- (BOOL)getObjectValue:(id *)obj
             forString:(NSString *)string
      errorDescription:(NSString **)error {
    if (obj == NULL) {
        return NO;
    }
    *obj = [self personNameComponentsFromString:string];
    return *obj != nil;
}

@end
