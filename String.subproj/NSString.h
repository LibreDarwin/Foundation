/*
 * Copyright (C) 2026, Samuel Zormeister.
 *
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */

#ifndef NSString_h
#define NSString_h

#import <Foundation/NSObject.h>
#import <Foundation/NSRange.h>

@class NSData;
@class NSCharacterSet;
@class NSArray;

typedef unsigned short unichar;

typedef NS_OPTIONS(NSUInteger, NSStringEncodingConversionOptions) {
    NSStringEncodingConversionExternalRepresentation = 1,
    NSStringEncodingConversionAllowLossy = 2,
};

typedef NS_ENUM(NSUInteger, NSStringEncoding) {
    NSASCIIStringEncoding = 1,
    NSNEXTSTEPStringEncoding = 2,
    NSJapaneseEUCStringEncoding = 3,
    NSUTF8StringEncoding = 4,
    NSISOLatin1StringEncoding = 5,
    NSSymbolStringEncoding = 6,
    NSNonLossyASCIIStringEncoding = 7,
    NSShiftJISStringEncoding = 8,
    NSISOLatin2StringEncoding = 9,
    NSUnicodeStringEncoding = 10,
    NSWindowsCP1251StringEncoding = 11,
    NSWindowsCP1252StringEncoding = 12,
    NSWindowsCP1253StringEncoding = 13,
    NSWindowsCP1254StringEncoding = 14,
    NSWindowsCP1250StringEncoding = 15,
    NSISO2022JPStringEncoding = 21,
    NSMacOSRomanStringEncoding = 30,
    NSUTF16StringEncoding = NSUnicodeStringEncoding,
    NSUTF16BigEndianStringEncoding = 0x90000100,
    NSUTF16LittleEndianStringEncoding = 0x94000100,
    NSUTF32StringEncoding = 0x8c000100,
    NSUTF32BigEndianStringEncoding = 0x98000100,
    NSUTF32LittleEndianStringEncoding = 0x9c000100,
};

/* The option values mirror CoreFoundation's kCFCompare* flags so the compare
 * flags can be passed through unchanged; NSLiteralSearch is the default
 * (flag) state and NSRegularExpressionSearch is accepted but only meaningful
 * to rangeOfString: callers that implement their own search. */
typedef NS_OPTIONS(NSUInteger, NSStringCompareOptions) {
    NSCaseInsensitiveSearch      = 1,
    NSLiteralSearch              = 2,
    NSBackwardsSearch            = 4,
    NSAnchoredSearch             = 8,
    NSNumericSearch              = 64,
    NSDiacriticInsensitiveSearch = 128,
    NSWidthInsensitiveSearch     = 256,
    NSForcedOrderingSearch       = 512,
    NSRegularExpressionSearch    = 1024,
};

@interface NSString : NSObject

+ (instancetype)stringWithUTF8String:(const char *)utf8String;
+ (instancetype)stringWithCharacters:(const unichar *)characters length:(NSUInteger)length;
+ (instancetype)stringWithFormat:(NSString *)format, ... NS_FORMAT_FUNCTION(1,2);

- (instancetype)initWithUTF8String:(const char *)utf8String;
- (instancetype)initWithFormat:(NSString *)format, ... NS_FORMAT_FUNCTION(1,2);
- (instancetype)initWithFormat:(NSString *)format arguments:(va_list)argList NS_FORMAT_FUNCTION(1,0);
- (instancetype)initWithBytes:(const void *)bytes
                       length:(NSUInteger)length
                     encoding:(NSStringEncoding)encoding;

- (NSData *)dataUsingEncoding:(NSStringEncoding)encoding;

- (NSUInteger)length;
- (unichar)characterAtIndex:(NSUInteger)index;
- (NSString *)substringWithRange:(NSRange)range;
- (void)getCharacters:(unichar *)buffer range:(NSRange)range;
- (const char *)UTF8String;

- (BOOL)getBytes:(void *)buffer
       maxLength:(NSUInteger)maxBufferCount
      usedLength:(NSUInteger *)usedBufferCount
        encoding:(NSStringEncoding)encoding
         options:(NSStringEncodingConversionOptions)options
           range:(NSRange)range
  remainingRange:(NSRange *)leftover;

- (BOOL)isEqualToString:(NSString *)aString;
- (BOOL)hasPrefix:(NSString *)aString;
- (BOOL)hasSuffix:(NSString *)aString;
- (BOOL)containsString:(NSString *)aString;

- (NSComparisonResult)compare:(NSString *)string;
- (NSComparisonResult)compare:(NSString *)string options:(NSStringCompareOptions)mask;
- (NSComparisonResult)compare:(NSString *)string
                      options:(NSStringCompareOptions)mask
                        range:(NSRange)range;
- (NSComparisonResult)caseInsensitiveCompare:(NSString *)string;

- (NSRange)rangeOfString:(NSString *)aString;
- (NSRange)rangeOfString:(NSString *)aString options:(NSStringCompareOptions)mask;

- (NSString *)stringByAppendingString:(NSString *)aString;
- (NSString *)stringByAppendingFormat:(NSString *)format, ... NS_FORMAT_FUNCTION(1,2);
- (NSString *)lowercaseString;
- (NSString *)uppercaseString;
- (NSString *)stringByTrimmingCharactersInSet:(NSCharacterSet *)set;
- (NSString *)stringByReplacingOccurrencesOfString:(NSString *)target
                                        withString:(NSString *)replacement;
- (NSString *)stringByReplacingCharactersInRange:(NSRange)range
                                      withString:(NSString *)replacement;

- (NSArray *)componentsSeparatedByString:(NSString *)separator;
- (NSString *)substringFromIndex:(NSUInteger)from;
- (NSString *)substringToIndex:(NSUInteger)to;

@end


@interface NSMutableString : NSString

+ (instancetype)string;
+ (instancetype)stringWithCapacity:(NSUInteger)capacity;

- (nullable instancetype)initWithCapacity:(NSUInteger)capacity;
- (nullable instancetype)initWithString:(NSString *)string;

- (void)insertString:(NSString *)string atIndex:(NSUInteger)location;
- (void)deleteCharactersInRange:(NSRange)range;

- (void)appendString:(NSString *)string;
- (void)appendFormat:(NSString *)format, ...;
- (void)setString:(NSString *)string;

- (void)replaceCharactersInRange:(NSRange)range withString:(NSString *)string;
- (NSUInteger)replaceOccurrencesOfString:(NSString *)target
                              withString:(NSString *)replacement
                                 options:(NSStringCompareOptions)options
                                   range:(NSRange)searchRange;

@end

#endif /* NSString_h */
