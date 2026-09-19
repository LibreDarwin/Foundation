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
@property (readonly, copy) NSLocale *locale;

- (NSString *)stringFromDate:(NSDate *)date;
- (NSDate *)dateFromString:(NSString *)string;

@end

#endif /* NSDateFormatter_h */
