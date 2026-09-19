/*
 * Copyright (C) 2026, PureDarwin Project.
 *
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 *
 * The scanner state machine is adapted from Cocotron Foundation's
 * NSScanner implementation by Christopher J. W. Lloyd and Markus Hitter,
 * used under its MIT license. The original implementation is kept at
 * local/ravynos/Frameworks/Foundation/NSScanner.
 */

#import <Foundation/NSScanner.h>
#include <CoreFoundation/CFString.h>
#include <ctype.h>
#include <errno.h>
#include <limits.h>
#include <math.h>
#include <stdlib.h>

static unichar _NSScannerFold(unichar c) {
    if (c >= 'A' && c <= 'Z') {
        return (unichar)(c + ('a' - 'A'));
    }
    return c;
}

static BOOL _NSScannerMatches(NSString *source, NSUInteger location,
                              NSString *pattern, BOOL caseSensitive) {
    NSUInteger length = [pattern length];
    if (location + length > [source length]) {
        return NO;
    }
    for (NSUInteger i = 0; i < length; i++) {
        unichar left = [source characterAtIndex:location + i];
        unichar right = [pattern characterAtIndex:i];
        if (!caseSensitive) {
            left = _NSScannerFold(left);
            right = _NSScannerFold(right);
        }
        if (left != right) {
            return NO;
        }
    }
    return YES;
}

static NSUInteger _NSScannerSkip(NSScanner *scanner, NSUInteger location) {
    NSCharacterSet *set = scanner.charactersToBeSkipped;
    NSUInteger length = [scanner.string length];
    while (location < length && set != nil &&
           [set characterIsMember:[scanner.string characterAtIndex:location]]) {
        location++;
    }
    return location;
}

static NSString *_NSScannerString(NSString *source, NSUInteger start, NSUInteger end) {
    if (end <= start) {
        return [NSString stringWithCharacters:NULL length:0];
    }
    NSUInteger length = end - start;
    unichar *characters = (unichar *)malloc(length * sizeof(*characters));
    if (characters == NULL) {
        return nil;
    }
    [source getCharacters:characters range:NSMakeRange(start, length)];
    NSString *result = [NSString stringWithCharacters:characters length:length];
    free(characters);
    return result;
}

@implementation NSScanner

+ (instancetype)scannerWithString:(NSString *)string {
    NSScanner *scanner = [[self alloc] initWithString:string];
#if !__has_feature(objc_arc)
    return [scanner autorelease];
#else
    return scanner;
#endif
}

+ (instancetype)localizedScannerWithString:(NSString *)string {
    return [self scannerWithString:string];
}

- (instancetype)initWithString:(NSString *)string {
    self = [super init];
    if (self != nil) {
#if __has_feature(objc_arc)
        _string = [string copy];
        _charactersToBeSkipped = [[NSCharacterSet whitespaceAndNewlineCharacterSet] copy];
#else
        _string = [string copy];
        _charactersToBeSkipped = [[NSCharacterSet whitespaceAndNewlineCharacterSet] retain];
#endif
        _scanLocation = 0;
        _caseSensitive = NO;
    }
    return self;
}

- (id)copyWithZone:(NSZone *)zone {
    NSScanner *copy = [[[self class] allocWithZone:zone] initWithString:_string];
    copy.scanLocation = _scanLocation;
    copy.caseSensitive = _caseSensitive;
    copy.charactersToBeSkipped = _charactersToBeSkipped;
    copy.locale = _locale;
    return copy;
}

- (NSString *)string { return _string; }
- (NSUInteger)scanLocation { return _scanLocation; }
- (void)setScanLocation:(NSUInteger)location { _scanLocation = location; }
- (NSCharacterSet *)charactersToBeSkipped { return _charactersToBeSkipped; }
- (BOOL)caseSensitive { return _caseSensitive; }
- (id)locale { return _locale; }

- (void)setCharactersToBeSkipped:(NSCharacterSet *)set {
#if __has_feature(objc_arc)
    _charactersToBeSkipped = [set copy];
#else
    [_charactersToBeSkipped release];
    _charactersToBeSkipped = [set copy];
#endif
}

- (void)setCaseSensitive:(BOOL)value { _caseSensitive = value; }

- (void)setLocale:(id)value {
#if __has_feature(objc_arc)
    _locale = value;
#else
    [_locale release];
    _locale = [value retain];
#endif
}

- (BOOL)isAtEnd {
    return _NSScannerSkip(self, _scanLocation) >= [_string length];
}

- (BOOL)scanLongLong:(long long *)result {
    NSUInteger start = _NSScannerSkip(self, _scanLocation);
    NSUInteger location = start;
    NSUInteger length = [_string length];
    BOOL negative = NO;
    if (location < length && ([_string characterAtIndex:location] == '+' ||
                              [_string characterAtIndex:location] == '-')) {
        negative = [_string characterAtIndex:location] == '-';
        location++;
    }
    NSUInteger digits = location;
    unsigned long long value = 0;
    unsigned long long limit = negative ? ((unsigned long long)LLONG_MAX + 1ULL)
                                        : (unsigned long long)LLONG_MAX;
    BOOL overflow = NO;
    while (location < length) {
        unichar c = [_string characterAtIndex:location];
        if (c < '0' || c > '9') break;
        unsigned digit = (unsigned)(c - '0');
        if (value > (limit - digit) / 10ULL) {
            overflow = YES;
        } else if (!overflow) {
            value = value * 10ULL + digit;
        }
        location++;
    }
    if (location == digits) return NO;
    _scanLocation = location;
    if (result != NULL) {
        if (overflow) {
            *result = negative ? LLONG_MIN : LLONG_MAX;
        } else if (negative) {
            *result = value == ((unsigned long long)LLONG_MAX + 1ULL)
                ? LLONG_MIN : -(long long)value;
        } else {
            *result = (long long)value;
        }
    }
    return YES;
}

- (BOOL)scanInt:(int *)result {
    long long value;
    if (![self scanLongLong:&value]) return NO;
    if (result != NULL) {
        *result = value > INT_MAX ? INT_MAX : value < INT_MIN ? INT_MIN : (int)value;
    }
    return YES;
}

- (BOOL)scanInteger:(NSInteger *)result {
    long long value;
    if (![self scanLongLong:&value]) return NO;
    if (result != NULL) {
        *result = value > NSIntegerMax ? NSIntegerMax :
                  value < NSIntegerMin ? NSIntegerMin : (NSInteger)value;
    }
    return YES;
}

- (BOOL)scanUnsignedLongLong:(unsigned long long *)result {
    NSUInteger start = _NSScannerSkip(self, _scanLocation);
    NSUInteger location = start;
    NSUInteger length = [_string length];
    if (location < length && [_string characterAtIndex:location] == '+') location++;
    NSUInteger digits = location;
    unsigned long long value = 0;
    BOOL overflow = NO;
    while (location < length) {
        unichar c = [_string characterAtIndex:location];
        if (c < '0' || c > '9') break;
        unsigned digit = (unsigned)(c - '0');
        if (value > (ULLONG_MAX - digit) / 10ULL) overflow = YES;
        else if (!overflow) value = value * 10ULL + digit;
        location++;
    }
    if (location == digits) return NO;
    _scanLocation = location;
    if (result != NULL) *result = overflow ? ULLONG_MAX : value;
    return YES;
}

- (BOOL)scanDouble:(double *)result {
    NSUInteger start = _NSScannerSkip(self, _scanLocation);
    NSUInteger location = start;
    NSUInteger length = [_string length];
    char *buffer = (char *)malloc((length - start + 1) * sizeof(*buffer));
    if (buffer == NULL) return NO;
    NSUInteger count = 0;
    while (location < length) {
        unichar c = [_string characterAtIndex:location];
        if ((c >= '0' && c <= '9') || c == '+' || c == '-' || c == '.' ||
            c == 'e' || c == 'E' || c == 'x' || c == 'X' ||
            (c >= 'a' && c <= 'f') || (c >= 'A' && c <= 'F') || c == 'p' || c == 'P') {
            buffer[count++] = (char)c;
            location++;
        } else break;
    }
    buffer[count] = '\0';
    if (count == 0) { free(buffer); return NO; }
    char *end = NULL;
    errno = 0;
    double value = strtod(buffer, &end);
    if (end == buffer) { free(buffer); return NO; }
    _scanLocation = start + (NSUInteger)(end - buffer);
    free(buffer);
    if (result != NULL) *result = value;
    return YES;
}

- (BOOL)scanFloat:(float *)result {
    double value;
    if (![self scanDouble:&value]) return NO;
    if (result != NULL) *result = (float)value;
    return YES;
}

- (BOOL)scanHexLongLong:(unsigned long long *)result {
    NSUInteger location = _NSScannerSkip(self, _scanLocation);
    NSUInteger length = [_string length];
    if (location + 2 <= length && [_string characterAtIndex:location] == '0' &&
        ([_string characterAtIndex:location + 1] == 'x' || [_string characterAtIndex:location + 1] == 'X')) {
        location += 2;
    }
    NSUInteger digits = location;
    unsigned long long value = 0;
    BOOL overflow = NO;
    while (location < length) {
        unichar c = [_string characterAtIndex:location];
        unsigned digit;
        if (c >= '0' && c <= '9') digit = c - '0';
        else if (c >= 'a' && c <= 'f') digit = c - 'a' + 10;
        else if (c >= 'A' && c <= 'F') digit = c - 'A' + 10;
        else break;
        if (value > (ULLONG_MAX - digit) / 16ULL) overflow = YES;
        else if (!overflow) value = value * 16ULL + digit;
        location++;
    }
    if (location == digits) return NO;
    _scanLocation = location;
    if (result != NULL) *result = overflow ? ULLONG_MAX : value;
    return YES;
}

- (BOOL)scanHexInt:(unsigned *)result {
    unsigned long long value;
    if (![self scanHexLongLong:&value]) return NO;
    if (result != NULL) *result = value > UINT_MAX ? UINT_MAX : (unsigned)value;
    return YES;
}

- (BOOL)scanHexDouble:(double *)result {
    return [self scanDouble:result];
}

- (BOOL)scanHexFloat:(float *)result {
    return [self scanFloat:result];
}

- (BOOL)scanString:(NSString *)string intoString:(NSString **)result {
    NSUInteger start = _NSScannerSkip(self, _scanLocation);
    if (!_NSScannerMatches(_string, start, string, _caseSensitive)) return NO;
    _scanLocation = start + [string length];
    if (result != NULL) *result = string;
    return YES;
}

- (BOOL)scanCharactersFromSet:(NSCharacterSet *)set intoString:(NSString **)result {
    NSUInteger start = _NSScannerSkip(self, _scanLocation);
    NSUInteger location = start;
    while (location < [_string length] &&
           [set characterIsMember:[_string characterAtIndex:location]]) location++;
    if (location == start) return NO;
    _scanLocation = location;
    if (result != NULL) *result = _NSScannerString(_string, start, location);
    return YES;
}

- (BOOL)scanUpToString:(NSString *)string intoString:(NSString **)result {
    NSUInteger start = _NSScannerSkip(self, _scanLocation);
    NSUInteger location = start;
    while (location < [_string length] &&
           !_NSScannerMatches(_string, location, string, _caseSensitive)) location++;
    if (location == start) return NO;
    _scanLocation = location;
    if (result != NULL) *result = _NSScannerString(_string, start, location);
    return YES;
}

- (BOOL)scanUpToCharactersFromSet:(NSCharacterSet *)set intoString:(NSString **)result {
    NSUInteger start = _NSScannerSkip(self, _scanLocation);
    NSUInteger location = start;
    while (location < [_string length] &&
           ![set characterIsMember:[_string characterAtIndex:location]]) location++;
    if (location == start) return NO;
    _scanLocation = location;
    if (result != NULL) *result = _NSScannerString(_string, start, location);
    return YES;
}

- (void)dealloc {
#if !__has_feature(objc_arc)
    [_string release];
    [_charactersToBeSkipped release];
    [_locale release];
    [super dealloc];
#endif
}

@end
