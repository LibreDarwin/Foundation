/*
 * Copyright (C) 2026, Samuel Zormeister.
 *
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */

#ifndef NSDateFormatter_h
#define NSDateFormatter_h

#import <Foundation/NSObject.h>
#import <Foundation/NSDate.h>
#import <Foundation/NSLocale.h>
#import <Foundation/NSRange.h>
#import <Foundation/NSError.h>
#import <Foundation/NSTimeZone.h>
#import <Foundation/NSCalendar.h>
#import <Foundation/NSArray.h>
#import <Foundation/NSDictionary.h>

typedef NS_ENUM(NSUInteger, NSDateFormatterStyle) {
    NSDateFormatterNoStyle = 0,
    NSDateFormatterShortStyle = 1,
    NSDateFormatterMediumStyle = 2,
    NSDateFormatterLongStyle = 3,
    NSDateFormatterFullStyle = 4
};

@interface NSDateFormatter : NSObject {
    void *_formatter;
    NSMutableDictionary *_symbolOverrides;
}

+ (instancetype)dateFormatter;
+ (NSString *)localizedStringFromDate:(NSDate *)date dateStyle:(NSDateFormatterStyle)dstyle timeStyle:(NSDateFormatterStyle)tstyle;
+ (nullable NSString *)dateFormatFromTemplate:(NSString *)tmplate options:(NSUInteger)opts locale:(nullable NSLocale *)locale;
- (instancetype)init;
- (instancetype)initWithDateFormat:(NSString *)format locale:(NSLocale *)locale;
- (void)setLocalizedDateFormatFromTemplate:(NSString *)dateFormatTemplate;

@property NSDateFormatterStyle dateStyle;
@property NSDateFormatterStyle timeStyle;
@property (copy) NSString *dateFormat;
@property (copy) NSLocale *locale;
@property (getter=isLenient) BOOL lenient;
@property (nullable, copy) NSDate *defaultDate;
@property (nullable, copy) NSTimeZone *timeZone;
@property (nullable, copy) NSCalendar *calendar;
@property BOOL doesRelativeDateFormatting;
@property (nullable, copy) NSDate *gregorianStartDate;

@property (copy) NSArray<NSString *> *eraSymbols;
@property (copy) NSArray<NSString *> *monthSymbols;
@property (copy) NSArray<NSString *> *shortMonthSymbols;
@property (copy) NSArray<NSString *> *veryShortMonthSymbols;
@property (copy) NSArray<NSString *> *weekdaySymbols;
@property (copy) NSArray<NSString *> *shortWeekdaySymbols;
@property (copy) NSArray<NSString *> *veryShortWeekdaySymbols;
@property (copy) NSArray<NSString *> *longEraSymbols;
@property (copy) NSArray<NSString *> *standaloneMonthSymbols;
@property (copy) NSArray<NSString *> *shortStandaloneMonthSymbols;
@property (copy) NSArray<NSString *> *veryShortStandaloneMonthSymbols;
@property (copy) NSArray<NSString *> *standaloneWeekdaySymbols;
@property (copy) NSArray<NSString *> *shortStandaloneWeekdaySymbols;
@property (copy) NSArray<NSString *> *veryShortStandaloneWeekdaySymbols;
@property (copy) NSArray<NSString *> *quarterSymbols;
@property (copy) NSArray<NSString *> *shortQuarterSymbols;
@property (copy) NSArray<NSString *> *standaloneQuarterSymbols;
@property (copy) NSArray<NSString *> *shortStandaloneQuarterSymbols;
@property (copy) NSString *AMSymbol;
@property (copy) NSString *PMSymbol;

- (NSString *)stringFromDate:(NSDate *)date;
- (NSDate *)dateFromString:(NSString *)string;
- (BOOL)getObjectValue:(id *)obj forString:(NSString *)string range:(NSRange *)rangep error:(NSError **)error;

@end

#endif /* NSDateFormatter_h */
