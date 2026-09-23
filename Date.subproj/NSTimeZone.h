/*
 * Copyright (C) 2026, Samuel Zormeister.
 *
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */

#ifndef NSTimeZone_h
#define NSTimeZone_h

#import <Foundation/NSObject.h>
#import <Foundation/NSDate.h>

@class NSArray;
@class NSData;
@class NSLocale;
@class NSString;

typedef NS_ENUM(NSUInteger, NSTimeZoneNameStyle) {
    NSTimeZoneNameStyleStandard = 0,
    NSTimeZoneNameStyleShortStandard = 1,
    NSTimeZoneNameStyleDaylightSaving = 2,
    NSTimeZoneNameStyleShortDaylightSaving = 3,
};

@interface NSTimeZone : NSObject <NSCopying> {
@private
    NSString *_name;
    NSData *_data;
    NSInteger _secondsFromGMT;
}

+ (NSTimeZone *)systemTimeZone;
+ (NSTimeZone *)defaultTimeZone;
+ (void)setDefaultTimeZone:(NSTimeZone *)tz;
+ (NSTimeZone *)localTimeZone;
+ (void)resetSystemTimeZone;
+ (NSTimeZone *)timeZoneWithName:(NSString *)tzName;
+ (NSTimeZone *)timeZoneWithName:(NSString *)tzName data:(NSData *)aData;
+ (NSTimeZone *)timeZoneForSecondsFromGMT:(NSInteger)seconds;
+ (NSTimeZone *)timeZoneWithAbbreviation:(NSString *)abbreviation;
+ (NSArray *)knownTimeZoneNames;
+ (NSDictionary *)abbreviationDictionary;

- (instancetype)initWithName:(NSString *)tzName data:(NSData *)aData;
- (NSString *)name;
- (NSData *)data;
- (NSInteger)secondsFromGMT;
- (NSInteger)secondsFromGMTForDate:(NSDate *)aDate;
- (NSString *)abbreviation;
- (NSString *)abbreviationForDate:(NSDate *)aDate;
- (BOOL)isDaylightSavingTime;
- (BOOL)isDaylightSavingTimeForDate:(NSDate *)aDate;
- (NSTimeInterval)daylightSavingTimeOffset;
- (NSTimeInterval)daylightSavingTimeOffsetForDate:(NSDate *)aDate;
- (NSDate *)nextDaylightSavingTimeTransition;
- (NSDate *)nextDaylightSavingTimeTransitionAfterDate:(NSDate *)aDate;
- (BOOL)isEqualToTimeZone:(NSTimeZone *)aTimeZone;
- (NSString *)localizedName:(NSTimeZoneNameStyle)style locale:(NSLocale *)locale;

@end

#endif /* NSTimeZone_h */