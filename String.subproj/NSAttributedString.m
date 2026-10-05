/*
 * Copyright (C) 2026, Samuel Zormeister.
 *
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */

#import <Foundation/NSAttributedString.h>
#import <Foundation/NSArray.h>
#import <Foundation/NSEnumerator.h>
#import <Foundation/NSException.h>
#import <Foundation/NSValue.h>
#include <CoreFoundation/CFAttributedString.h>
#include <objc/runtime.h>

/* NSAttributedString owns a CFAttributedString rather than bridging to it, for
 * the same reason NSLocale owns a CFLocale and NSURL owns a CFURL: CoreFoundation
 * registers its own NSAttributedString against the CFAttributedString type
 * while CF itself initializes, which necessarily runs before this library's
 * constructors, so a toll-free port class would lose every instance method to
 * CoreFoundation's implementation.  Holding the CF object in an ivar keeps
 * every instance a real port class.
 *
 * Attributes need no conversion: the port's NSString and NSDictionary are
 * themselves toll-free with CFString and CFDictionary, so an attribute
 * dictionary can be handed to CFAttributedString unchanged. */

@interface NSAttributedString () {
    CFAttributedStringRef _attrString;
}
- (CFAttributedStringRef)_backing;
- (instancetype)_initWithBacking:(CFAttributedStringRef)backing;
@end

@interface NSMutableAttributedString () {
    CFMutableAttributedStringRef _mutableAttrString;
}
- (instancetype)_initWithMutableBacking:(CFMutableAttributedStringRef)backing;
- (NSRange)rangeOfString:(NSString *)target
                 options:(NSStringCompareOptions)options
                   range:(NSRange)range;
@end

static CFAttributedStringRef NSAttributedStringBacking(NSAttributedString *s) {
    if (s == nil || ![s isKindOfClass:[NSAttributedString class]]) return NULL;
    return [s _backing];
}

static CFRange NSAttributedStringCFRange(NSRange range) {
    return CFRangeMake((CFIndex)range.location, (CFIndex)range.length);
}

/* Apple rejects these arguments with NSInvalidArgumentException before any CF
 * call is made, and so must the port: CoreFoundation's own handling of a NULL
 * string, NULL replacement, or NULL attributed string is a crash rather than
 * an exception. */
static void NSAttributedStringCheckNotNil(NSAttributedString *s, id object,
                                          SEL selector, NSString *argument) {
    if (object == nil) {
        [NSException raise:NSInvalidArgumentException
                    format:@"*** -[%@ %@]: %@ argument cannot be nil",
                           NSStringFromClass([s class]), NSStringFromSelector(selector),
                           argument];
    }
}

static void NSAttributedStringCheckRange(NSAttributedString *s, NSRange range,
                                         SEL selector) {
    NSUInteger length = (NSUInteger)CFAttributedStringGetLength(NSAttributedStringBacking(s));
    if (range.location > NSUIntegerMax - range.length ||
        range.location + range.length > length) {
        [NSException raise:NSRangeException
                    format:@"*** -[%@ %@]: range {%lu, %lu} extends beyond the string's bounds {%lu, %lu}",
                           NSStringFromClass([s class]), NSStringFromSelector(selector),
                           (unsigned long)range.location, (unsigned long)range.length,
                           (unsigned long)0, (unsigned long)length];
    }
}

@implementation NSAttributedString

- (CFAttributedStringRef)_backing {
    return _attrString;
}

/* Adopts the caller's +1 reference rather than retaining again, so the ivar
 * and -dealloc balance against the CFAttributedStringCreate that produced it. */
- (instancetype)_initWithBacking:(CFAttributedStringRef)backing {
    if (backing == NULL) return nil;
    self = [super init];
    if (self != nil) {
        _attrString = backing;
    }
    return self;
}

- (void)dealloc {
    if (_attrString != NULL) CFRelease(_attrString);
    _attrString = NULL;
}

- (instancetype)initWithString:(NSString *)str {
    return [self initWithString:str attributes:nil];
}

- (instancetype)initWithString:(NSString *)str
                    attributes:(NSDictionary<NSAttributedStringKey, id> *)attrs {
    NSAttributedStringCheckNotNil(self, str, _cmd, @"string");
    /* A NULL dictionary means "no attributes" here and is not rejected. */
    return [self _initWithBacking:CFAttributedStringCreate(kCFAllocatorDefault,
                                                          (__bridge CFStringRef)str,
                                                          (__bridge CFDictionaryRef)attrs)];
}

- (instancetype)initWithAttributedString:(NSAttributedString *)attrStr {
    NSAttributedStringCheckNotNil(self, attrStr, _cmd, @"attributedString");
    return [self _initWithBacking:
        CFAttributedStringCreateCopy(kCFAllocatorDefault, NSAttributedStringBacking(attrStr))];
}

- (NSString *)string {
    CFStringRef string = CFAttributedStringGetString(NSAttributedStringBacking(self));
    return CFBridgingRelease(CFRetain(string));
}

- (NSUInteger)length {
    return (NSUInteger)CFAttributedStringGetLength(NSAttributedStringBacking(self));
}

/* CoreFoundation exposes only the longest-effective-range accessor, so the
 * shorter -effectiveRange: variants report that same range.  The search range
 * must span the whole string rather than start at `location`: an effective
 * range is allowed to extend backwards before the index it was asked about,
 * and restricting the search to [location, end) would clip it. */
- (NSDictionary<NSAttributedStringKey, id> *)attributesAtIndex:(NSUInteger)location
                                                effectiveRange:(NSRangePointer)range {
    CFRange effective = CFRangeMake(0, 0);
    CFDictionaryRef attributes = CFAttributedStringGetAttributesAndLongestEffectiveRange(
        NSAttributedStringBacking(self), (CFIndex)location,
        NSAttributedStringCFRange(NSMakeRange(0, [self length])),
        &effective);
    if (range != NULL) *range = NSMakeRange((NSUInteger)effective.location,
                                           (NSUInteger)effective.length);
    return CFBridgingRelease(CFRetain(attributes));
}

- (id)attribute:(NSAttributedStringKey)attrName
        atIndex:(NSUInteger)location
 effectiveRange:(NSRangePointer)range {
    CFRange effective = CFRangeMake(0, 0);
    CFTypeRef value = CFAttributedStringGetAttributeAndLongestEffectiveRange(
        NSAttributedStringBacking(self), (CFIndex)location,
        (__bridge CFStringRef)attrName,
        NSAttributedStringCFRange(NSMakeRange(0, [self length])),
        &effective);
    if (range != NULL) *range = NSMakeRange((NSUInteger)effective.location,
                                           (NSUInteger)effective.length);
    /* CF reports an absent attribute as CFNULL; the port must hand back nil. */
    if (value == NULL || value == kCFNull) return nil;
    return CFBridgingRelease(CFRetain(value));
}

- (NSDictionary<NSAttributedStringKey, id> *)
    attributesAtIndex:(NSUInteger)location
  longestEffectiveRange:(NSRangePointer)range
              inRange:(NSRange)rangeLimit {
    CFRange effective = CFRangeMake(0, 0);
    CFDictionaryRef attributes = CFAttributedStringGetAttributesAndLongestEffectiveRange(
        NSAttributedStringBacking(self), (CFIndex)location,
        NSAttributedStringCFRange(rangeLimit), &effective);
    if (range != NULL) *range = NSMakeRange((NSUInteger)effective.location,
                                           (NSUInteger)effective.length);
    return CFBridgingRelease(CFRetain(attributes));
}

- (id)attribute:(NSAttributedStringKey)attrName
        atIndex:(NSUInteger)location
 longestEffectiveRange:(NSRangePointer)range
        inRange:(NSRange)rangeLimit {
    CFRange effective = CFRangeMake(0, 0);
    CFTypeRef value = CFAttributedStringGetAttributeAndLongestEffectiveRange(
        NSAttributedStringBacking(self), (CFIndex)location,
        (__bridge CFStringRef)attrName, NSAttributedStringCFRange(rangeLimit), &effective);
    if (range != NULL) *range = NSMakeRange((NSUInteger)effective.location,
                                           (NSUInteger)effective.length);
    if (value == NULL || value == kCFNull) return nil;
    return CFBridgingRelease(CFRetain(value));
}

- (NSAttributedString *)attributedSubstringFromRange:(NSRange)range {
    NSAttributedStringCheckRange(self, range, _cmd);
    return [[NSAttributedString alloc] _initWithBacking:
        CFAttributedStringCreateWithSubstring(kCFAllocatorDefault,
                                              NSAttributedStringBacking(self),
                                              NSAttributedStringCFRange(range))];
}

- (BOOL)isEqualToAttributedString:(NSAttributedString *)other {
    CFAttributedStringRef backing = NSAttributedStringBacking(self);
    CFAttributedStringRef otherBacking = NSAttributedStringBacking(other);
    if (backing == NULL || otherBacking == NULL) return backing == otherBacking ? YES : NO;
    return CFEqual(backing, otherBacking) ? YES : NO;
}

/* A plain object has to supply the value identity CF used to provide while the
 * port was toll-free with it. */
- (BOOL)isEqual:(id)object {
    if (self == object) return YES;
    if (![object isKindOfClass:[NSAttributedString class]]) return NO;
    return [self isEqualToAttributedString:object];
}

- (NSUInteger)hash {
    return CFHash(NSAttributedStringBacking(self));
}

/* Apple hands back the receiver for an immutable attributed string. */
- (id)copyWithZone:(NSZone *)zone {
    return self;
}

- (id)mutableCopyWithZone:(NSZone *)zone {
    CFMutableAttributedStringRef copy = CFAttributedStringCreateMutableCopy(
        kCFAllocatorDefault, 0, NSAttributedStringBacking(self));
    if (copy == NULL) return nil;
    return [[NSMutableAttributedString alloc] _initWithMutableBacking:copy];
}

- (void)enumerateAttributesInRange:(NSRange)enumerationRange
                           options:(NSAttributedStringEnumerationOptions)opts
                        usingBlock:(void (NS_NOESCAPE ^)(NSDictionary<NSAttributedStringKey, id> *attrs,
                                                         NSRange range, BOOL *stop))block {
    if (block == nil) return;
    NSUInteger limit = enumerationRange.location + enumerationRange.length;
    NSUInteger location = enumerationRange.location;
    BOOL reverse = (opts & NSAttributedStringEnumerationReverse) != 0;

    /* Reverse enumeration walks the same runs from the far end, because
     * CoreFoundation has no reverse enumeration entry point of its own. */
    while (location < limit) {
        NSUInteger probe = reverse ? limit - 1 : location;
        NSRange run = NSMakeRange(location, 0);
        NSDictionary *attrs = [self attributesAtIndex:probe
                                 longestEffectiveRange:&run
                                           inRange:NSMakeRange(location, limit - location)];
        BOOL stop = NO;
        block(attrs, run, &stop);
        if (stop) return;
        if (reverse) {
            location = run.location;
            limit = run.location;
        } else {
            location = NSMaxRange(run);
        }
    }
}

- (void)enumerateAttribute:(NSAttributedStringKey)attrName
                   inRange:(NSRange)enumerationRange
                   options:(NSAttributedStringEnumerationOptions)opts
                usingBlock:(void (NS_NOESCAPE ^)(id value, NSRange range, BOOL *stop))block {
    if (block == nil) return;
    NSUInteger limit = enumerationRange.location + enumerationRange.length;
    NSUInteger location = enumerationRange.location;
    BOOL reverse = (opts & NSAttributedStringEnumerationReverse) != 0;

    while (location < limit) {
        NSUInteger probe = reverse ? limit - 1 : location;
        NSRange run = NSMakeRange(location, 0);
        id value = [self attribute:attrName
                           atIndex:probe
                longestEffectiveRange:&run
                              inRange:NSMakeRange(location, limit - location)];
        BOOL stop = NO;
        block(value, run, &stop);
        if (stop) return;
        if (reverse) {
            location = run.location;
            limit = run.location;
        } else {
            location = NSMaxRange(run);
        }
    }
}

@end

/* Apple's -mutableString is not a copy of the current characters: it is a proxy
 * whose edits are written straight back into the attributed string, so that
 * -string on the owner reflects them.  CoreFoundation's
 * CFAttributedStringGetMutableString cannot supply that (it returns NULL for
 * the mutable backings this port builds), so the proxy is implemented here by
 * forwarding every mutating string entry point to the owner. */
@interface NSAttributedStringMutableStringProxy : NSMutableString {
    NSMutableAttributedString *_owner;
}
@end

@implementation NSAttributedStringMutableStringProxy

- (instancetype)initWithOwner:(NSMutableAttributedString *)owner {
    /* NSMutableString is toll-free with CFMutableString, so [super alloc] and
     * the inherited initializers resolve to CoreFoundation rather than to this
     * subclass -- the compiler rejects the former and the latter would hand
     * back a CF instance whose every message lands outside the port.  Allocate
     * the instance directly from the runtime instead; the proxy overrides every
     * accessor and mutator, so it never touches inherited string storage. */
    self = class_createInstance(object_getClass(self), 0);
    if (self != nil) {
        _owner = owner;
    }
    return self;
}

- (NSUInteger)length {
    return [_owner length];
}

- (unichar)characterAtIndex:(NSUInteger)index {
    return [[_owner string] characterAtIndex:index];
}

- (NSString *)substringWithRange:(NSRange)range {
    return [[_owner string] substringWithRange:range];
}

- (const char *)UTF8String {
    return [[_owner string] UTF8String];
}

- (void)getCharacters:(unichar *)buffer range:(NSRange)range {
    [[_owner string] getCharacters:buffer range:range];
}

- (void)insertString:(NSString *)string atIndex:(NSUInteger)location {
    [_owner replaceCharactersInRange:NSMakeRange(location, 0) withString:string];
}

- (void)deleteCharactersInRange:(NSRange)range {
    [_owner deleteCharactersInRange:range];
}

- (void)appendString:(NSString *)string {
    [_owner replaceCharactersInRange:NSMakeRange([_owner length], 0) withString:string];
}

- (void)appendFormat:(NSString *)format, ... {
    va_list args;
    va_start(args, format);
    NSString *text = [[NSString alloc] initWithFormat:format arguments:args];
    va_end(args);
    [self appendString:text];
}

- (void)setString:(NSString *)string {
    [_owner setAttributedString:[[NSAttributedString alloc] initWithString:string]];
}

- (void)replaceCharactersInRange:(NSRange)range withString:(NSString *)string {
    [_owner replaceCharactersInRange:range withString:string];
}

/* -replaceOccurrencesOfString: is a Foundation category method on NSString, so
 * it is inherited here rather than overridden by NSMutableString itself.  Left
 * unimplemented the inherited version would run against the proxy's (absent)
 * CF string storage, so the search-and-replace is driven through the owner.
 * Matches are collected first and then applied back to front, so that removing
 * a later match cannot invalidate the range of an earlier one. */
- (NSUInteger)replaceOccurrencesOfString:(NSString *)target
                              withString:(NSString *)replacement
                                 options:(NSStringCompareOptions)options
                                   range:(NSRange)range {
    NSMutableAttributedString *owner = _owner;
    NSMutableArray<NSValue *> *matches = [NSMutableArray array];
    NSUInteger end = NSMaxRange(range);
    NSUInteger search = range.location;
    while (search < end) {
        /* The owner hands back the characters to search over, so this does not
         * depend on the Foundation string category being present. */
        NSRange found = [owner rangeOfString:target
                                     options:options
                                       range:NSMakeRange(search, end - search)];
        if (found.location == NSNotFound) break;
        [matches addObject:[NSValue valueWithRange:found]];
        search = NSMaxRange(found);
    }
    for (NSValue *boxed in [matches reverseObjectEnumerator]) {
        [owner replaceCharactersInRange:boxed.rangeValue withString:replacement];
    }
    return (NSUInteger)[matches count];
}

@end

@implementation NSMutableAttributedString

- (instancetype)_initWithMutableBacking:(CFMutableAttributedStringRef)backing {
    if (backing == NULL) return nil;
    self = [super _initWithBacking:backing];
    if (self != nil) {
        _mutableAttrString = backing;
    }
    return self;
}

- (void)dealloc {
    _mutableAttrString = NULL;
}

/* -initWithString:attributes: is the primitive here: build the immutable
 * attributed string, promote it to a mutable copy, then release the
 * intermediate.  -initWithString: defers to it with no attributes. */
- (instancetype)initWithString:(NSString *)str {
    return [self initWithString:str attributes:nil];
}

- (instancetype)initWithString:(NSString *)str
                    attributes:(NSDictionary<NSAttributedStringKey, id> *)attrs {
    NSAttributedStringCheckNotNil(self, str, _cmd, @"string");
    CFAttributedStringRef immutable = CFAttributedStringCreate(kCFAllocatorDefault,
                                                               (__bridge CFStringRef)str,
                                                               (__bridge CFDictionaryRef)attrs);
    if (immutable == NULL) return nil;
    CFMutableAttributedStringRef backing =
        CFAttributedStringCreateMutableCopy(kCFAllocatorDefault, 0, immutable);
    CFRelease(immutable);
    if (backing == NULL) return nil;
    return [self _initWithMutableBacking:backing];
}

- (instancetype)initWithAttributedString:(NSAttributedString *)attrStr {
    NSAttributedStringCheckNotNil(self, attrStr, _cmd, @"attributedString");
    return [self _initWithMutableBacking:
        CFAttributedStringCreateMutableCopy(kCFAllocatorDefault, 0,
                                           NSAttributedStringBacking(attrStr))];
}

- (NSMutableString *)mutableString {
    return [[NSAttributedStringMutableStringProxy alloc] initWithOwner:self];
}

- (void)replaceCharactersInRange:(NSRange)range withString:(NSString *)str {
    NSAttributedStringCheckNotNil(self, str, _cmd, @"string");
    NSAttributedStringCheckRange(self, range, _cmd);
    CFAttributedStringReplaceString(_mutableAttrString, NSAttributedStringCFRange(range),
                                    (__bridge CFStringRef)str);
}

- (void)setAttributes:(NSDictionary<NSAttributedStringKey, id> *)attrs range:(NSRange)range {
    NSAttributedStringCheckRange(self, range, _cmd);
    /* Apple documents -setAttributes:range: as a *replacement*, not a merge: an
     * attribute already present in the range and absent from `attrs` is
     * removed.  CFAttributedStringSetAttributes only merges unless
     * clearOtherAttributes is true, so that flag is what carries the
     * documented behaviour.  A nil dictionary clears the range, which CF
     * accepts alongside clearOtherAttributes=true. */
    CFAttributedStringSetAttributes(_mutableAttrString, NSAttributedStringCFRange(range),
                                    (__bridge CFDictionaryRef)attrs, true);
}

- (void)addAttribute:(NSAttributedStringKey)name value:(id)value range:(NSRange)range {
    NSAttributedStringCheckRange(self, range, _cmd);
    /* Unlike -removeAttribute:, Apple treats a nil value as an argument error
     * rather than as a removal. */
    NSAttributedStringCheckNotNil(self, value, _cmd, @"value");
    CFAttributedStringSetAttribute(_mutableAttrString, NSAttributedStringCFRange(range),
                                   (__bridge CFStringRef)name, (__bridge CFTypeRef)value);
}

- (void)addAttributes:(NSDictionary<NSAttributedStringKey, id> *)attrs range:(NSRange)range {
    NSAttributedStringCheckRange(self, range, _cmd);
    for (NSAttributedStringKey key in attrs) {
        CFAttributedStringSetAttribute(_mutableAttrString, NSAttributedStringCFRange(range),
                                       (__bridge CFStringRef)key,
                                       (__bridge CFTypeRef)[attrs objectForKey:key]);
    }
}

- (void)removeAttribute:(NSAttributedStringKey)name range:(NSRange)range {
    NSAttributedStringCheckRange(self, range, _cmd);
    CFAttributedStringRemoveAttribute(_mutableAttrString, NSAttributedStringCFRange(range),
                                      (__bridge CFStringRef)name);
}

- (void)replaceCharactersInRange:(NSRange)range
         withAttributedString:(NSAttributedString *)attrString {
    NSAttributedStringCheckNotNil(self, attrString, _cmd, @"attributedString");
    NSAttributedStringCheckRange(self, range, _cmd);
    CFAttributedStringReplaceAttributedString(_mutableAttrString,
                                               NSAttributedStringCFRange(range),
                                               NSAttributedStringBacking(attrString));
}

- (void)insertAttributedString:(NSAttributedString *)attrString atIndex:(NSUInteger)loc {
    NSAttributedStringCheckNotNil(self, attrString, _cmd, @"attributedString");
    NSAttributedStringCheckRange(self, NSMakeRange(loc, 0), _cmd);
    CFAttributedStringReplaceAttributedString(_mutableAttrString,
                                               CFRangeMake((CFIndex)loc, 0),
                                               NSAttributedStringBacking(attrString));
}

- (void)appendAttributedString:(NSAttributedString *)attrString {
    NSAttributedStringCheckNotNil(self, attrString, _cmd, @"attributedString");
    NSUInteger length = (NSUInteger)CFAttributedStringGetLength(_mutableAttrString);
    CFAttributedStringReplaceAttributedString(_mutableAttrString,
                                               CFRangeMake((CFIndex)length, 0),
                                               NSAttributedStringBacking(attrString));
}

- (void)deleteCharactersInRange:(NSRange)range {
    NSAttributedStringCheckRange(self, range, _cmd);
    /* CFAttributedStringReplaceString segfaults on a NULL replacement, so
     * deletion replaces with the empty string rather than passing NULL. */
    CFAttributedStringReplaceString(_mutableAttrString, NSAttributedStringCFRange(range),
                                    CFSTR(""));
}

- (void)setAttributedString:(NSAttributedString *)attrString {
    NSAttributedStringCheckNotNil(self, attrString, _cmd, @"attributedString");
    /* Clearing first then inserting would need a NULL replacement, which CF
     * does not accept; replacing the whole span in one call avoids it and
     * keeps the original attributes of the incoming string intact. */
    NSUInteger length = (NSUInteger)CFAttributedStringGetLength(_mutableAttrString);
    CFAttributedStringReplaceAttributedString(_mutableAttrString,
                                               CFRangeMake(0, (CFIndex)length),
                                               NSAttributedStringBacking(attrString));
}

/* Search helper for -mutableString's -replaceOccurrencesOfString:.  It goes
 * through CFStringFind directly because the port has no
 * -rangeOfString:options:range: category on NSString yet, and the proxy
 * deliberately is not a real NSString to search. */
- (NSRange)rangeOfString:(NSString *)target
                 options:(NSStringCompareOptions)options
                   range:(NSRange)range {
    CFStringRef haystack = (__bridge CFStringRef)[self string];
    CFStringRef needle = (__bridge CFStringRef)target;
    if (haystack == NULL || needle == NULL) return NSMakeRange(NSNotFound, 0);
    CFRange found = CFRangeMake(0, 0);
    if (!CFStringFindWithOptions(haystack, needle, NSAttributedStringCFRange(range),
                                 (CFStringCompareFlags)options, &found)) {
        return NSMakeRange(NSNotFound, 0);
    }
    return NSMakeRange((NSUInteger)found.location, (NSUInteger)found.length);
}

- (void)beginEditing {
    CFAttributedStringBeginEditing(_mutableAttrString);
}

- (void)endEditing {
    CFAttributedStringEndEditing(_mutableAttrString);
}

/* -copy must yield an immutable string even when the receiver is mutable, and
 * -mutableCopy must yield a distinct mutable string.  Returning self for either
 * would let a later edit through the mutable copy mutate the "immutable" one. */
- (id)copyWithZone:(NSZone *)zone {
    CFAttributedStringRef backing = NSAttributedStringBacking(self);
    if (backing == NULL) return nil;
    return [[NSAttributedString alloc] _initWithBacking:
        CFAttributedStringCreateCopy(kCFAllocatorDefault, backing)];
}

- (id)mutableCopyWithZone:(NSZone *)zone {
    CFAttributedStringRef backing = NSAttributedStringBacking(self);
    if (backing == NULL) return nil;
    return [[NSMutableAttributedString alloc] _initWithMutableBacking:
        CFAttributedStringCreateMutableCopy(kCFAllocatorDefault, 0, backing)];
}

@end