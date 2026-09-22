/*
 * Copyright (C) 2026, Samuel Zormeister.
 *
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */

#ifndef NSCalendar_h
#define NSCalendar_h

#import <Foundation/NSObject.h>
#import <Foundation/NSArray.h>
#import <Foundation/NSDate.h>
#import <Foundation/NSDateComponents.h>
#import <Foundation/NSCalendarUnit.h>
#import <Foundation/NSNotification.h>
#import <Foundation/NSRange.h>

@class NSString;
@class NSLocale;

typedef NSString *NSCalendarIdentifier;

FOUNDATION_EXPORT NSCalendarIdentifier const NSCalendarIdentifierGregorian;
FOUNDATION_EXPORT NSCalendarIdentifier const NSCalendarIdentifierBuddhist;
FOUNDATION_EXPORT NSCalendarIdentifier const NSCalendarIdentifierChinese;
FOUNDATION_EXPORT NSCalendarIdentifier const NSCalendarIdentifierCoptic;
FOUNDATION_EXPORT NSCalendarIdentifier const NSCalendarIdentifierEthiopicAmeteMihret;
FOUNDATION_EXPORT NSCalendarIdentifier const NSCalendarIdentifierEthiopicAmeteAlem;
FOUNDATION_EXPORT NSCalendarIdentifier const NSCalendarIdentifierHebrew;
FOUNDATION_EXPORT NSCalendarIdentifier const NSCalendarIdentifierISO8601;
FOUNDATION_EXPORT NSCalendarIdentifier const NSCalendarIdentifierIndian;
FOUNDATION_EXPORT NSCalendarIdentifier const NSCalendarIdentifierIslamic;
FOUNDATION_EXPORT NSCalendarIdentifier const NSCalendarIdentifierIslamicCivil;
FOUNDATION_EXPORT NSCalendarIdentifier const NSCalendarIdentifierJapanese;
FOUNDATION_EXPORT NSCalendarIdentifier const NSCalendarIdentifierPersian;
FOUNDATION_EXPORT NSCalendarIdentifier const NSCalendarIdentifierRepublicOfChina;
FOUNDATION_EXPORT NSCalendarIdentifier const NSCalendarIdentifierIslamicTabular;
FOUNDATION_EXPORT NSCalendarIdentifier const NSCalendarIdentifierIslamicUmmAlQura;
FOUNDATION_EXPORT NSCalendarIdentifier const NSCalendarIdentifierBangla;
FOUNDATION_EXPORT NSCalendarIdentifier const NSCalendarIdentifierGujarati;
FOUNDATION_EXPORT NSCalendarIdentifier const NSCalendarIdentifierKannada;
FOUNDATION_EXPORT NSCalendarIdentifier const NSCalendarIdentifierMalayalam;
FOUNDATION_EXPORT NSCalendarIdentifier const NSCalendarIdentifierMarathi;
FOUNDATION_EXPORT NSCalendarIdentifier const NSCalendarIdentifierOdia;
FOUNDATION_EXPORT NSCalendarIdentifier const NSCalendarIdentifierTamil;
FOUNDATION_EXPORT NSCalendarIdentifier const NSCalendarIdentifierTelugu;
FOUNDATION_EXPORT NSCalendarIdentifier const NSCalendarIdentifierVikram;
FOUNDATION_EXPORT NSCalendarIdentifier const NSCalendarIdentifierDangi;
FOUNDATION_EXPORT NSCalendarIdentifier const NSCalendarIdentifierVietnamese;

/* Posted through [NSNotificationCenter defaultCenter] when the system day
 * changes, as defined by the process's current calendar, locale, and time
 * zone. */
FOUNDATION_EXPORT NSNotificationName const NSCalendarDayChangedNotification;

@interface NSCalendar : NSObject <NSCopying, NSSecureCoding>

+ (instancetype)currentCalendar;
+ (instancetype)autoupdatingCurrentCalendar;
+ (instancetype)calendarWithIdentifier:(NSCalendarIdentifier)identifier;
- (instancetype)initWithCalendarIdentifier:(NSCalendarIdentifier)identifier;

@property (readonly, copy) NSCalendarIdentifier calendarIdentifier;
@property (copy) NSLocale *locale;

/* The first weekday is 1-based, as in CFCalendar and the Gregorian tradition:
 * Sunday is 1 and Saturday is 7. */
@property NSUInteger firstWeekday;
@property NSUInteger minimumDaysInFirstWeek;

/* Component name strings, localized to the calendar's locale. */
@property (readonly, copy) NSArray<NSString *> *eraSymbols;
@property (readonly, copy) NSArray<NSString *> *longEraSymbols;

@property (readonly, copy) NSArray<NSString *> *monthSymbols;
@property (readonly, copy) NSArray<NSString *> *shortMonthSymbols;
@property (readonly, copy) NSArray<NSString *> *veryShortMonthSymbols;
@property (readonly, copy) NSArray<NSString *> *standaloneMonthSymbols;
@property (readonly, copy) NSArray<NSString *> *shortStandaloneMonthSymbols;
@property (readonly, copy) NSArray<NSString *> *veryShortStandaloneMonthSymbols;

@property (readonly, copy) NSArray<NSString *> *weekdaySymbols;
@property (readonly, copy) NSArray<NSString *> *shortWeekdaySymbols;
@property (readonly, copy) NSArray<NSString *> *veryShortWeekdaySymbols;
@property (readonly, copy) NSArray<NSString *> *standaloneWeekdaySymbols;
@property (readonly, copy) NSArray<NSString *> *shortStandaloneWeekdaySymbols;
@property (readonly, copy) NSArray<NSString *> *veryShortStandaloneWeekdaySymbols;

@property (readonly, copy) NSArray<NSString *> *quarterSymbols;
@property (readonly, copy) NSArray<NSString *> *shortQuarterSymbols;
@property (readonly, copy) NSArray<NSString *> *standaloneQuarterSymbols;
@property (readonly, copy) NSArray<NSString *> *shortStandaloneQuarterSymbols;

@property (readonly, copy) NSString *AMSymbol;
@property (readonly, copy) NSString *PMSymbol;

- (NSRange)minimumRangeOfUnit:(NSCalendarUnit)unit;
- (NSRange)maximumRangeOfUnit:(NSCalendarUnit)unit;

- (NSRange)rangeOfUnit:(NSCalendarUnit)smaller inUnit:(NSCalendarUnit)larger forDate:(NSDate *)date;
- (NSUInteger)ordinalityOfUnit:(NSCalendarUnit)smaller inUnit:(NSCalendarUnit)larger forDate:(NSDate *)date;
- (BOOL)rangeOfUnit:(NSCalendarUnit)unit startDate:(NSDate **)datep interval:(NSTimeInterval *)tip forDate:(NSDate *)date;

- (NSDate *)dateFromComponents:(NSDateComponents *)comps;
- (NSDateComponents *)components:(NSCalendarUnit)unitFlags fromDate:(NSDate *)date;
- (NSDate *)dateByAddingComponents:(NSDateComponents *)comps
                            toDate:(NSDate *)date
                           options:(NSCalendarOptions)opts;
- (NSDateComponents *)components:(NSCalendarUnit)unitFlags
                        fromDate:(NSDate *)startingDate
                          toDate:(NSDate *)resultDate
                         options:(NSCalendarOptions)opts;

- (void)getEra:(NSInteger *)eraValuePointer
          year:(NSInteger *)yearValuePointer
         month:(NSInteger *)monthValuePointer
           day:(NSInteger *)dayValuePointer
      fromDate:(NSDate *)date;
- (void)getEra:(NSInteger *)eraValuePointer
yearForWeekOfYear:(NSInteger *)yearValuePointer
    weekOfYear:(NSInteger *)weekValuePointer
       weekday:(NSInteger *)weekdayValuePointer
      fromDate:(NSDate *)date;
- (void)getHour:(NSInteger *)hourValuePointer
        minute:(NSInteger *)minuteValuePointer
        second:(NSInteger *)secondValuePointer
    nanosecond:(NSInteger *)nanosecondValuePointer
      fromDate:(NSDate *)date;
- (NSInteger)component:(NSCalendarUnit)unit fromDate:(NSDate *)date;

- (NSDate *)dateWithEra:(NSInteger)eraValue
                   year:(NSInteger)yearValue
                  month:(NSInteger)monthValue
                    day:(NSInteger)dayValue
                   hour:(NSInteger)hourValue
                 minute:(NSInteger)minuteValue
                 second:(NSInteger)secondValue
             nanosecond:(NSInteger)nanosecondValue;
- (NSDate *)dateWithEra:(NSInteger)eraValue
       yearForWeekOfYear:(NSInteger)yearValue
             weekOfYear:(NSInteger)weekValue
                weekday:(NSInteger)weekdayValue
                   hour:(NSInteger)hourValue
                 minute:(NSInteger)minuteValue
                 second:(NSInteger)secondValue
             nanosecond:(NSInteger)nanosecondValue;

- (NSDate *)dateBySettingUnit:(NSCalendarUnit)unit
                        value:(NSInteger)value
                       ofDate:(NSDate *)date
                      options:(NSCalendarOptions)opts;

- (NSDate *)dateBySettingHour:(NSInteger)hour
                        minute:(NSInteger)minute
                        second:(NSInteger)second
                        ofDate:(NSDate *)date
                       options:(NSCalendarOptions)opts;

- (NSDate *)nextDateAfterDate:(NSDate *)date
           matchingComponents:(NSDateComponents *)comps
                      options:(NSCalendarOptions)opts;
- (NSDate *)nextDateAfterDate:(NSDate *)date
                matchingUnit:(NSCalendarUnit)unit
                       value:(NSInteger)value
                     options:(NSCalendarOptions)opts;
- (NSDate *)nextDateAfterDate:(NSDate *)date
               matchingHour:(NSInteger)hour
                     minute:(NSInteger)minute
                     second:(NSInteger)second
                    options:(NSCalendarOptions)opts;

- (NSDate *)startOfDayForDate:(NSDate *)date;

- (NSComparisonResult)compareDate:(NSDate *)date1
                           toDate:(NSDate *)date2
                toUnitGranularity:(NSCalendarUnit)unit;
- (BOOL)isDate:(NSDate *)date1 equalToDate:(NSDate *)date2 toUnitGranularity:(NSCalendarUnit)unit;
- (BOOL)isDate:(NSDate *)date1 inSameDayAsDate:(NSDate *)date2;
- (BOOL)isDateInToday:(NSDate *)date;
- (BOOL)isDateInYesterday:(NSDate *)date;
- (BOOL)isDateInTomorrow:(NSDate *)date;
- (BOOL)date:(NSDate *)date matchesComponents:(NSDateComponents *)components;

- (NSDateComponents *)components:(NSCalendarUnit)unitFlags
               fromDateComponents:(NSDateComponents *)startingDateComp
                 toDateComponents:(NSDateComponents *)resultDateComp
                          options:(NSCalendarOptions)options;

- (NSDate *)dateByAddingUnit:(NSCalendarUnit)unit
                       value:(NSInteger)value
                      toDate:(NSDate *)date
                     options:(NSCalendarOptions)options;

- (id)copyWithZone:(NSZone *)zone;

@end

#endif /* NSCalendar_h */
