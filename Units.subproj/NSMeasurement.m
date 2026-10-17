/*
 * Copyright (C) 2026, LibreDarwin.
 *
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */

#import <Foundation/NSMeasurement.h>
#import <Foundation/NSException.h>
#import <Foundation/NSCoder.h>
#import <Foundation/NSString.h>

static BOOL NSMeasurementSameDimension(NSUnit *a, NSUnit *b) {
    return [a isKindOfClass:[NSDimension class]] &&
           [b isKindOfClass:[NSDimension class]] &&
           [a class] == [b class];
}

@implementation NSMeasurement {
@private
    NSUnit *_unit;
    double _doubleValue;
}

+ (BOOL)supportsSecureCoding {
    return YES;
}

- (instancetype)initWithDoubleValue:(double)doubleValue unit:(NSUnit *)unit {
    self = [super init];
    if (self) {
        _unit = [unit copy];
        _doubleValue = doubleValue;
    }
    return self;
}

- (instancetype)initWithCoder:(NSCoder *)coder {
    if (self = [super init]) {
        _unit = [[coder decodeObjectOfClass:[NSUnit class] forKey:@"unit"] copy];
        _doubleValue = [coder decodeDoubleForKey:@"doubleValue"];
    }
    return self;
}

- (void)encodeWithCoder:(NSCoder *)coder {
    [coder encodeObject:_unit forKey:@"unit"];
    [coder encodeDouble:_doubleValue forKey:@"doubleValue"];
}

- (NSUnit *)unit {
    return _unit;
}

- (double)doubleValue {
    return _doubleValue;
}

- (id)copyWithZone:(NSZone *)zone {
    return self;
}

- (NSString *)description {
    return [NSString stringWithFormat:@"<NSMeasurement: %p> value: %f unit: %s",
            self, _doubleValue, [_unit symbol].UTF8String];
}

- (BOOL)isEqual:(id)other {
    if (self == other) {
        return YES;
    }
    if (![other isKindOfClass:[NSMeasurement class]]) {
        return NO;
    }
    NSMeasurement *measurement = other;
    return _doubleValue == measurement.doubleValue &&
           [_unit isEqual:measurement.unit];
}

- (NSUInteger)hash {
    return [_unit hash] ^ (NSUInteger)_doubleValue;
}

- (BOOL)canBeConvertedToUnit:(NSUnit *)unit {
    return NSMeasurementSameDimension(_unit, unit);
}

- (NSMeasurement *)measurementByConvertingToUnit:(NSUnit *)unit {
    if (!NSMeasurementSameDimension(_unit, unit)) {
        [NSException raise:NSInvalidArgumentException
                    format:@"*** -[NSMeasurement measurementByConvertingToUnit:]: "
                           @"unit %@ is not compatible with %@",
                           unit, _unit];
    }
    double baseValue = [[(NSDimension *)_unit converter] baseUnitValueFromValue:_doubleValue];
    double value = [[(NSDimension *)unit converter] valueFromBaseUnitValue:baseValue];
    return [[NSMeasurement alloc] initWithDoubleValue:value unit:unit];
}

- (NSMeasurement *)measurementByAddingMeasurement:(NSMeasurement *)measurement {
    if (!NSMeasurementSameDimension(_unit, [measurement unit])) {
        [NSException raise:NSInvalidArgumentException
                    format:@"*** -[NSMeasurement measurementByAddingMeasurement:]: "
                           @"unit %@ is not compatible with %@",
                           [measurement unit], _unit];
    }
    double value;
    NSUnit *unit;
    if ([_unit isEqual:[measurement unit]]) {
        value = _doubleValue + [measurement doubleValue];
        unit = _unit;
    } else {
        double baseValue = [[(NSDimension *)_unit converter] baseUnitValueFromValue:_doubleValue];
        double otherBaseValue = [[(NSDimension *)[measurement unit] converter] baseUnitValueFromValue:[measurement doubleValue]];
        value = baseValue + otherBaseValue;
        unit = [[_unit class] baseUnit];
    }
    return [[NSMeasurement alloc] initWithDoubleValue:value unit:unit];
}

- (NSMeasurement *)measurementBySubtractingMeasurement:(NSMeasurement *)measurement {
    if (!NSMeasurementSameDimension(_unit, [measurement unit])) {
        [NSException raise:NSInvalidArgumentException
                    format:@"*** -[NSMeasurement measurementBySubtractingMeasurement:]: "
                           @"unit %@ is not compatible with %@",
                           [measurement unit], _unit];
    }
    double value;
    NSUnit *unit;
    if ([_unit isEqual:[measurement unit]]) {
        value = _doubleValue - [measurement doubleValue];
        unit = _unit;
    } else {
        double baseValue = [[(NSDimension *)_unit converter] baseUnitValueFromValue:_doubleValue];
        double otherBaseValue = [[(NSDimension *)[measurement unit] converter] baseUnitValueFromValue:[measurement doubleValue]];
        value = baseValue - otherBaseValue;
        unit = [[_unit class] baseUnit];
    }
    return [[NSMeasurement alloc] initWithDoubleValue:value unit:unit];
}

@end
