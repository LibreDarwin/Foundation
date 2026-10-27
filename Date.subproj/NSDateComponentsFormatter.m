/*
 * Copyright (C) 2026, Samuel Zormeister.
 *
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 *
 * NSDateComponentsFormatter is a thin policy layer over three pieces of
 * Apple machinery: NSCalendar supplies the variable-length unit arithmetic,
 * ICU's uatmufmt_* entry points supply the localized unit names, and
 * CFNumberFormatter (through NSNumberFormatter) supplies decimal and
 * spelled-out numbers.  The rest of this file is the ordering, rounding and
 * zero-formatting policy that the class documents.
 */

#import <Foundation/NSDateComponentsFormatter.h>
#import <Foundation/NSCalendar.h>
#import <Foundation/NSDateComponents.h>
#import <Foundation/NSDate.h>
#import <Foundation/NSNumberFormatter.h>
#import <Foundation/NSNumber.h>
#import <Foundation/NSLocale.h>
#import <Foundation/NSTimeZone.h>
#import <Foundation/NSString.h>
#import <Foundation/NSArray.h>
#import <Foundation/NSException.h>
#import <Foundation/NSObjCRuntime.h>

#include <math.h>
#include <stdint.h>

/* ICU's date/time unit formatter.  The ABI is stable and the symbols live in
 * libicucore, which the framework already links (NSMeasurementFormatter uses
 * it for measurement units). */
typedef uint16_t LDICUChar;
typedef int32_t LDICUStatus;

extern int32_t uatmufmt_getTimePattern(const char *localeID, int32_t style,
                                       LDICUChar *result, int32_t resultCapacity,
                                       LDICUStatus *status);
extern void *uatmufmt_open(const char *localeID, int32_t style,
                           LDICUStatus *status);
extern int32_t uatmufmt_format(void *formatter, double value, int32_t unit,
                               LDICUChar *result, int32_t resultCapacity,
                               LDICUStatus *status);
extern void uatmufmt_close(void *formatter);

/* Internal unit order.  Note that ICU's index order puts day before week;
 * -LDICUUnit performs that swap. */
enum {
    LDUnitYear = 0,
    LDUnitMonth,
    LDUnitWeek,
    LDUnitDay,
    LDUnitHour,
    LDUnitMinute,
    LDUnitSecond,
    LDUnitCount
};

/* ICU unit indices. */
enum {
    LDICUYear = 0,
    LDICUMonth,
    LDICUDay,
    LDICUWeek,
    LDICUHour,
    LDICUMinute,
    LDICUSecond
};

/* ICU uatmufmt styles. */
enum {
    LDICUStyleFull = 0,
    LDICUStyleShort = 1,
    LDICUStyleAbbreviated = 2,
    LDICUStyleBrief = 3
};

typedef struct {
    NSInteger value[LDUnitCount];
    BOOL present[LDUnitCount];
} LDUnitSet;

static NSCalendarUnit LDCalendarUnit(int unit) {
    switch (unit) {
        case LDUnitYear: return NSCalendarUnitYear;
        case LDUnitMonth: return NSCalendarUnitMonth;
        case LDUnitWeek: return NSCalendarUnitWeekOfMonth;
        case LDUnitDay: return NSCalendarUnitDay;
        case LDUnitHour: return NSCalendarUnitHour;
        case LDUnitMinute: return NSCalendarUnitMinute;
        default: return NSCalendarUnitSecond;
    }
}

static int LDICUUnit(int unit) {
    switch (unit) {
        case LDUnitYear: return LDICUYear;
        case LDUnitMonth: return LDICUMonth;
        case LDUnitWeek: return LDICUWeek;
        case LDUnitDay: return LDICUDay;
        case LDUnitHour: return LDICUHour;
        case LDUnitMinute: return LDICUMinute;
        default: return LDICUSecond;
    }
}

static BOOL LDIsDefined(NSInteger value) {
    return value != NSDateComponentUndefined;
}

/* Formats one unit and value with an already-open ICU formatter. */
static NSString *LDFormatWithICU(void *formatter, double value, int unit) {
    if (formatter == NULL) return @"";
    LDICUChar stackBuffer[128];
    LDICUStatus status = 0;
    int32_t length = uatmufmt_format(formatter, value, LDICUUnit(unit),
                                     stackBuffer, 128, &status);
    if (length < 0) return @"";
    if (length < 128) {
        return [NSString stringWithCharacters:stackBuffer length:(NSUInteger)length];
    }
    LDICUChar *heapBuffer = malloc(sizeof(LDICUChar) * (size_t)(length + 1));
    if (heapBuffer == NULL) return @"";
    status = 0;
    length = uatmufmt_format(formatter, value, LDICUUnit(unit),
                             heapBuffer, length + 1, &status);
    if (length < 0) {
        free(heapBuffer);
        return @"";
    }
    NSString *result = [NSString stringWithCharacters:heapBuffer length:(NSUInteger)length];
    free(heapBuffer);
    return result;
}

static int32_t LDICUStyleForUnitsStyle(NSDateComponentsFormatterUnitsStyle style) {
    switch (style) {
        case NSDateComponentsFormatterUnitsStyleFull: return LDICUStyleFull;
        case NSDateComponentsFormatterUnitsStyleShort: return LDICUStyleShort;
        case NSDateComponentsFormatterUnitsStyleBrief: return LDICUStyleBrief;
        case NSDateComponentsFormatterUnitsStyleSpellOut: return LDICUStyleFull;
        default: return LDICUStyleAbbreviated;
    }
}

static NSString *LDDecimalString(NSInteger value, NSLocale *locale) {
    NSNumberFormatter *formatter = [[NSNumberFormatter alloc] init];
    formatter.numberStyle = NSNumberFormatterDecimalStyle;
    if (locale != nil) formatter.locale = locale;
    NSString *string = [formatter stringFromNumber:[NSNumber numberWithInteger:value]];
    return string != nil ? string : [NSString stringWithFormat:@"%ld", (long)value];
}

static NSString *LDSpellOutString(NSInteger value, NSLocale *locale) {
    NSNumberFormatter *formatter = [[NSNumberFormatter alloc] init];
    formatter.numberStyle = NSNumberFormatterSpellOutStyle;
    if (locale != nil) formatter.locale = locale;
    NSString *string = [formatter stringFromNumber:[NSNumber numberWithInteger:value]];
    return string != nil ? string : [NSString stringWithFormat:@"%ld", (long)value];
}

/* Renders a time pattern such as "h:mm:ss".  The first numeric field is not
 * padded; subsequent fields are two digits, matching ICU's en_US patterns. */
static NSString *LDFormatTimePattern(NSString *pattern, NSInteger hour,
                                     NSInteger minute, NSInteger second,
                                     NSLocale *locale) {
    NSMutableString *result = [NSMutableString string];
    BOOL quoted = NO;
    NSUInteger length = [pattern length];
    for (NSUInteger index = 0; index < length; index++) {
        unichar character = [pattern characterAtIndex:index];
        if (character == '\'') {
            quoted = !quoted;
            continue;
        }
        if (quoted) {
            [result appendFormat:@"%C", character];
            continue;
        }
        BOOL field = (character == 'h' || character == 'H' ||
                      character == 'k' || character == 'K' ||
                      character == 'm' || character == 's');
        if (!field) {
            [result appendFormat:@"%C", character];
            continue;
        }
        /* A repeated field letter is ICU's width marker ("mm", "ss"), not a
         * second occurrence of the field. */
        NSUInteger run = 1;
        while (index + run < length &&
               [pattern characterAtIndex:index + run] == character) {
            run++;
        }
        index += run - 1;

        NSInteger value = 0;
        if (character == 'h' || character == 'H' ||
            character == 'k' || character == 'K') {
            value = hour;
        } else if (character == 'm') {
            value = minute;
        } else {
            value = second;
        }
        NSString *digits = LDDecimalString(value, locale);
        if (run >= 2 && [digits length] < 2) {
            digits = [@"0" stringByAppendingString:digits];
        }
        [result appendString:digits];
    }
    return result;
}

/* ICU only returns a pattern whose fields are a subset of the ones we ask
 * for; the field letters themselves tell us which values to substitute. */
static BOOL LDPatternContains(NSString *pattern, unichar field) {
    return [pattern rangeOfString:[NSString stringWithFormat:@"%C", field]].location != NSNotFound;
}

@implementation NSDateComponentsFormatter {
    NSDateComponentsFormatterUnitsStyle _unitsStyle;
    NSCalendarUnit _allowedUnits;
    NSDateComponentsFormatterZeroFormattingBehavior _zeroFormattingBehavior;
    NSCalendar *_calendar;
    BOOL _calendarWasSet;
    NSDate *_referenceDate;
    BOOL _allowsFractionalUnits;
    NSInteger _maximumUnitCount;
    BOOL _collapsesLargestUnit;
    BOOL _includesApproximationPhrase;
    BOOL _includesTimeRemainingPhrase;
    NSFormattingContext _formattingContext;
    BOOL _ldSourceWeekDefined;
}

- (instancetype)init {
    self = [super init];
    if (self != nil) {
        _unitsStyle = NSDateComponentsFormatterUnitsStylePositional;
        _allowedUnits = 0;
        _zeroFormattingBehavior = NSDateComponentsFormatterZeroFormattingBehaviorDefault;
        _calendar = nil;
        _calendarWasSet = NO;
        _referenceDate = nil;
        _allowsFractionalUnits = NO;
        _maximumUnitCount = 0;
        _collapsesLargestUnit = NO;
        _includesApproximationPhrase = NO;
        _includesTimeRemainingPhrase = NO;
        _formattingContext = NSFormattingContextUnknown;
    }
    return self;
}

#pragma mark - Properties

- (NSDateComponentsFormatterUnitsStyle)unitsStyle {
    return _unitsStyle;
}

- (void)setUnitsStyle:(NSDateComponentsFormatterUnitsStyle)unitsStyle {
    if (unitsStyle != NSDateComponentsFormatterUnitsStyleSpellOut &&
        unitsStyle != NSDateComponentsFormatterUnitsStyleFull &&
        unitsStyle != NSDateComponentsFormatterUnitsStyleShort &&
        unitsStyle != NSDateComponentsFormatterUnitsStyleAbbreviated &&
        unitsStyle != NSDateComponentsFormatterUnitsStylePositional &&
        unitsStyle != NSDateComponentsFormatterUnitsStyleBrief) {
        [NSException raise:NSInternalInconsistencyException
                    format:@"Invalid parameter not satisfying: unitsStyle == NSDateComponentsFormatterUnitsStyleSpellOut || unitsStyle == NSDateComponentsFormatterUnitsStyleFull || unitsStyle == NSDateComponentsFormatterUnitsStyleShort || unitsStyle == NSDateComponentsFormatterUnitsStyleAbbreviated || unitsStyle == NSDateComponentsFormatterUnitsStylePositional || unitsStyle == NSDateComponentsFormatterUnitsStyleBrief"];
    }
    _unitsStyle = unitsStyle;
}

- (NSCalendarUnit)allowedUnits {
    return _allowedUnits;
}

- (void)setAllowedUnits:(NSCalendarUnit)allowedUnits {
    NSCalendarUnit legal = NSCalendarUnitYear | NSCalendarUnitMonth |
        NSCalendarUnitWeekOfMonth | NSCalendarUnitDay | NSCalendarUnitHour |
        NSCalendarUnitMinute | NSCalendarUnitSecond;
    if (allowedUnits != 0 && (allowedUnits & ~legal) != 0) {
        [NSException raise:NSInternalInconsistencyException
                    format:@"Invalid parameter not satisfying: allowedUnits == 0 || !(allowedUnits & ~(NSCalendarUnitYear | NSCalendarUnitMonth | NSCalendarUnitWeekOfMonth | NSCalendarUnitDay | NSCalendarUnitHour | NSCalendarUnitMinute | NSCalendarUnitSecond))"];
    }
    _allowedUnits = allowedUnits;
}

- (NSDateComponentsFormatterZeroFormattingBehavior)zeroFormattingBehavior {
    return _zeroFormattingBehavior;
}

- (void)setZeroFormattingBehavior:(NSDateComponentsFormatterZeroFormattingBehavior)behavior {
    _zeroFormattingBehavior = behavior;
}

- (NSCalendar *)calendar {
    if (!_calendarWasSet && _calendar == nil) {
        _calendar = [NSCalendar autoupdatingCurrentCalendar];
    }
    return _calendar;
}

- (void)setCalendar:(NSCalendar *)calendar {
    _calendar = [calendar copy];
    _calendarWasSet = YES;
}

- (NSDate *)referenceDate {
    return _referenceDate;
}

- (void)setReferenceDate:(NSDate *)referenceDate {
    _referenceDate = [referenceDate copy];
}

- (BOOL)allowsFractionalUnits {
    return _allowsFractionalUnits;
}

- (void)setAllowsFractionalUnits:(BOOL)allowsFractionalUnits {
    _allowsFractionalUnits = allowsFractionalUnits;
}

- (NSInteger)maximumUnitCount {
    return _maximumUnitCount;
}

- (void)setMaximumUnitCount:(NSInteger)maximumUnitCount {
    _maximumUnitCount = maximumUnitCount;
}

- (BOOL)collapsesLargestUnit {
    return _collapsesLargestUnit;
}

- (void)setCollapsesLargestUnit:(BOOL)collapsesLargestUnit {
    _collapsesLargestUnit = collapsesLargestUnit;
}

- (BOOL)includesApproximationPhrase {
    return _includesApproximationPhrase;
}

- (void)setIncludesApproximationPhrase:(BOOL)includesApproximationPhrase {
    _includesApproximationPhrase = includesApproximationPhrase;
}

- (BOOL)includesTimeRemainingPhrase {
    return _includesTimeRemainingPhrase;
}

- (void)setIncludesTimeRemainingPhrase:(BOOL)includesTimeRemainingPhrase {
    _includesTimeRemainingPhrase = includesTimeRemainingPhrase;
}

- (NSFormattingContext)formattingContext {
    return _formattingContext;
}

- (void)setFormattingContext:(NSFormattingContext)formattingContext {
    _formattingContext = formattingContext;
}

#pragma mark - Calendar and locale

- (NSCalendar *)ldEffectiveCalendarForComponents:(NSDateComponents *)components {
    if (components.calendar != nil) return components.calendar;
    if (_calendarWasSet) {
        if (_calendar != nil) return _calendar;
        NSCalendar *calendar = [NSCalendar calendarWithIdentifier:NSCalendarIdentifierGregorian];
        calendar.locale = [NSLocale localeWithLocaleIdentifier:@"en_US_POSIX"];
        return calendar;
    }
    return [NSCalendar autoupdatingCurrentCalendar];
}

- (NSString *)ldLocaleIdentifierForCalendar:(NSCalendar *)calendar {
    NSLocale *locale = calendar.locale;
    NSString *identifier = locale != nil ? [locale localeIdentifier] : nil;
    return identifier != nil ? identifier : @"en_US_POSIX";
}

- (NSLocale *)ldLocaleForCalendar:(NSCalendar *)calendar {
    NSLocale *locale = calendar.locale;
    if (locale == nil) locale = [NSLocale localeWithLocaleIdentifier:@"en_US_POSIX"];
    return locale;
}

#pragma mark - Decomposition

- (void)ldDecomposeInterval:(NSTimeInterval)magnitude
                referenceDate:(NSDate *)reference
                   calendar:(NSCalendar *)calendar
                       into:(LDUnitSet *)units {
    _ldSourceWeekDefined = (_allowedUnits == 0) ||
        ((_allowedUnits & NSCalendarUnitWeekOfMonth) != 0);
    NSDate *end = [reference dateByAddingTimeInterval:magnitude];
    NSCalendarUnit flags = NSCalendarUnitYear | NSCalendarUnitMonth |
        NSCalendarUnitDay | NSCalendarUnitHour | NSCalendarUnitMinute |
        NSCalendarUnitSecond;
    NSDateComponents *components = [calendar components:flags
                                              fromDate:reference
                                                toDate:end
                                               options:0];
    units->value[LDUnitYear] = LDIsDefined(components.year) ? components.year : 0;
    units->value[LDUnitMonth] = LDIsDefined(components.month) ? components.month : 0;
    units->value[LDUnitDay] = LDIsDefined(components.day) ? components.day : 0;
    units->value[LDUnitHour] = LDIsDefined(components.hour) ? components.hour : 0;
    units->value[LDUnitMinute] = LDIsDefined(components.minute) ? components.minute : 0;
    units->value[LDUnitSecond] = LDIsDefined(components.second) ? components.second : 0;
    units->value[LDUnitWeek] = units->value[LDUnitDay] / 7;
    units->value[LDUnitDay] = units->value[LDUnitDay] % 7;
    for (int unit = 0; unit < LDUnitCount; unit++) {
        if (units->value[unit] < 0) units->value[unit] = -units->value[unit];
        units->present[unit] = YES;
    }
    if (_allowedUnits == 0) return;

    NSInteger full[LDUnitCount];
    for (int unit = 0; unit < LDUnitCount; unit++) full[unit] = units->value[unit];

    NSDate *cursor = reference;
    for (int unit = 0; unit < LDUnitCount; unit++) {
        units->present[unit] = (_allowedUnits & LDCalendarUnit(unit)) != 0;
        units->value[unit] = 0;
        if (!units->present[unit]) continue;
        NSInteger amount = [self ldCountOfUnit:unit fromDate:cursor toDate:end calendar:calendar];
        units->value[unit] = amount;
        NSDateComponents *step = [[NSDateComponents alloc] init];
        [step setValue:amount forComponent:LDCalendarUnit(unit)];
        NSDate *next = [calendar dateByAddingComponents:step toDate:cursor options:0];
        if (next != nil) cursor = next;
    }
    for (int unit = 0; unit < LDUnitCount; unit++) {
        if (units->value[unit] < 0) units->value[unit] = -units->value[unit];
        if (!units->present[unit] && unit == LDUnitMonth) units->value[unit] = full[unit];
    }
    [self ldValidatePositionalUnits:units strict:NO];
}

#pragma mark - Component folding

/* Adds `amount` of `unit` to `target` by counting whole target units between
 * the calendar cursor and the date after the addition. */
- (NSInteger)ldCountOfUnit:(int)target
                  fromDate:(NSDate *)start
                    toDate:(NSDate *)end
                  calendar:(NSCalendar *)calendar {
    NSDateComponents *difference = [calendar components:LDCalendarUnit(target)
                                              fromDate:start
                                                toDate:end
                                               options:0];
    NSInteger amount = [difference valueForComponent:LDCalendarUnit(target)];
    return LDIsDefined(amount) ? amount : 0;
}

- (BOOL)ldBuildUnitsForComponents:(NSDateComponents *)components
                         calendar:(NSCalendar *)calendar
                         reference:(NSDate *)reference
                              into:(LDUnitSet *)units {
    _ldSourceWeekDefined = NO;
    for (int unit = 0; unit < LDUnitCount; unit++) {
        units->value[unit] = 0;
        units->present[unit] = NO;
    }

    NSInteger raw[LDUnitCount];
    BOOL defined[LDUnitCount];
    raw[LDUnitYear] = components.year;
    raw[LDUnitMonth] = components.month;
    raw[LDUnitWeek] = components.weekOfMonth;
    raw[LDUnitDay] = components.day;
    raw[LDUnitHour] = components.hour;
    raw[LDUnitMinute] = components.minute;
    raw[LDUnitSecond] = components.second;
    for (int unit = 0; unit < LDUnitCount; unit++) {
        defined[unit] = LDIsDefined(raw[unit]);
        if (!defined[unit]) raw[unit] = 0;
    }

    /* Week-of-year is not a quantity unit.  Apple folds it into the largest
     * defined smaller quantity unit when no explicit mask was given, and
     * reports nil when there is nowhere to put it. */
    NSInteger weekOfYear = components.weekOfYear;
    if (LDIsDefined(weekOfYear)) {
        if (_allowedUnits == 0) {
            int target = -1;
            int order[4] = { LDUnitDay, LDUnitHour, LDUnitMinute, LDUnitSecond };
            for (int index = 0; index < 4; index++) {
                if (defined[order[index]]) { target = order[index]; break; }
            }
            if (target < 0) return NO;
            static const NSInteger factors[4] = { 7, 168, 10080, 604800 };
            raw[target] += weekOfYear * factors[target - LDUnitDay];
            defined[target] = YES;
        } else {
            int target = -1;
            int order[4] = { LDUnitDay, LDUnitHour, LDUnitMinute, LDUnitSecond };
            for (int index = 0; index < 4; index++) {
                int candidate = order[index];
                if ((_allowedUnits & LDCalendarUnit(candidate)) != 0) {
                    target = candidate;
                    break;
                }
            }
            if (target >= 0) {
                static const NSInteger factors[4] = { 7, 168, 10080, 604800 };
                raw[target] += weekOfYear * factors[target - LDUnitDay];
                defined[target] = YES;
            } else if ((_allowedUnits & NSCalendarUnitWeekOfMonth) != 0) {
                raw[LDUnitWeek] += weekOfYear;
                defined[LDUnitWeek] = YES;
            }
        }
    }

    _ldSourceWeekDefined = defined[LDUnitWeek];

    if (_allowedUnits == 0) {
        /* Without a mask the defined quantity units are the output units.
         * Apple canonicalizes them through the calendar: units are counted
         * sequentially from the reference date, so defined larger units
         * absorb overflow from their defined smaller neighbours while
         * undefined units are skipped entirely. */
        NSDateComponents *addition = [[NSDateComponents alloc] init];
        if (defined[LDUnitYear]) addition.year = raw[LDUnitYear];
        if (defined[LDUnitMonth]) addition.month = raw[LDUnitMonth];
        if (defined[LDUnitWeek]) addition.weekOfMonth = raw[LDUnitWeek];
        if (defined[LDUnitDay]) addition.day = raw[LDUnitDay];
        if (defined[LDUnitHour]) addition.hour = raw[LDUnitHour];
        if (defined[LDUnitMinute]) addition.minute = raw[LDUnitMinute];
        if (defined[LDUnitSecond]) addition.second = raw[LDUnitSecond];
        NSDate *end = [calendar dateByAddingComponents:addition toDate:reference options:0];
        if (end == nil) return NO;

        NSDate *cursor = reference;
        BOOL any = NO;
        for (int unit = LDUnitYear; unit < LDUnitCount; unit++) {
            if (!defined[unit]) continue;
            NSInteger amount = [self ldCountOfUnit:unit fromDate:cursor toDate:end calendar:calendar];
            units->present[unit] = YES;
            units->value[unit] = amount;
            any = YES;
            NSDateComponents *step = [[NSDateComponents alloc] init];
            [step setValue:amount forComponent:LDCalendarUnit(unit)];
            NSDate *next = [calendar dateByAddingComponents:step toDate:cursor options:0];
            if (next != nil) cursor = next;
        }
        return any;
    }

    /* With an explicit mask, build the date described by the components and
     * then extract only the allowed units from reference to that date.  This
     * carries overflow in either direction, e.g. 3y13mo -> 4y 1mo. */
    NSDateComponents *addition = [[NSDateComponents alloc] init];
    if (defined[LDUnitYear]) addition.year = raw[LDUnitYear];
    if (defined[LDUnitMonth]) addition.month = raw[LDUnitMonth];
    if (defined[LDUnitWeek]) addition.weekOfMonth = raw[LDUnitWeek];
    if (defined[LDUnitDay]) addition.day = raw[LDUnitDay];
    if (defined[LDUnitHour]) addition.hour = raw[LDUnitHour];
    if (defined[LDUnitMinute]) addition.minute = raw[LDUnitMinute];
    if (defined[LDUnitSecond]) addition.second = raw[LDUnitSecond];
    NSDate *end = [calendar dateByAddingComponents:addition toDate:reference options:0];
    if (end == nil) return NO;

    NSDate *cursor = reference;
    for (int unit = 0; unit < LDUnitCount; unit++) {
        units->present[unit] = (_allowedUnits & LDCalendarUnit(unit)) != 0;
        units->value[unit] = 0;
        if (!units->present[unit]) continue;
        NSInteger amount = [self ldCountOfUnit:unit fromDate:cursor toDate:end calendar:calendar];
        units->value[unit] = amount;
        NSDateComponents *step = [[NSDateComponents alloc] init];
        [step setValue:amount forComponent:LDCalendarUnit(unit)];
        NSDate *next = [calendar dateByAddingComponents:step toDate:cursor options:0];
        if (next != nil) cursor = next;
    }
    NSDate *fullCursor = reference;
    for (int unit = 0; unit < LDUnitCount; unit++) {
        NSInteger amount = [self ldCountOfUnit:unit fromDate:fullCursor toDate:end calendar:calendar];
        if (!units->present[unit] && unit == LDUnitMonth) units->value[unit] = amount;
        NSDateComponents *step = [[NSDateComponents alloc] init];
        [step setValue:amount forComponent:LDCalendarUnit(unit)];
        NSDate *next = [calendar dateByAddingComponents:step toDate:fullCursor options:0];
        if (next != nil) fullCursor = next;
    }
    return YES;
}

- (void)ldApplyAllowedMaskTo:(LDUnitSet *)units
                    calendar:(NSCalendar *)calendar
                   reference:(NSDate *)reference {
    if (_allowedUnits == 0) return;
    NSInteger raw[LDUnitCount];
    for (int unit = 0; unit < LDUnitCount; unit++) {
        raw[unit] = units->value[unit];
        units->present[unit] = (_allowedUnits & LDCalendarUnit(unit)) != 0;
        units->value[unit] = 0;
    }

    NSDate *cursor = reference;
    for (int unit = LDUnitYear; unit < LDUnitCount; unit++) {
        NSInteger value = raw[unit];
        if (units->present[unit]) {
            units->value[unit] += value;
            if (value != 0) {
                NSDateComponents *addition = [[NSDateComponents alloc] init];
                [addition setValue:value forComponent:LDCalendarUnit(unit)];
                NSDate *next = [calendar dateByAddingComponents:addition toDate:cursor options:0];
                if (next != nil) cursor = next;
            }
            continue;
        }
        if (value == 0) continue;
        NSDateComponents *addition = [[NSDateComponents alloc] init];
        [addition setValue:value forComponent:LDCalendarUnit(unit)];
        NSDate *end = [calendar dateByAddingComponents:addition toDate:cursor options:0];
        if (end == nil) continue;
        int target = -1;
        for (int candidate = unit + 1; candidate < LDUnitCount; candidate++) {
            if (units->present[candidate]) { target = candidate; break; }
        }
        if (target >= 0) {
            units->value[target] += [self ldCountOfUnit:target fromDate:cursor toDate:end calendar:calendar];
        }
        cursor = end;
    }
}

#pragma mark - Rounding

/* The remainder of `unit` expressed in its next smaller standard unit. */
static NSInteger LDSubValue(const LDUnitSet *units, int unit) {
    switch (unit) {
        case LDUnitYear: return units->value[LDUnitMonth];
        case LDUnitMonth:
            return units->value[LDUnitWeek] * 7 + units->value[LDUnitDay];
        case LDUnitWeek: return units->value[LDUnitDay];
        case LDUnitDay: return units->value[LDUnitHour];
        case LDUnitHour: return units->value[LDUnitMinute];
        case LDUnitMinute: return units->value[LDUnitSecond];
        default: return 0;
    }
}

- (BOOL)ldUnitRoundsUp:(int)unit
                 units:(const LDUnitSet *)units
              calendar:(NSCalendar *)calendar
             reference:(NSDate *)reference {
    NSInteger sub = LDSubValue(units, unit);
    if (_allowedUnits == 0) {
        int subUnit = -1;
        for (int candidate = unit + 1; candidate < LDUnitCount; candidate++) {
            if (units->present[candidate]) { subUnit = candidate; break; }
        }
        if (subUnit > unit + 1 && unit >= LDUnitWeek) {
            NSInteger value = units->value[subUnit];
            if (subUnit == LDUnitHour) return value * 2 >= 24;
            if (subUnit == LDUnitMinute || subUnit == LDUnitSecond) {
                return value * 2 >= 60;
            }
            if (subUnit == LDUnitDay) return value * 2 >= 24;
        }
    }
    switch (unit) {
        case LDUnitYear:
            return sub * 2 > 12;
        case LDUnitMonth: {
            NSDateComponents *addition = [[NSDateComponents alloc] init];
            addition.year = units->value[LDUnitYear];
            addition.month = units->value[LDUnitMonth];
            NSDate *end = [calendar dateByAddingComponents:addition toDate:reference options:0];
            NSInteger length = 31;
            if (end != nil) {
                NSRange range = [calendar rangeOfUnit:NSCalendarUnitDay
                                               inUnit:NSCalendarUnitMonth
                                              forDate:end];
                if (range.length > 0) length = (NSInteger)range.length;
            }
            return sub * 2 > length;
        }
        case LDUnitWeek:
            return sub * 2 >= 7;
        case LDUnitDay:
            return sub * 2 >= 24;
        case LDUnitHour:
            return sub * 2 >= 60;
        case LDUnitMinute:
            return sub * 2 >= 60;
        default:
            return NO;
    }
}

- (void)ldApplyCollapseTo:(LDUnitSet *)units
                 calendar:(NSCalendar *)calendar
                reference:(NSDate *)reference {
    if (!_collapsesLargestUnit) return;
    if (_ldSourceWeekDefined) return;
    int first = -1;
    for (int unit = 0; unit < LDUnitCount; unit++) {
        if (units->present[unit]) { first = unit; break; }
    }
    if (first != LDUnitYear || units->value[LDUnitYear] != 1) return;
    int next = -1;
    for (int unit = LDUnitYear + 1; unit < LDUnitCount; unit++) {
        if (units->present[unit]) { next = unit; break; }
    }
    if (next < 0 || units->value[next] == 0) return;
    NSDateComponents *addition = [[NSDateComponents alloc] init];
    addition.year = units->value[LDUnitYear];
    NSDate *end = [calendar dateByAddingComponents:addition toDate:reference options:0];
    if (end == nil) return;
    NSInteger amount = [self ldCountOfUnit:next fromDate:reference toDate:end calendar:calendar];
    units->value[next] += amount;
    units->present[LDUnitYear] = NO;
    units->value[LDUnitYear] = 0;
}

- (void)ldApplyMaximumUnitCountTo:(LDUnitSet *)units
                         calendar:(NSCalendar *)calendar
                        reference:(NSDate *)reference
                         negative:(BOOL)negative {
    if (_maximumUnitCount <= 0) return;
    int indices[LDUnitCount];
    int count = 0;
    for (int unit = 0; unit < LDUnitCount; unit++) {
        if (units->present[unit]) indices[count++] = unit;
    }
    int first = -1;
    for (int position = 0; position < count; position++) {
        if (units->value[indices[position]] != 0) { first = position; break; }
    }
    if (first < 0) return;

    int stop = -1;
    NSInteger nonZero = 0;
    for (int position = first; position < count; position++) {
        int unit = indices[position];
        if (units->value[unit] != 0) {
            nonZero++;
            if (nonZero > _maximumUnitCount) { stop = position; break; }
        }
    }
    if (stop < 0) return;

    int lastPosition = stop - 1;
    int lastUnit = indices[lastPosition];
    if ([self ldUnitRoundsUp:lastUnit units:units calendar:calendar reference:reference]) {
        if (units->value[lastUnit] == 0) {
            /* A zero final unit that would round up is dropped rather than
             * promoted; only an already-present unit may round. */
            units->present[lastUnit] = NO;
        } else if (negative && lastUnit == LDUnitMonth) {
            /* Apple carries a rounded negative month as one year plus thirteen
             * months, leaving the result unnormalized. */
            units->value[lastUnit] += 14;
            units->value[LDUnitYear] += 1;
        } else {
            units->value[lastUnit] += 1;
        }
    }
    for (int position = lastPosition + 1; position < count; position++) {
        units->present[indices[position]] = NO;
    }
}

#pragma mark - Zero formatting

static void LDKeepAll(const LDUnitSet *units, BOOL *keep) {
    for (int unit = 0; unit < LDUnitCount; unit++) keep[unit] = units->present[unit];
}

static void LDDropLeadingZeros(const LDUnitSet *units, BOOL *keep) {
    BOOL dropping = YES;
    for (int unit = 0; unit < LDUnitCount; unit++) {
        if (!keep[unit]) continue;
        if (dropping && units->value[unit] == 0) {
            keep[unit] = NO;
        } else {
            dropping = NO;
        }
    }
}

static void LDDropTrailingZeros(const LDUnitSet *units, BOOL *keep) {
    BOOL dropping = YES;
    for (int unit = LDUnitCount - 1; unit >= 0; unit--) {
        if (!keep[unit]) continue;
        if (dropping && units->value[unit] == 0) {
            keep[unit] = NO;
        } else {
            dropping = NO;
        }
    }
}

static void LDDropInteriorZeros(const LDUnitSet *units, BOOL *keep) {
    int first = -1, last = -1;
    for (int unit = 0; unit < LDUnitCount; unit++) {
        if (keep[unit]) {
            if (first < 0) first = unit;
            last = unit;
        }
    }
    if (first < 0) return;
    for (int unit = first + 1; unit < last; unit++) {
        if (keep[unit] && units->value[unit] == 0) keep[unit] = NO;
    }
}

static int LDSmallestPresent(const LDUnitSet *units) {
    for (int unit = LDUnitCount - 1; unit >= 0; unit--) {
        if (units->present[unit]) return unit;
    }
    return -1;
}

- (void)ldApplyZeroFormattingTo:(const LDUnitSet *)units
                       positional:(BOOL)positional
                             keep:(BOOL *)keep {
    LDKeepAll(units, keep);
    NSUInteger behavior = _zeroFormattingBehavior;
    BOOL hasPad = (behavior & NSDateComponentsFormatterZeroFormattingBehaviorPad) != 0;
    behavior &= ~NSDateComponentsFormatterZeroFormattingBehaviorPad;
    (void)hasPad;

    if (positional) {
        if (behavior == 0) return;
        if ((behavior & NSDateComponentsFormatterZeroFormattingBehaviorDefault) != 0 &&
            (behavior & ~(NSUInteger)NSDateComponentsFormatterZeroFormattingBehaviorDefault) == 0) {
            LDDropLeadingZeros(units, keep);
            return;
        }
        if ((behavior & NSDateComponentsFormatterZeroFormattingBehaviorDropTrailing) != 0) {
            if ((behavior & NSDateComponentsFormatterZeroFormattingBehaviorDropLeading) != 0 ||
                (behavior & NSDateComponentsFormatterZeroFormattingBehaviorDropMiddle) != 0) {
                LDDropLeadingZeros(units, keep);
            }
            LDDropTrailingZeros(units, keep);
            if ((behavior & NSDateComponentsFormatterZeroFormattingBehaviorDropMiddle) != 0) {
                LDDropInteriorZeros(units, keep);
            }
            return;
        }
        if ((behavior & NSDateComponentsFormatterZeroFormattingBehaviorDropMiddle) != 0) {
            LDDropLeadingZeros(units, keep);
            BOOL any = NO;
            for (int unit = 0; unit < LDUnitCount; unit++) if (keep[unit]) { any = YES; break; }
            if (any) {
                for (int unit = LDUnitCount - 1; unit >= 0; unit--) {
                    if (units->present[unit]) { keep[unit] = YES; break; }
                }
                LDDropInteriorZeros(units, keep);
            }
            return;
        }
        if ((behavior & NSDateComponentsFormatterZeroFormattingBehaviorDropLeading) != 0) {
            LDDropLeadingZeros(units, keep);
        }
        BOOL any = NO;
        for (int unit = 0; unit < LDUnitCount; unit++) if (keep[unit]) { any = YES; break; }
        if (!any && _allowedUnits != 0) {
            int smallest = LDSmallestPresent(units);
            if (smallest >= 0) keep[smallest] = YES;
        }
        return;
    }

    /* Non-positional styles. */
    if (behavior == 0) return;
    if ((behavior & NSDateComponentsFormatterZeroFormattingBehaviorDefault) != 0) {
        for (int unit = 0; unit < LDUnitCount; unit++) {
            if (keep[unit] && units->value[unit] == 0) keep[unit] = NO;
        }
        BOOL any = NO;
        for (int unit = 0; unit < LDUnitCount; unit++) if (keep[unit]) { any = YES; break; }
        if (!any) {
            int smallest = LDSmallestPresent(units);
            if (smallest >= 0) keep[smallest] = YES;
        }
        return;
    }
    if ((behavior & NSDateComponentsFormatterZeroFormattingBehaviorDropLeading) != 0) {
        LDDropLeadingZeros(units, keep);
    }
    if ((behavior & NSDateComponentsFormatterZeroFormattingBehaviorDropTrailing) != 0) {
        LDDropTrailingZeros(units, keep);
    }
    if ((behavior & NSDateComponentsFormatterZeroFormattingBehaviorDropMiddle) != 0) {
        if ((behavior & NSDateComponentsFormatterZeroFormattingBehaviorDropTrailing) == 0 ||
            _allowedUnits != 0) {
            LDDropLeadingZeros(units, keep);
            LDDropInteriorZeros(units, keep);
        } else {
            LDDropInteriorZeros(units, keep);
        }
    }
    BOOL any = NO;
    for (int unit = 0; unit < LDUnitCount; unit++) if (keep[unit]) { any = YES; break; }
    if (!any) {
        int smallest = LDSmallestPresent(units);
        if (smallest >= 0) keep[smallest] = YES;
    }
}

#pragma mark - Rendering

- (NSString *)ldRenderNonPositional:(const LDUnitSet *)units
                               keep:(BOOL *)keep
                           calendar:(NSCalendar *)calendar
                             locale:(NSLocale *)locale
                           negative:(BOOL)negative {
    NSDateComponentsFormatterUnitsStyle style = _unitsStyle;
    if (style == NSDateComponentsFormatterUnitsStyleSpellOut) {
        NSNumberFormatter *spellOut = [[NSNumberFormatter alloc] init];
        spellOut.numberStyle = NSNumberFormatterSpellOutStyle;
        spellOut.locale = locale;

        LDICUStatus status = 0;
        void *full = uatmufmt_open([[self ldLocaleIdentifierForCalendar:calendar] UTF8String],
                                   LDICUStyleFull, &status);

        NSMutableString *result = [NSMutableString string];
        BOOL first = YES;
        BOOL signPlaced = NO;
        for (int unit = 0; unit < LDUnitCount; unit++) {
            if (!keep[unit]) continue;
            NSInteger value = units->value[unit];
            NSString *number = [spellOut stringFromNumber:[NSNumber numberWithInteger:value]];
            if (number == nil) number = [NSString stringWithFormat:@"%ld", (long)value];
            NSString *label = nil;
            if (full != NULL) {
                NSString *formatted = LDFormatWithICU(full, (double)value, unit);
                NSRange space = [formatted rangeOfString:@" "];
                label = space.location == NSNotFound ? formatted : [formatted substringFromIndex:space.location + 1];
            }
            if (label == nil || [label length] == 0) label = @"";
            if (!first) [result appendString:@", "];
            if (!first && negative && !signPlaced) {
                /* Only the first rendered unit carries the sign. */
            }
            if (first && negative) {
                [result appendString:@"minus "];
                signPlaced = YES;
            }
            [result appendString:number];
            if ([label length] > 0) {
                [result appendString:@" "];
                [result appendString:label];
            }
            first = NO;
        }
        if (full != NULL) uatmufmt_close(full);
        return result;
    }

    LDICUStatus status = 0;
    void *formatter = uatmufmt_open([[self ldLocaleIdentifierForCalendar:calendar] UTF8String],
                                    LDICUStyleForUnitsStyle(style), &status);

    NSString *separator = (style == NSDateComponentsFormatterUnitsStyleShort ||
                           style == NSDateComponentsFormatterUnitsStyleFull) ? @", " : @" ";
    NSMutableString *result = [NSMutableString string];
    BOOL first = YES;
    for (int unit = 0; unit < LDUnitCount; unit++) {
        if (!keep[unit]) continue;
        NSInteger value = units->value[unit];
        NSString *piece = formatter != NULL ? LDFormatWithICU(formatter, (double)value, unit)
                                            : [NSString stringWithFormat:@"%ld", (long)value];
        if (!first) [result appendString:separator];
        if (first && negative && value != 0) [result appendString:@"-"];
        [result appendString:piece];
        first = NO;
    }
    if (formatter != NULL) uatmufmt_close(formatter);
    return result;
}

- (NSString *)ldRenderPositional:(const LDUnitSet *)units
                            keep:(BOOL *)keep
                        calendar:(NSCalendar *)calendar
                          locale:(NSLocale *)locale
                        negative:(BOOL)negative {
    BOOL any = NO;
    for (int unit = 0; unit < LDUnitCount; unit++) if (keep[unit]) { any = YES; break; }
    if (!any && _allowedUnits != 0) {
        int smallest = LDSmallestPresent(units);
        if (smallest >= 0) keep[smallest] = YES;
    }
    BOOL anyDate = NO, anyTime = NO;
    for (int unit = LDUnitYear; unit <= LDUnitDay; unit++) if (keep[unit]) anyDate = YES;
    for (int unit = LDUnitHour; unit <= LDUnitSecond; unit++) if (keep[unit]) anyTime = YES;
    if (!anyDate && !anyTime) return @"0";

    NSString *localeIdentifier = [self ldLocaleIdentifierForCalendar:calendar];
    LDICUStatus status = 0;
    void *abbreviated = uatmufmt_open([localeIdentifier UTF8String],
                                      LDICUStyleAbbreviated, &status);

    NSMutableString *result = [NSMutableString string];
    BOOL dateSignPlaced = NO;
    if (anyDate) {
        BOOL first = YES;
        for (int unit = LDUnitYear; unit <= LDUnitDay; unit++) {
            if (!keep[unit]) continue;
            NSString *piece = abbreviated != NULL
                ? LDFormatWithICU(abbreviated, (double)units->value[unit], unit)
                : [NSString stringWithFormat:@"%ld", (long)units->value[unit]];
            if (!first) [result appendString:@" "];
            if (first && negative && units->value[unit] != 0) {
                [result appendString:@"-"];
                dateSignPlaced = YES;
            }
            [result appendString:piece];
            first = NO;
        }
    }

    if (anyTime) {
        BOOL hasHour = keep[LDUnitHour];
        BOOL hasMinute = keep[LDUnitMinute];
        BOOL hasSecond = keep[LDUnitSecond];
        NSInteger hour = units->value[LDUnitHour];
        NSInteger minute = units->value[LDUnitMinute];
        NSInteger second = units->value[LDUnitSecond];

        NSString *time = nil;
        if (hasHour && hasMinute && hasSecond) {
            LDICUChar pattern[64];
            status = 0;
            int32_t length = uatmufmt_getTimePattern([localeIdentifier UTF8String], 1,
                                                     pattern, 64, &status);
            NSString *patternString = length > 0
                ? [NSString stringWithCharacters:pattern length:(NSUInteger)length] : @"h:mm:ss";
            time = LDFormatTimePattern(patternString, hour, minute, second, locale);
        } else if (hasHour && hasMinute) {
            LDICUChar pattern[64];
            status = 0;
            int32_t length = uatmufmt_getTimePattern([localeIdentifier UTF8String], 0,
                                                     pattern, 64, &status);
            NSString *patternString = length > 0
                ? [NSString stringWithCharacters:pattern length:(NSUInteger)length] : @"h:mm";
            time = LDFormatTimePattern(patternString, hour, minute, second, locale);
        } else if (hasMinute && hasSecond) {
            LDICUChar pattern[64];
            status = 0;
            int32_t length = uatmufmt_getTimePattern([localeIdentifier UTF8String], 2,
                                                     pattern, 64, &status);
            NSString *patternString = length > 0
                ? [NSString stringWithCharacters:pattern length:(NSUInteger)length] : @"m:ss";
            time = LDFormatTimePattern(patternString, hour, minute, second, locale);
        } else if (hasHour && hasSecond) {
            time = LDFormatTimePattern(@"h:mm:ss", hour, minute, second, locale);
        } else if (hasHour) {
            if (anyDate || _includesApproximationPhrase || _includesTimeRemainingPhrase) {
                time = abbreviated != NULL
                    ? LDFormatWithICU(abbreviated, (double)hour, LDUnitHour)
                    : [NSString stringWithFormat:@"%ld", (long)hour];
            } else {
                time = LDDecimalString(hour, locale);
            }
        } else if (hasMinute) {
            if (anyDate || _includesApproximationPhrase || _includesTimeRemainingPhrase) {
                time = abbreviated != NULL
                    ? LDFormatWithICU(abbreviated, (double)minute, LDUnitMinute)
                    : [NSString stringWithFormat:@"%ld", (long)minute];
            } else {
                time = LDDecimalString(minute, locale);
            }
        } else if (hasSecond) {
            if (anyDate || _includesApproximationPhrase || _includesTimeRemainingPhrase) {
                time = abbreviated != NULL
                    ? LDFormatWithICU(abbreviated, (double)second, LDUnitSecond)
                    : [NSString stringWithFormat:@"%ld", (long)second];
            } else {
                time = LDDecimalString(second, locale);
            }
        }
        if (time != nil) {
            BOOL patternedTime = (hasHour + hasMinute + hasSecond) > 1;
            if (anyDate) [result appendString:@" "];
            if (negative && (!anyDate || patternedTime)) [result appendString:@"-"];
            [result appendString:time];
        }
    }

    if (abbreviated != NULL) uatmufmt_close(abbreviated);
    return result;
}

- (void)ldValidatePositionalUnits:(const LDUnitSet *)units strict:(BOOL)strict {
    (void)strict;
    if (_unitsStyle != NSDateComponentsFormatterUnitsStylePositional) return;
    int sequence[7] = { LDUnitYear, LDUnitMonth, LDUnitWeek, LDUnitDay,
                        LDUnitHour, LDUnitMinute, LDUnitSecond };
    int first = -1, last = -1;
    for (int index = 0; index < 7; index++) {
        if (units->present[sequence[index]]) {
            if (first < 0) first = index;
            last = index;
        }
    }
    for (int index = first; index <= last && first >= 0; index++) {
        if (!units->present[sequence[index]]) {
            [NSException raise:NSInvalidArgumentException
                        format:@"Specifying positional units with gaps is ambiguous, and therefore unsupported"];
        }
    }
}

- (NSString *)ldStringFromUnits:(LDUnitSet *)units
                       calendar:(NSCalendar *)calendar
                      reference:(NSDate *)reference
                       negative:(BOOL)negative {
    BOOL positional = _unitsStyle == NSDateComponentsFormatterUnitsStylePositional;
    NSLocale *locale = [self ldLocaleForCalendar:calendar];

    [self ldApplyCollapseTo:units calendar:calendar reference:reference];
    [self ldApplyMaximumUnitCountTo:units calendar:calendar reference:reference negative:negative];

    BOOL keep[LDUnitCount];
    [self ldApplyZeroFormattingTo:units positional:positional keep:keep];

    NSString *body = nil;
    if (positional) {
        body = [self ldRenderPositional:units keep:keep calendar:calendar locale:locale negative:negative];
    } else {
        body = [self ldRenderNonPositional:units keep:keep calendar:calendar locale:locale negative:negative];
    }
    if (body == nil) body = @"";

    NSMutableString *result = [NSMutableString string];
    if (_includesApproximationPhrase) [result appendString:@"About "];
    [result appendString:body];
    if (_includesTimeRemainingPhrase) [result appendString:@" remaining"];
    return result;
}

- (id)copyWithZone:(NSZone *)zone {
    NSDateComponentsFormatter *copy = [[NSDateComponentsFormatter allocWithZone:zone] init];
    copy->_unitsStyle = _unitsStyle;
    copy->_allowedUnits = _allowedUnits;
    copy->_zeroFormattingBehavior = _zeroFormattingBehavior;
    copy->_calendar = [_calendar copy];
    copy->_calendarWasSet = _calendarWasSet;
    copy->_allowsFractionalUnits = _allowsFractionalUnits;
    copy->_maximumUnitCount = _maximumUnitCount;
    copy->_collapsesLargestUnit = _collapsesLargestUnit;
    copy->_includesApproximationPhrase = _includesApproximationPhrase;
    copy->_includesTimeRemainingPhrase = _includesTimeRemainingPhrase;
    copy->_formattingContext = _formattingContext;
    return copy;
}

#pragma mark - Public formatting

- (NSString *)stringForObjectValue:(id)obj {
    if ([obj isKindOfClass:[NSDateComponents class]]) {
        return [self stringFromDateComponents:obj];
    }
    return nil;
}

- (NSString *)stringFromDateComponents:(NSDateComponents *)components {
    if (components == nil) {
        [NSException raise:NSInternalInconsistencyException
                    format:@"Invalid parameter not satisfying: components != nil"];
    }
    NSCalendar *calendar = [self ldEffectiveCalendarForComponents:components];
    NSDate *reference = _referenceDate != nil
        ? _referenceDate
        : [NSDate dateWithTimeIntervalSinceReferenceDate:0];

    LDUnitSet units;
    if (![self ldBuildUnitsForComponents:components calendar:calendar
                               reference:reference into:&units]) {
        return nil;
    }
    [self ldValidatePositionalUnits:&units strict:(_allowedUnits == 0)];
    return [self ldStringFromUnits:&units calendar:calendar reference:reference negative:NO];
}

- (NSString *)stringFromDate:(NSDate *)startDate toDate:(NSDate *)endDate {
    if (startDate == nil || endDate == nil) return nil;
    NSTimeInterval interval = [endDate timeIntervalSinceDate:startDate];
    if (!isfinite(interval) || isnan(interval)) {
        [NSException raise:NSInternalInconsistencyException
                    format:@"Invalid parameter not satisfying: isfinite(timeInterval) && !isnan(timeInterval)"];
    }
    BOOL negative = interval < 0;

    NSCalendar *calendar = [self ldEffectiveCalendarForComponents:nil];
    NSDate *reference = startDate;
    LDUnitSet units;
    [self ldDecomposeInterval:interval referenceDate:reference calendar:calendar into:&units];
    return [self ldStringFromUnits:&units calendar:calendar reference:reference negative:negative];
}

- (NSString *)stringFromTimeInterval:(NSTimeInterval)ti {
    if (!isfinite(ti) || isnan(ti)) {
        [NSException raise:NSInternalInconsistencyException
                    format:@"Invalid parameter not satisfying: isfinite(timeInterval) && !isnan(timeInterval)"];
    }
    BOOL negative = ti < 0;

    NSCalendar *calendar = [self ldEffectiveCalendarForComponents:nil];
    NSDate *reference = _referenceDate != nil
        ? _referenceDate
        : [NSDate dateWithTimeIntervalSinceReferenceDate:0];
    LDUnitSet units;
    [self ldDecomposeInterval:ti referenceDate:reference calendar:calendar into:&units];
    return [self ldStringFromUnits:&units calendar:calendar reference:reference negative:negative];
}

+ (NSString *)localizedStringFromDateComponents:(NSDateComponents *)components
                                      unitsStyle:(NSDateComponentsFormatterUnitsStyle)unitsStyle {
    NSDateComponentsFormatter *formatter = [[NSDateComponentsFormatter alloc] init];
    formatter.unitsStyle = unitsStyle;
    return [formatter stringFromDateComponents:components];
}

- (BOOL)getObjectValue:(id *)obj
             forString:(NSString *)string
      errorDescription:(NSString **)error {
    if (obj != NULL) *obj = nil;
    if (error != NULL) *error = nil;
    return NO;
}

@end
