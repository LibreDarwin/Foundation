/*
 * Copyright (C) 2026, Samuel Zormeister.
 *
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */

#import <Foundation/NSString.h>
#import <Foundation/NSCharacterSet.h>
#import <Foundation/NSData.h>
#import <Foundation/NSException.h>
#include <CoreFoundation/CFString.h>
#include <CoreFoundation/CFData.h>
#include <CoreFoundation/CFCharacterSet.h>
#include <stdarg.h>

/* NSStringEncoding and CFStringEncoding are separate numbering schemes; only
 * the two encodings NSString.h declares are mapped. */
static CFStringEncoding
__NSStringCFEncoding(NSStringEncoding encoding)
{
    return (encoding == NSUTF8StringEncoding) ? kCFStringEncodingUTF8
                                              : kCFStringEncodingASCII;
}

/* The file builds under both ARC and MRC. Every CF creation below returns a
 * +1 object; factories hand it to callers at +0 (autoreleased under MRC,
 * bridge-transferred under ARC), while initializers hand it over at +1. */
#if __has_feature(objc_arc)
#define NSSTRING_FACTORY(value)      ((__bridge_transfer id)(value))
#define NSSTRING_INITIALIZED(value)  ((__bridge_transfer id)(value))
#else
#define NSSTRING_FACTORY(value)      [(id)(value) autorelease]
#define NSSTRING_INITIALIZED(value)  ((id)(value))
#endif

/* NSStringCompareOptions carry the same bit values as the kCFCompare* flags,
 * so the two pass straight through. NSLiteralSearch (2) is the default state
 * and has no flag of its own; NSRegularExpressionSearch is accepted here but
 * not implemented. */
static CFStringCompareFlags
__NSStringCompareFlags(NSStringCompareOptions mask)
{
    return (CFStringCompareFlags)mask;
}

static NSComparisonResult
__NSStringFromCFResult(CFComparisonResult result)
{
    if (result == kCFCompareEqualTo) {
        return NSOrderedSame;
    }
    return (result == kCFCompareLessThan) ? NSOrderedAscending : NSOrderedDescending;
}

static void
__NSStringRaiseNil(NSString *method)
{
    [NSException raise:NSInvalidArgumentException
                format:@"%@ called with nil argument", method];
}

@implementation NSString

/* -(substringWithRange:) is an NSCFString cluster primitive, so the index-based
 * substring accessors and the replacing API derive from it and from
 * -(stringByReplacingOccurrencesOfString:withString:) rather than calling down
 * through a second layer of massaging. */
 - (instancetype)initWithFormat:(NSString *)format, ... {
     va_list args;
     va_start(args, format);
     NSString *result = [self initWithFormat:format arguments:args];
     va_end(args);
     return result;
 }

 - (instancetype)initWithFormat:(NSString *)format arguments:(va_list)argList {
     if (format == nil) {
         __NSStringRaiseNil(@"initWithFormat:arguments:");
     }
     CFStringRef result = CFStringCreateWithFormatAndArguments(kCFAllocatorDefault,
                                                               NULL,
                                                               (CFStringRef)format,
                                                               argList);
     return NSSTRING_INITIALIZED(result);
 }

+ (instancetype)stringWithFormat:(NSString *)format, ... {
    va_list args;
    va_start(args, format);
    CFStringRef result = CFStringCreateWithFormatAndArguments(kCFAllocatorDefault,
                                                              NULL,
                                                              (CFStringRef)format,
                                                              args);
    va_end(args);
    return NSSTRING_FACTORY(result);
}

- (NSString *)stringByAppendingFormat:(NSString *)format, ... {
    if (format == nil) {
        __NSStringRaiseNil(@"stringByAppendingFormat:");
    }
    va_list args;
    va_start(args, format);
    CFStringRef formatted = CFStringCreateWithFormatAndArguments(kCFAllocatorDefault,
                                                                  NULL,
                                                                  (CFStringRef)format,
                                                                  args);
    va_end(args);
    CFMutableStringRef result = CFStringCreateMutableCopy(kCFAllocatorDefault,
                                                          0,
                                                          (CFStringRef)self);
    CFStringAppend(result, formatted);
    CFRelease(formatted);
    return NSSTRING_FACTORY(result);
}

- (NSArray *)componentsSeparatedByString:(NSString *)separator {
    if (separator == nil) {
        __NSStringRaiseNil(@"componentsSeparatedByString:");
    }
    CFArrayRef array = CFStringCreateArrayBySeparatingStrings(kCFAllocatorDefault,
                                                              (CFStringRef)self,
                                                              (CFStringRef)separator);
    /* The array and its elements are one +1 unit: CF's array callbacks retain
     * each element on insert in return for the separator call's +1, so a single
     * transfer hands the caller a fully-owned array. */
    return NSARRAY_FACTORY(array);
}

- (NSString *)stringByReplacingCharactersInRange:(NSRange)range
                                       withString:(NSString *)replacement {
    if (replacement == nil) {
        __NSStringRaiseNil(@"stringByReplacingCharactersInRange:withString:");
    }
    if (range.location > NSUIntegerMax - range.length ||
        range.location + range.length > [self length]) {
        [NSException raise:NSRangeException
                    format:@"*** -[NSString stringByReplacingCharactersInRange:withString:]: "
                           @"range {%lu, %lu} extends beyond the string's bounds {%lu, %lu}",
                           (unsigned long)range.location, (unsigned long)range.length,
                           (unsigned long)0, (unsigned long)[self length]];
    }
    CFMutableStringRef result = CFStringCreateMutableCopy(kCFAllocatorDefault,
                                                          0,
                                                          (CFStringRef)self);
    CFStringReplace(result, CFRangeMake((CFIndex)range.location, (CFIndex)range.length),
                    (CFStringRef)replacement);
    return NSSTRING_FACTORY(result);
}

- (NSString *)substringFromIndex:(NSUInteger)from {
    return [self substringWithRange:NSMakeRange(from, [self length] - from)];
}

- (NSString *)substringToIndex:(NSUInteger)to {
    return [self substringWithRange:NSMakeRange(0, to)];
}

 + (instancetype)stringWithUTF8String:(const char *)utf8String {
    return [[self alloc] initWithUTF8String:utf8String];
}

+ (instancetype)stringWithCharacters:(const unichar *)characters length:(NSUInteger)length {
    if (characters == NULL && length != 0) {
        __NSStringRaiseNil(@"stringWithCharacters:length:");
    }
    CFStringRef result = CFStringCreateWithCharacters(kCFAllocatorDefault,
                                                       (const UniChar *)characters,
                                                       (CFIndex)length);
    return NSSTRING_FACTORY(result);
}

+ (instancetype)stringWithFormat:(NSString *)format, ... {
    va_list args;
    va_start(args, format);
    CFStringRef result = CFStringCreateWithFormatAndArguments(kCFAllocatorDefault, NULL, (CFStringRef)format, args);
    va_end(args);
    return NSSTRING_FACTORY(result);
}

- (instancetype)initWithUTF8String:(const char *)utf8String {
    CFStringRef result = CFStringCreateWithCString(kCFAllocatorDefault, utf8String, kCFStringEncodingUTF8);
    return NSSTRING_INITIALIZED(result);
}

- (instancetype)initWithBytes:(const void *)bytes
                       length:(NSUInteger)length
                     encoding:(NSStringEncoding)encoding {
    /* Returns nil when the bytes are not valid in the encoding, which callers
     * decoding untrusted input rely on to detect a malformed string. */
    CFStringRef result = CFStringCreateWithBytes(kCFAllocatorDefault,
                                                 (const UInt8 *)bytes,
                                                 (CFIndex)length,
                                                 __NSStringCFEncoding(encoding),
                                                 false);
    return NSSTRING_INITIALIZED(result);
}

- (NSData *)dataUsingEncoding:(NSStringEncoding)encoding {
    CFDataRef result = CFStringCreateExternalRepresentation(kCFAllocatorDefault,
                                                            (CFStringRef)self,
                                                            __NSStringCFEncoding(encoding),
                                                            0);
    if (result == NULL) {
        return nil;
    }
    return (__bridge NSData *)CFAutorelease(result);
}

- (BOOL)isEqualToString:(NSString *)aString {
    if (aString == nil) {
        return NO;
    }
    return CFStringCompare((CFStringRef)self, (CFStringRef)aString, 0) == kCFCompareEqualTo;
}

- (BOOL)hasPrefix:(NSString *)aString {
    if (aString == nil) {
        __NSStringRaiseNil(@"hasPrefix:");
    }
    return CFStringHasPrefix((CFStringRef)self, (CFStringRef)aString);
}

- (BOOL)hasSuffix:(NSString *)aString {
    if (aString == nil) {
        __NSStringRaiseNil(@"hasSuffix:");
    }
    return CFStringHasSuffix((CFStringRef)self, (CFStringRef)aString);
}

- (BOOL)containsString:(NSString *)aString {
    return [self rangeOfString:aString options:0].location != NSNotFound;
}

- (NSComparisonResult)compare:(NSString *)string {
    return [self compare:string options:0 range:NSMakeRange(0, [self length])];
}

- (NSComparisonResult)compare:(NSString *)string options:(NSStringCompareOptions)mask {
    return [self compare:string options:mask range:NSMakeRange(0, [self length])];
}

- (NSComparisonResult)compare:(NSString *)string
                      options:(NSStringCompareOptions)mask
                        range:(NSRange)range {
    if (string == nil) {
        __NSStringRaiseNil(@"compare:options:range:");
    }
    CFComparisonResult result = CFStringCompareWithOptions((CFStringRef)self,
                                                           (CFStringRef)string,
                                                           CFRangeMake((CFIndex)range.location, (CFIndex)range.length),
                                                           __NSStringCompareFlags(mask));
    return __NSStringFromCFResult(result);
}

- (NSComparisonResult)caseInsensitiveCompare:(NSString *)string {
    return [self compare:string options:NSCaseInsensitiveSearch];
}

- (NSRange)rangeOfString:(NSString *)aString {
    return [self rangeOfString:aString options:0];
}

- (NSRange)rangeOfString:(NSString *)aString options:(NSStringCompareOptions)mask {
    if (aString == nil) {
        __NSStringRaiseNil(@"rangeOfString:options:");
    }
    CFRange found = CFStringFind((CFStringRef)self, (CFStringRef)aString,
                                 __NSStringCompareFlags(mask));
    if (found.location == kCFNotFound) {
        return NSMakeRange(NSNotFound, 0);
    }
    return NSMakeRange((NSUInteger)found.location, (NSUInteger)found.length);
}

- (NSString *)stringByAppendingString:(NSString *)aString {
    if (aString == nil) {
        __NSStringRaiseNil(@"stringByAppendingString:");
    }
    CFMutableStringRef result = CFStringCreateMutableCopy(kCFAllocatorDefault, 0, (CFStringRef)self);
    CFStringAppend(result, (CFStringRef)aString);
    return NSSTRING_FACTORY(result);
}

- (NSString *)lowercaseString {
    CFMutableStringRef result = CFStringCreateMutableCopy(kCFAllocatorDefault, 0, (CFStringRef)self);
    CFStringLowercase(result, NULL);
    return NSSTRING_FACTORY(result);
}

- (NSString *)uppercaseString {
    CFMutableStringRef result = CFStringCreateMutableCopy(kCFAllocatorDefault, 0, (CFStringRef)self);
    CFStringUppercase(result, NULL);
    return NSSTRING_FACTORY(result);
}

- (NSString *)stringByTrimmingCharactersInSet:(NSCharacterSet *)set {
    if (set == nil) {
        __NSStringRaiseNil(@"stringByTrimmingCharactersInSet:");
    }
    CFIndex length = CFStringGetLength((CFStringRef)self);
    if (length == 0) {
        return NSSTRING_FACTORY(CFStringCreateWithCString(kCFAllocatorDefault, "", kCFStringEncodingUTF8));
    }
    /* Trim is symmetric: the result is the span between the first character not
     * in the set and the last character not in the set. Searching for non-members
     * beats walking members, because on a fully-covering set the member search
     * would run off the end of the string. */
    CFCharacterSetRef nonMembers = CFCharacterSetCreateInvertedSet(kCFAllocatorDefault,
                                                                   (CFCharacterSetRef)set);
    CFRange range = CFRangeMake(0, length);
    CFRange probe = CFRangeMake(0, 0);
    CFStringFindCharacterFromSet((CFStringRef)self, nonMembers, range, 0, &probe);
    if (probe.location == kCFNotFound) {
        /* Every character is a member: the whole string trims away. */
        CFRelease(nonMembers);
        return NSSTRING_FACTORY(CFStringCreateWithCString(kCFAllocatorDefault, "", kCFStringEncodingUTF8));
    }
    CFIndex left = probe.location;
    probe = CFRangeMake(0, 0);
    CFStringFindCharacterFromSet((CFStringRef)self, nonMembers, range, kCFCompareBackwards, &probe);
    CFIndex right = probe.location + 1;
    CFRelease(nonMembers);
    CFStringRef result = CFStringCreateWithSubstring(kCFAllocatorDefault, (CFStringRef)self,
                                                     CFRangeMake(left, right - left));
    return NSSTRING_FACTORY(result);
}

- (NSString *)stringByReplacingOccurrencesOfString:(NSString *)target
                                        withString:(NSString *)replacement {
    if (target == nil || replacement == nil) {
        __NSStringRaiseNil(@"stringByReplacingOccurrencesOfString:withString:");
    }
    CFMutableStringRef result = CFStringCreateMutableCopy(kCFAllocatorDefault, 0, (CFStringRef)self);
    CFStringFindAndReplace(result, (CFStringRef)target, (CFStringRef)replacement,
                           CFRangeMake(0, CFStringGetLength(result)),
                           __NSStringCompareFlags(NSLiteralSearch));
    return NSSTRING_FACTORY(result);
}

@end

/* CFStringCreateMutable takes maxLength, not a capacity hint: a non-zero value
 * is a hard limit on the string's length. NSMutableString has no such limit, so
 * the requested capacity is only a hint and 0 is passed through. */
@implementation NSMutableString

+ (instancetype)string {
    return [self stringWithCapacity:0];
}

+ (instancetype)stringWithCapacity:(NSUInteger)capacity {
    (void)capacity;
    CFMutableStringRef result = CFStringCreateMutable(kCFAllocatorDefault, 0);
    return NSSTRING_FACTORY(result);
}

- (void)appendString:(NSString *)string {
    CFStringAppend((CFMutableStringRef)self, (CFStringRef)string);
}

- (void)appendFormat:(NSString *)format, ... {
    va_list args;
    va_start(args, format);
    CFStringAppendFormatAndArguments((CFMutableStringRef)self, NULL,
                                     (CFStringRef)format, args);
    va_end(args);
}

- (void)setString:(NSString *)string {
    CFStringReplaceAll((CFMutableStringRef)self, (CFStringRef)string);
}

@end