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

typedef NS_ENUM(NSUInteger, NSDateFormatterStyle) {
    NSDateFormatterNoStyle = 0,
    NSDateFormatterShortStyle = 1,
    NSDateFormatterMediumStyle = 2,
    NSDateFormatterLongStyle = 3,
    NSDateFormatterFullStyle = 4
};

@interface NSDateFormatter : NSObject {
    void *_formatter;
}

+ (instancetype)dateFormatter;
- (instancetype)init;
- (instancetype)initWithDateFormat:(NSString *)format locale:(NSLocale *)locale;

@property NSDateFormatterStyle dateStyle;
@property NSDateFormatterStyle timeStyle;
@property (copy) NSString *dateFormat;
@property (copy) NSLocale *locale;
@property (getter=isLenient) BOOL lenient;
@property (nullable, copy) NSDate *defaultDate;

- (NSString *)stringFromDate:(NSDate *)date;
- (NSDate *)dateFromString:(NSString *)string;
- (BOOL)getObjectValue:(id *)obj forString:(NSString *)string range:(NSRange *)rangep error:(NSError **)error;

@end

#endif /* NSDateFormatter_h */
