/*
 * Copyright (C) 2026, Samuel Zormeister.
 *
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */

#ifndef NSFormatter_h
#define NSFormatter_h

#import <Foundation/NSObject.h>
#import <Foundation/NSRange.h>
#import <Foundation/NSAttributedString.h>

@class NSString, NSAttributedString, NSDictionary, NSCoder;

/* The capitalization context a formatter uses when it produces a string. */
typedef NS_ENUM(NSInteger, NSFormattingContext) {
    NSFormattingContextUnknown = 0,
    NSFormattingContextDynamic = 1,
    NSFormattingContextStandalone = 2,
    NSFormattingContextListItem = 3,
    NSFormattingContextBeginningOfSentence = 4,
    NSFormattingContextMiddleOfSentence = 5
};

/* There are 3 widths: long, medium, and short.  For example, for English,
 * when formatting "3 pounds", long is "3 pounds", medium is "3 lb" and short
 * is "3#". */
typedef NS_ENUM(NSInteger, NSFormattingUnitStyle) {
    NSFormattingUnitStyleShort = 1,
    NSFormattingUnitStyleMedium = 2,
    NSFormattingUnitStyleLong = 3
};

/* NSFormatter is an abstract base class.  Its concrete subclasses (such as
 * NSNumberFormatter, NSDateFormatter, NSByteCountFormatter, NSListFormatter)
 * override -stringForObjectValue: to turn a value into a display string and
 * -getObjectValue:forString:errorDescription: to parse one back. */
@interface NSFormatter : NSObject <NSCopying, NSCoding>

- (nullable NSString *)stringForObjectValue:(nullable id)obj;

- (nullable NSAttributedString *)attributedStringForObjectValue:(id)obj
                                           withDefaultAttributes:(nullable NSDictionary *)attrs;

- (nullable NSString *)editingStringForObjectValue:(id)obj;

- (BOOL)getObjectValue:(out id _Nullable * _Nullable)obj
             forString:(NSString *)string
      errorDescription:(out NSString * _Nullable * _Nullable)error;

- (BOOL)isPartialStringValid:(NSString *)partialString
            newEditingString:(NSString * _Nullable * _Nullable)newString
            errorDescription:(NSString * _Nullable * _Nullable)error;

- (BOOL)isPartialStringValid:(NSString * _Nonnull * _Nonnull)partialStringPtr
        proposedSelectedRange:(nullable NSRange *)proposedSelRangePtr
               originalString:(NSString *)origString
        originalSelectedRange:(NSRange)origSelRange
             errorDescription:(NSString * _Nullable * _Nullable)error;

@end

#endif /* NSFormatter_h */
