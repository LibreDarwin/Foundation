/*
 * Copyright (C) 2026, Samuel Zormeister.
 *
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */

#ifndef NSISO8601DateFormatter_h
#define NSISO8601DateFormatter_h

#import <Foundation/NSObject.h>
#import <Foundation/NSDate.h>
#import <Foundation/NSTimeZone.h>
#import <Foundation/NSCoder.h>

typedef NS_OPTIONS(NSUInteger, NSISO8601DateFormatOptions) {
    NSISO8601DateFormatWithYear = (1UL << 0),
    NSISO8601DateFormatWithMonth = (1UL << 1),
    NSISO8601DateFormatWithWeekOfYear = (1UL << 2),
    NSISO8601DateFormatWithDay = (1UL << 4),
    NSISO8601DateFormatWithTime = (1UL << 5),
    NSISO8601DateFormatWithTimeZone = (1UL << 6),
    NSISO8601DateFormatWithSpaceBetweenDateAndTime = (1UL << 7),
    NSISO8601DateFormatWithDashSeparatorInDate = (1UL << 8),
    NSISO8601DateFormatWithColonSeparatorInTime = (1UL << 9),
    NSISO8601DateFormatWithColonSeparatorInTimeZone = (1UL << 10),
    NSISO8601DateFormatWithFractionalSeconds = (1UL << 11),

    NSISO8601DateFormatWithFullDate = NSISO8601DateFormatWithYear | NSISO8601DateFormatWithMonth | NSISO8601DateFormatWithDay | NSISO8601DateFormatWithDashSeparatorInDate,
    NSISO8601DateFormatWithFullTime = NSISO8601DateFormatWithTime | NSISO8601DateFormatWithColonSeparatorInTime | NSISO8601DateFormatWithTimeZone | NSISO8601DateFormatWithColonSeparatorInTimeZone,
    NSISO8601DateFormatWithInternetDateTime = NSISO8601DateFormatWithFullDate | NSISO8601DateFormatWithFullTime,
};

@interface NSISO8601DateFormatter : NSObject <NSSecureCoding> {
    void *_formatter;
    NSTimeZone *_timeZone;
    NSISO8601DateFormatOptions _formatOptions;
}

@property (null_resettable, copy) NSTimeZone *timeZone; // default time zone is GMT
@property NSISO8601DateFormatOptions formatOptions;

- (instancetype)init;
- (NSString *)stringFromDate:(NSDate *)date;
- (nullable NSDate *)dateFromString:(NSString *)string;

+ (NSString *)stringFromDate:(NSDate *)date timeZone:(NSTimeZone *)timeZone formatOptions:(NSISO8601DateFormatOptions)formatOptions;

- (void)encodeWithCoder:(NSCoder *)coder;
- (instancetype)initWithCoder:(NSCoder *)coder;
+ (BOOL)supportsSecureCoding;

@end

#endif /* NSISO8601DateFormatter_h */