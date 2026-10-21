/*
 * Copyright (C) 2026, Samuel Zormeister.
 *
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */

#import <Foundation/NSDateInterval.h>
#import <Foundation/NSException.h>
#import <Foundation/NSString.h>

@interface _NSConcreteDateInterval : NSDateInterval
@end

/* NSDateInterval is a class cluster; +alloc hands back the concrete subclass
 * below, exactly like the system. The base class carries the storage and all
 * of the behavior so the subclass stays empty. */
@implementation NSDateInterval {
    NSDate *_startDate;
    NSTimeInterval _duration;
}

+ (id)allocWithZone:(NSZone *)zone {
    if (self == [NSDateInterval class]) {
        return [_NSConcreteDateInterval allocWithZone:zone];
    }
    return [super allocWithZone:zone];
}

- (instancetype)init {
    return [self initWithStartDate:[NSDate date] duration:0.0];
}

- (instancetype)initWithStartDate:(NSDate *)startDate duration:(NSTimeInterval)duration {
    if (startDate == nil) {
        @throw [NSException exceptionWithName:NSInvalidArgumentException
                                       reason:@"Start date is nil!"
                                     userInfo:nil];
    }
    /* Written as a negated >= so a NaN duration lands here too, matching the
     * system's ordered comparison. */
    if (!(duration >= 0.0)) {
        @throw [NSException exceptionWithName:NSInvalidArgumentException
                                       reason:@"Duration is less than 0!"
                                     userInfo:nil];
    }
    self = [super init];
    if (self != nil) {
        _startDate = [startDate copy];
        _duration = duration;
    }
    return self;
}

- (instancetype)initWithStartDate:(NSDate *)startDate endDate:(NSDate *)endDate {
    if (startDate == nil) {
        @throw [NSException exceptionWithName:NSInvalidArgumentException
                                       reason:@"Start date is nil!"
                                     userInfo:nil];
    }
    if (endDate == nil) {
        @throw [NSException exceptionWithName:NSInvalidArgumentException
                                       reason:@"End date is nil!"
                                     userInfo:nil];
    }
    if ([startDate compare:endDate] == NSOrderedDescending) {
        @throw [NSException exceptionWithName:NSGenericException
                                       reason:@"Start date cannot be later in time than end date!"
                                     userInfo:nil];
    }
    return [self initWithStartDate:startDate
                          duration:[endDate timeIntervalSinceDate:startDate]];
}

- (NSDate *)startDate {
    return _startDate;
}

- (NSDate *)endDate {
    /* A zero-length interval reports the very same date object it started
     * with; only a non-zero duration asks NSDate to do the arithmetic. */
    if (_duration == 0.0) {
        return _startDate;
    }
    return [NSDate dateWithTimeIntervalSinceReferenceDate:
            [_startDate timeIntervalSinceReferenceDate] + _duration];
}

- (NSTimeInterval)duration {
    return _duration;
}

- (NSComparisonResult)compare:(NSDateInterval *)dateInterval {
    if (self == dateInterval) {
        return NSOrderedSame;
    }
    if (dateInterval == nil) {
        return NSOrderedDescending;
    }
    NSComparisonResult result = [_startDate compare:[dateInterval startDate]];
    if (result != NSOrderedSame) {
        return result;
    }
    NSTimeInterval otherDuration = [dateInterval duration];
    if (_duration < otherDuration) {
        return NSOrderedAscending;
    }
    if (_duration > otherDuration) {
        return NSOrderedDescending;
    }
    return NSOrderedSame;
}

- (BOOL)isEqualToDateInterval:(NSDateInterval *)dateInterval {
    if (dateInterval == nil) {
        return NO;
    }
    return [_startDate isEqualToDate:[dateInterval startDate]]
        && _duration == [dateInterval duration];
}

- (BOOL)isEqual:(id)object {
    if (object == self) {
        return YES;
    }
    if (object == nil || ![object isKindOfClass:[NSDateInterval class]]) {
        return NO;
    }
    return [self isEqualToDateInterval:object];
}

- (NSUInteger)hash {
    return (NSUInteger)[_startDate timeIntervalSinceReferenceDate]
        ^ (NSUInteger)_duration;
}

- (id)copyWithZone:(NSZone *)zone {
    (void)zone;
    /* Immutable: a copy is the same instance, like the system. */
    return self;
}

- (BOOL)containsDate:(NSDate *)date {
    if (date == nil) {
        return NO;
    }
    NSTimeInterval start = [_startDate timeIntervalSinceReferenceDate];
    NSTimeInterval end = start + _duration;
    NSTimeInterval point = [date timeIntervalSinceReferenceDate];
    return point >= start && point <= end;
}

- (BOOL)intersectsDateInterval:(NSDateInterval *)dateInterval {
    if (dateInterval == nil) {
        return NO;
    }
    if ([self containsDate:[dateInterval startDate]]) {
        return YES;
    }
    return [dateInterval containsDate:_startDate];
}

- (NSDateInterval *)intersectionWithDateInterval:(NSDateInterval *)dateInterval {
    if (dateInterval == nil) {
        return nil;
    }
    if (![self intersectsDateInterval:dateInterval]) {
        return nil;
    }
    if ([self isEqualToDateInterval:dateInterval]) {
        return [self copy];
    }

    NSTimeInterval selfStart = [_startDate timeIntervalSinceReferenceDate];
    NSTimeInterval selfEnd = selfStart + _duration;
    NSTimeInterval otherStart = [[dateInterval startDate] timeIntervalSinceReferenceDate];
    NSTimeInterval otherEnd = otherStart + [dateInterval duration];

    NSDateInterval *later = selfStart >= otherStart ? self : dateInterval;
    NSTimeInterval start = selfStart >= otherStart ? selfStart : otherStart;
    NSTimeInterval end = selfEnd <= otherEnd ? selfEnd : otherEnd;

    return [[NSDateInterval alloc] initWithStartDate:[later startDate]
                                            duration:end - start];
}

- (NSString *)description {
    return [NSString stringWithFormat:@"<%@: %p> (Start Date) %@ + (Duration) %f seconds = (End Date) %@",
            NSStringFromClass([self class]), self, _startDate, _duration, [self endDate]];
}

#pragma mark - NSCoding

+ (BOOL)supportsSecureCoding {
    return YES;
}

- (void)encodeWithCoder:(NSCoder *)coder {
    if (![coder allowsKeyedCoding]) return;
    [coder encodeObject:_startDate forKey:@"NS.startDate"];
    [coder encodeObject:[self endDate] forKey:@"NS.endDate"];
    [coder encodeDouble:_duration forKey:@"NS.duration"];
}

- (instancetype)initWithCoder:(NSCoder *)coder {
    if (![coder allowsKeyedCoding]) return nil;
    NSDate *start = [coder decodeObjectOfClass:[NSDate class] forKey:@"NS.startDate"];
    if (start == nil) return nil;
    if ([coder containsValueForKey:@"NS.duration"]) {
        return [self initWithStartDate:start duration:[coder decodeDoubleForKey:@"NS.duration"]];
    }
    NSDate *end = [coder decodeObjectOfClass:[NSDate class] forKey:@"NS.endDate"];
    if ([coder error] != nil) return nil;
    return [self initWithStartDate:start endDate:end];
}

@end

/* Empty concrete subclass: every method lives on NSDateInterval, but the
 * runtime class an instance reports is this one. */
@implementation _NSConcreteDateInterval
@end
