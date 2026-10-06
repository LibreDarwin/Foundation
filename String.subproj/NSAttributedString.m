/*
 * Copyright (C) 2026, Samuel Zormeister.
 *
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */

#import <Foundation/NSAttributedString.h>
#import <Foundation/NSArray.h>
#import <Foundation/NSCoder.h>
#import <Foundation/NSData.h>
#import <Foundation/NSEnumerator.h>
#import <Foundation/NSException.h>
#import <Foundation/NSNumber.h>
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
 * an exception.
 *
 * These helpers only read their object arguments before raising, so they borrow
 * them.  Declaring them __strong would make ARC retain on entry and schedule the
 * release for the function's normal exit; the raise never reaches that release,
 * so the caller's object would be left one reference too heavy.  On the out-of-
 * bounds path that leaked the receiving attributed string on every raise (~100
 * bytes per call, unbounded) because the caller creates one per iteration and it
 * is the parameter's retain -- not ARC's release at the caller's own scope
 * -- that would have to balance.
 *
 * The class and selector names in the message are formatted from C strings with
 * %s rather than from NSStringFromClass and NSStringFromSelector with %@.  Those
 * two return autoreleased objects, and Objective-C sources are not compiled with
 * -fobjc-arc-exceptions, so ARC has no cleanup to run when the raise unwinds this
 * frame.  Handing the results straight to the format leaks them (ARC claims the
 * autorelease and nobody releases: two CFStrings per raise, unbounded over a loop
 * of range checks); parking them in a __unsafe_unretained local is worse -- ARC
 * claims and then immediately balances the value, leaving the local pointing at
 * freed memory by the time the format runs.  class_getName and sel_getName hand
 * back C strings owned by the runtime and produce byte-identical text. */
static void NSAttributedStringCheckNotNil(NSAttributedString * __unsafe_unretained s,
                                          id __unsafe_unretained object,
                                          SEL selector,
                                          NSString * __unsafe_unretained argument) {
    if (object == nil) {
        [NSException raise:NSInvalidArgumentException
                    format:@"*** -[%s %s]: %@ argument cannot be nil",
                           class_getName([s class]), sel_getName(selector), argument];
    }
}

static void NSAttributedStringCheckRange(NSAttributedString * __unsafe_unretained s,
                                         NSRange range, SEL selector) {
    NSUInteger length = (NSUInteger)CFAttributedStringGetLength(NSAttributedStringBacking(s));
    if (range.location > NSUIntegerMax - range.length ||
        range.location + range.length > length) {
        [NSException raise:NSRangeException
                    format:@"*** -[%s %s]: range {%lu, %lu} extends beyond the string's bounds {%lu, %lu}",
                           class_getName([s class]), sel_getName(selector),
                           (unsigned long)range.location, (unsigned long)range.length,
                           (unsigned long)0, (unsigned long)length];
    }
}

/* ---- NSCoding ---- */
/* Apple's keyed archive of an attributed string carries:
 *   NSString        the backing characters
 *   NSAttributes    one NSDictionary per attribute run, in run order; a bare
 *                   run is an empty dictionary rather than a missing entry
 *   NSAttributeInfo an NSData of LEB128 (runLength, attributeIndex) pairs,
 *                   where the index selects an entry of NSAttributes.  The
 *                   key is omitted when there is at most one run, in which
 *                   case the single NSAttributes entry applies to the whole
 *                   string, or to nothing at all when the string is empty.
 * The blob is what lets one dictionary object serve several disjoint runs, and
 * what tells the decoder where each run ends without walking the string. */

static void NSAttributedStringAppendLEB128(NSMutableData *data, uint32_t value) {
    do {
        uint8_t byte = (uint8_t)(value & 0x7f);
        value >>= 7;
        if (value != 0) byte |= 0x80;
        [data appendBytes:&byte length:1];
    } while (value != 0);
}

static BOOL NSAttributedStringReadLEB128(const uint8_t *bytes, NSUInteger length,
                                        NSUInteger *cursor, uint32_t *valueOut) {
    uint32_t value = 0;
    unsigned shift = 0;
    while (*cursor < length && shift <= 28) {
        uint8_t byte = bytes[(*cursor)++];
        value |= ((uint32_t)(byte & 0x7f)) << shift;
        if ((byte & 0x80) == 0) {
            *valueOut = value;
            return YES;
        }
        shift += 7;
    }
    return NO;
}

/* Decode an archived attributed string into a new +1 CF backing.  The whole
 * archive is validated before the backing is created, so a raise on a malformed
 * archive cannot strand a half-built CF object: Objective-C sources here are not
 * compiled with -fobjc-arc-exceptions, so there is no cleanup to run when the
 * raise unwinds this frame. */
static CFMutableAttributedStringRef NSAttributedStringBackingFromCoder(NSCoder *coder,
                                                                       Class cls) {
    NSString *archiveString = [coder decodeObjectOfClass:[NSString class] forKey:@"NSString"];
    if (archiveString != nil && ![archiveString isKindOfClass:[NSString class]]) {
        [NSException raise:NSInvalidArgumentException
                    format:@"*** -[%s initWithCoder:]: the NSString entry is not a string",
                           class_getName(cls)];
    }
    /* A missing string is an empty string rather than a rejection: the run
     * table then has nothing to apply either. */
    NSString *string = archiveString ?: @"";

    NSArray *archiveAttributes = [coder decodeObjectOfClass:[NSArray class] forKey:@"NSAttributes"];
    if (archiveAttributes == nil) archiveAttributes = [NSArray array];
    if (![archiveAttributes isKindOfClass:[NSArray class]]) {
        [NSException raise:NSInvalidArgumentException
                    format:@"*** -[%s initWithCoder:]: the NSAttributes entry is not an array",
                           class_getName(cls)];
    }
    NSArray * __unsafe_unretained attributes = archiveAttributes;
    NSUInteger attributeCount = [attributes count];
    NSUInteger stringLength = [string length];

    NSData *archiveBlob = [coder decodeObjectOfClass:[NSData class] forKey:@"NSAttributeInfo"];
    if (archiveBlob != nil && ![archiveBlob isKindOfClass:[NSData class]]) {
        [NSException raise:NSInvalidArgumentException
                    format:@"*** -[%s initWithCoder:]: the NSAttributeInfo entry is not data",
                           class_getName(cls)];
    }
    NSData * __unsafe_unretained blob = archiveBlob;

    /* Expand the run table now, while nothing but autoreleased Foundation
     * objects is held, so every archive-shape error raises before CF is
     * entered and before any +1 reference is taken. */
    NSMutableArray *ranges = [NSMutableArray array];
    NSMutableArray *indices = [NSMutableArray array];
    if (blob == nil) {
        /* One run covering the whole string, or none at all. */
        if (attributeCount == 1 && stringLength > 0) {
            [ranges addObject:[NSValue valueWithRange:NSMakeRange(0, stringLength)]];
            [indices addObject:[NSNumber numberWithUnsignedInteger:(NSUInteger)0]];
        }
    } else if (stringLength == 0) {
        /* A run table for a zero-length string has nothing to apply. */
    } else {
        const uint8_t *bytes = [blob bytes];
        NSUInteger byteCount = [blob length];
        NSUInteger cursor = 0;
        NSUInteger location = 0;
        while (location < stringLength) {
            uint32_t runLength = 0;
            uint32_t attributeIndex = 0;
            if (!NSAttributedStringReadLEB128(bytes, byteCount, &cursor, &runLength) ||
                !NSAttributedStringReadLEB128(bytes, byteCount, &cursor, &attributeIndex) ||
                runLength == 0 ||
                (NSUInteger)runLength > stringLength - location ||
                (NSUInteger)attributeIndex >= attributeCount) {
                [NSException raise:NSInvalidArgumentException
                            format:@"*** -[%s initWithCoder:]: the NSAttributeInfo run table does not describe the string",
                                   class_getName(cls)];
            }
            [ranges addObject:[NSValue valueWithRange:NSMakeRange(location, (NSUInteger)runLength)]];
            [indices addObject:[NSNumber numberWithUnsignedInteger:(NSUInteger)attributeIndex]];
            location += (NSUInteger)runLength;
        }
        /* Trailing bytes would mean Apple and this port disagree about the run
         * layout, which is worth failing on rather than silently ignoring. */
        if (cursor != byteCount) {
            [NSException raise:NSInvalidArgumentException
                        format:@"*** -[%s initWithCoder:]: the NSAttributeInfo run table has %lu trailing bytes",
                               class_getName(cls), (unsigned long)(byteCount - cursor)];
        }
    }

    CFMutableAttributedStringRef backing =
        CFAttributedStringCreateMutable(kCFAllocatorDefault, 0);
    if (backing == NULL) {
        [NSException raise:NSMallocException
                    format:@"*** -[%s initWithCoder:]: could not allocate the backing store",
                           class_getName(cls)];
    }
    /* The freshly created mutable backing is empty, and this port's vendored
     * header does not expose CFAttributedStringSetString, so the archived
     * characters go in through the replacement entry point the same way the
     * delete path uses it. */
    CFAttributedStringReplaceString(backing, CFRangeMake(0, 0),
                                    (__bridge CFStringRef)string);
    NSUInteger runCount = [ranges count];
    for (NSUInteger i = 0; i < runCount; i++) {
        NSUInteger attributeIndex =
            (NSUInteger)[[indices objectAtIndex:i] unsignedIntegerValue];
        NSDictionary *attrs = [attributes objectAtIndex:attributeIndex];
        /* Let CoreFoundation merge any adjacent run that carries the same
         * dictionary, so the decoded layout is maximal the same way Apple's
         * is. */
        CFAttributedStringSetAttributes(backing,
                                        NSAttributedStringCFRange([[ranges objectAtIndex:i] rangeValue]),
                                        (__bridge CFDictionaryRef)attrs, true);
    }
    return backing;
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

+ (BOOL)supportsSecureCoding {
    return YES;
}

/* Encode one entry per attribute run, then a run table that says how those
 * entries are laid out.  -enumerateAttributesInRange:options:usingBlock: walks
 * maximal runs, so an attribute dictionary that covers several disjoint places
 * is recorded once and referenced by more than one run length. */
- (void)encodeWithCoder:(NSCoder *)coder {
    NSMutableArray *table = [NSMutableArray array];
    NSMutableArray *runLengths = [NSMutableArray array];
    NSUInteger length = CFAttributedStringGetLength(NSAttributedStringBacking(self));
    [self enumerateAttributesInRange:NSMakeRange(0, length)
                            options:0
                         usingBlock:^(NSDictionary<NSAttributedStringKey, id> *attrs,
                                      NSRange range, BOOL *stop) {
        (void)stop;
        /* The port has no indexOfObject:, and equality is what matters: two
         * dictionaries that isEqual: may share one NSAttributes entry. */
        BOOL known = NO;
        NSUInteger tableCount = [table count];
        for (NSUInteger k = 0; k < tableCount; k++) {
            if ([[table objectAtIndex:k] isEqual:attrs]) {
                known = YES;
                break;
            }
        }
        if (!known) [table addObject:attrs];
        [runLengths addObject:[NSNumber numberWithUnsignedInteger:range.length]];
    }];

    NSString *string = self.string;
    if (string == nil) string = @"";
    [coder encodeObject:string forKey:@"NSString"];
    [coder encodeObject:table forKey:@"NSAttributes"];

    NSUInteger runCount = [runLengths count];
    /* Apple omits NSAttributeInfo when there is at most one run: the single
     * NSAttributes entry, if any, then applies to the whole string. */
    if (runCount <= 1) return;

    NSMutableData *blob = [NSMutableData data];
    for (NSUInteger i = 0; i < runCount; i++) {
        NSAttributedStringAppendLEB128(blob, (uint32_t)[[runLengths objectAtIndex:i] unsignedIntegerValue]);
        NSAttributedStringAppendLEB128(blob, (uint32_t)i);
    }
    [coder encodeObject:blob forKey:@"NSAttributeInfo"];
}

- (instancetype)initWithCoder:(NSCoder *)coder {
    return [self _initWithBacking:NSAttributedStringBackingFromCoder(coder, [NSAttributedString class])];
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

/* Decodes into a mutable backing directly rather than decoding an immutable
 * string and copying it, so the archive is read once.  The shared decoder
 * already builds a CFMutableAttributedStringRef, which is exactly what
 * -_initWithMutableBacking: adopts. */
- (instancetype)initWithCoder:(NSCoder *)coder {
    return [self _initWithMutableBacking:
        NSAttributedStringBackingFromCoder(coder, [NSMutableAttributedString class])];
}

@end