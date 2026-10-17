/*
 * Copyright (C) 2026, LibreDarwin.
 *
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */

#import <Foundation/NSUnit.h>
#import <Foundation/NSMeasurement.h>
#import <Foundation/NSRaise.h>
#import <Foundation/NSCoder.h>
#import <Foundation/NSSet.h>
#include <math.h>

NSExceptionName const NSUnitErrorDomain = @"NSUnitErrorDomain";

@implementation NSUnitConverter

- (id)copyWithZone:(NSZone *)zone {
    return self;
}

- (double)baseUnitValueFromValue:(double)value {
    return value;
}

- (double)valueFromBaseUnitValue:(double)baseUnitValue {
    return baseUnitValue;
}

@end

@implementation NSUnitConverterLinear {
@private
    double _coefficient;
    double _constant;
}

+ (BOOL)supportsSecureCoding {
    return YES;
}

- (instancetype)initWithCoefficient:(double)coefficient {
    return [self initWithCoefficient:coefficient constant:0.0];
}

- (instancetype)initWithCoefficient:(double)coefficient constant:(double)constant {
    self = [super init];
    if (self) {
        _coefficient = coefficient;
        _constant = constant;
    }
    return self;
}

- (instancetype)initWithCoder:(NSCoder *)coder {
    if (self = [super init]) {
        _coefficient = [coder decodeDoubleForKey:@"coefficient"];
        _constant = [coder decodeDoubleForKey:@"constant"];
    }
    return self;
}

- (void)encodeWithCoder:(NSCoder *)coder {
    [coder encodeDouble:_coefficient forKey:@"coefficient"];
    [coder encodeDouble:_constant forKey:@"constant"];
}

- (double)coefficient {
    return _coefficient;
}

- (double)constant {
    return _constant;
}

- (double)baseUnitValueFromValue:(double)value {
    return _coefficient * value + _constant;
}

- (double)valueFromBaseUnitValue:(double)baseUnitValue {
    return (baseUnitValue - _constant) / _coefficient;
}

@end

@implementation NSUnit {
@protected
    NSString *_symbol;
}

+ (BOOL)supportsSecureCoding {
    return YES;
}

- (instancetype)initWithSymbol:(NSString *)symbol {
    self = [super init];
    if (self) {
        _symbol = [symbol copy];
    }
    return self;
}

- (instancetype)initWithCoder:(NSCoder *)coder {
    if (self = [super init]) {
        _symbol = [[coder decodeObjectOfClass:[NSString class] forKey:@"symbol"] copy];
    }
    return self;
}

- (void)encodeWithCoder:(NSCoder *)coder {
    [coder encodeObject:_symbol forKey:@"symbol"];
}

- (NSString *)symbol {
    return _symbol;
}

- (id)copyWithZone:(NSZone *)zone {
    return self;
}

- (BOOL)isEqual:(id)other {
    if (self == other) {
        return YES;
    }
    if (![other isKindOfClass:[NSUnit class]]) {
        return NO;
    }
    return [self isMemberOfClass:[other class]] &&
           [_symbol isEqualToString:[(NSUnit *)other symbol]];
}

- (NSUInteger)hash {
    return [_symbol hash];
}

@end

@interface NSDimension ()
- (instancetype)_initWithSymbol:(NSString *)symbol
                      converter:(NSUnitConverter *)converter
                      specifier:(NSInteger)specifier;
+ (NSMeasurement *)_measurementWithNaturalScale:(NSMeasurement *)measurement
                                         system:(NSInteger)system;
@end

@implementation NSDimension {
@private
    NSUnitConverter *_converter;
    NSInteger _specifier;
}

+ (BOOL)supportsSecureCoding {
    return YES;
}

- (instancetype)initWithSymbol:(NSString *)symbol converter:(NSUnitConverter *)converter {
    return [self _initWithSymbol:symbol converter:converter specifier:-1];
}

- (instancetype)_initWithSymbol:(NSString *)symbol
                      converter:(NSUnitConverter *)converter
                      specifier:(NSInteger)specifier {
    self = [super initWithSymbol:symbol];
    if (self) {
        _converter = [converter copy];
        _specifier = specifier;
    }
    return self;
}

- (instancetype)initWithCoder:(NSCoder *)coder {
    if (self = [super initWithCoder:coder]) {
        _converter = [[coder decodeObjectOfClass:[NSUnitConverterLinear class] forKey:@"converter"] copy];
        _specifier = [coder decodeIntegerForKey:@"specifier"];
    }
    return self;
}

- (void)encodeWithCoder:(NSCoder *)coder {
    [super encodeWithCoder:coder];
    [coder encodeObject:_converter forKey:@"converter"];
    [coder encodeInteger:_specifier forKey:@"specifier"];
}

- (NSUnitConverter *)converter {
    return _converter;
}

- (NSInteger)specifier {
    return _specifier;
}

+ (instancetype)baseUnit {
    return nil;
}

/* By default a dimension is already at its natural scale. */
+ (NSMeasurement *)_measurementWithNaturalScale:(NSMeasurement *)measurement
                                         system:(NSInteger)system {
    return measurement;
}

@end

/* ICU UMeasureUnit identifiers.  Only these storage units have an ICU
 * counterpart; every other unit (nibbles, the *ibi* binary units, petabits,
 * exa- and above) carries -1 and is localized through its symbol. */
enum {
    kICUBit         = 0xE00,
    kICUByte        = 0xE01,
    kICUGigabit     = 0xE02,
    kICUGigabyte    = 0xE03,
    kICUKilobit     = 0xE04,
    kICUKilobyte    = 0xE05,
    kICUMegabit     = 0xE06,
    kICUMegabyte    = 0xE07,
    kICUTerabit     = 0xE08,
    kICUTerabyte    = 0xE09,
    kICUPetabyte    = 0xE0A
};

@implementation NSUnitInformationStorage

+ (instancetype)_unitWithSymbol:(NSString *)symbol
                      coefficient:(double)coefficient
                        specifier:(NSInteger)specifier {
    return [[self alloc] _initWithSymbol:symbol
                               converter:[[NSUnitConverterLinear alloc] initWithCoefficient:coefficient]
                               specifier:specifier];
}

+ (instancetype)baseUnit {
    return [self bytes];
}

+ (NSUnitInformationStorage *)bytes {
    return [self _unitWithSymbol:@"B" coefficient:1.0 specifier:kICUByte];
}

+ (NSUnitInformationStorage *)bits {
    return [self _unitWithSymbol:@"bit" coefficient:0.125 specifier:kICUBit];
}

+ (NSUnitInformationStorage *)nibbles {
    return [self _unitWithSymbol:@"nibble" coefficient:0.5 specifier:-1];
}

+ (NSUnitInformationStorage *)kilobytes {
    return [self _unitWithSymbol:@"kB" coefficient:1000.0 specifier:kICUKilobyte];
}

+ (NSUnitInformationStorage *)megabytes {
    return [self _unitWithSymbol:@"MB" coefficient:1000000.0 specifier:kICUMegabyte];
}

+ (NSUnitInformationStorage *)gigabytes {
    return [self _unitWithSymbol:@"GB" coefficient:1000000000.0 specifier:kICUGigabyte];
}

+ (NSUnitInformationStorage *)terabytes {
    return [self _unitWithSymbol:@"TB" coefficient:1000000000000.0 specifier:kICUTerabyte];
}

+ (NSUnitInformationStorage *)petabytes {
    return [self _unitWithSymbol:@"PB" coefficient:1000000000000000.0 specifier:kICUPetabyte];
}

+ (NSUnitInformationStorage *)exabytes {
    return [self _unitWithSymbol:@"EB" coefficient:1.0e18 specifier:-1];
}

+ (NSUnitInformationStorage *)zettabytes {
    return [self _unitWithSymbol:@"ZB" coefficient:1.0e21 specifier:-1];
}

+ (NSUnitInformationStorage *)yottabytes {
    return [self _unitWithSymbol:@"YB" coefficient:1.0e24 specifier:-1];
}

+ (NSUnitInformationStorage *)kilobits {
    return [self _unitWithSymbol:@"kb" coefficient:125.0 specifier:kICUKilobit];
}

+ (NSUnitInformationStorage *)megabits {
    return [self _unitWithSymbol:@"Mb" coefficient:125000.0 specifier:kICUMegabit];
}

+ (NSUnitInformationStorage *)gigabits {
    return [self _unitWithSymbol:@"Gb" coefficient:1.25e8 specifier:kICUGigabit];
}

+ (NSUnitInformationStorage *)terabits {
    return [self _unitWithSymbol:@"Tb" coefficient:1.25e11 specifier:kICUTerabit];
}

+ (NSUnitInformationStorage *)petabits {
    return [self _unitWithSymbol:@"Pb" coefficient:1.25e14 specifier:-1];
}

+ (NSUnitInformationStorage *)exabits {
    return [self _unitWithSymbol:@"Eb" coefficient:1.25e17 specifier:-1];
}

+ (NSUnitInformationStorage *)zettabits {
    return [self _unitWithSymbol:@"Zb" coefficient:1.25e20 specifier:-1];
}

+ (NSUnitInformationStorage *)yottabits {
    return [self _unitWithSymbol:@"Yb" coefficient:1.25e23 specifier:-1];
}

+ (NSUnitInformationStorage *)kibibytes {
    return [self _unitWithSymbol:@"KiB" coefficient:1024.0 specifier:-1];
}

+ (NSUnitInformationStorage *)mebibytes {
    return [self _unitWithSymbol:@"MiB" coefficient:1048576.0 specifier:-1];
}

+ (NSUnitInformationStorage *)gibibytes {
    return [self _unitWithSymbol:@"GiB" coefficient:1073741824.0 specifier:-1];
}

+ (NSUnitInformationStorage *)tebibytes {
    return [self _unitWithSymbol:@"TiB" coefficient:1099511627776.0 specifier:-1];
}

+ (NSUnitInformationStorage *)pebibytes {
    return [self _unitWithSymbol:@"PiB" coefficient:1125899906842624.0 specifier:-1];
}

+ (NSUnitInformationStorage *)exbibytes {
    return [self _unitWithSymbol:@"EiB" coefficient:1152921504606846976.0 specifier:-1];
}

+ (NSUnitInformationStorage *)zebibytes {
    return [self _unitWithSymbol:@"ZiB" coefficient:1180591620717411303424.0 specifier:-1];
}

+ (NSUnitInformationStorage *)yobibytes {
    return [self _unitWithSymbol:@"YiB" coefficient:1208925819614629174706176.0 specifier:-1];
}

+ (NSUnitInformationStorage *)kibibits {
    return [self _unitWithSymbol:@"Kib" coefficient:128.0 specifier:-1];
}

+ (NSUnitInformationStorage *)mebibits {
    return [self _unitWithSymbol:@"Mib" coefficient:131072.0 specifier:-1];
}

+ (NSUnitInformationStorage *)gibibits {
    return [self _unitWithSymbol:@"Gib" coefficient:134217728.0 specifier:-1];
}

+ (NSUnitInformationStorage *)tebibits {
    return [self _unitWithSymbol:@"Tib" coefficient:137438953472.0 specifier:-1];
}

+ (NSUnitInformationStorage *)pebibits {
    return [self _unitWithSymbol:@"Pib" coefficient:140737488355328.0 specifier:-1];
}

+ (NSUnitInformationStorage *)exbibits {
    return [self _unitWithSymbol:@"Eib" coefficient:144115188075855872.0 specifier:-1];
}

+ (NSUnitInformationStorage *)zebibits {
    return [self _unitWithSymbol:@"Zib" coefficient:147573952589676412928.0 specifier:-1];
}

+ (NSUnitInformationStorage *)yobibits {
    return [self _unitWithSymbol:@"Yib" coefficient:151115727451828646838272.0 specifier:-1];
}

/* The 16 binary (power-of-1024) units.  A measurement made with one of these
 * scales in the binary system; everything else scales in the decimal system. */
+ (NSSet *)_binaryUnits {
    static NSSet *set = nil;
    if (set == nil) {
        set = [[NSSet alloc] initWithObjects:
            [self kibibytes], [self mebibytes], [self gibibytes], [self tebibytes],
            [self pebibytes], [self exbibytes], [self zebibytes], [self yobibytes],
            [self kibibits], [self mebibits], [self gibibits], [self tebibits],
            [self pebibits], [self exbibits], [self zebibits], [self yobibits],
            nil];
    }
    return set;
}

/* The unit for one bit of the "allowed unit" mask used by the file-size
 * algorithm: bit 0 is the base unit (bytes), each following bit steps up a
 * prefix.  allowBinary selects the 1024-based (NO) or 1000-based (YES) family. */
+ (NSUnitInformationStorage *)_unitForAllowedUnitBit:(NSUInteger)bit
                                         allowBinary:(BOOL)allowBinary {
    switch (bit) {
        case 1UL << 0: return [self bytes];
        case 1UL << 1: return allowBinary ? [self kilobytes] : [self kibibytes];
        case 1UL << 2: return allowBinary ? [self megabytes] : [self mebibytes];
        case 1UL << 3: return allowBinary ? [self gigabytes] : [self gibibytes];
        case 1UL << 4: return allowBinary ? [self terabytes] : [self tebibytes];
        case 1UL << 5: return allowBinary ? [self petabytes] : [self pebibytes];
        case 1UL << 6: return allowBinary ? [self exabytes] : [self exbibytes];
        case 1UL << 7: return allowBinary ? [self zettabytes] : [self zebibytes];
        default:       return allowBinary ? [self yottabytes] : [self yobibytes];
    }
}

/* Number of fractional digits used to round each candidate when choosing the
 * file-size unit (see __NSMeasurementConvertedForFileSizeDescription). */
static NSInteger _fractionDigitsForStep(NSUInteger step) {
    static const NSInteger digits[] = {0, 0, 1, 2, 2, 2, 2, 2, 2};
    return (step < (sizeof(digits) / sizeof(digits[0]))) ? digits[step] : 0;
}

/* Re-expresses a measurement in the largest information-storage unit that
 * still keeps its rounded magnitude below base.  mask selects the candidate
 * steps, base is 1000 (decimal) or 1024 (binary) and allowBinary picks the
 * family.  This mirrors Apple's private
 * __NSMeasurementConvertedForFileSizeDescription. */
+ (NSMeasurement *)_measurementConvertedForFileSizeDescription:(NSMeasurement *)measurement
                                                          mask:(NSUInteger)mask
                                                   allowBinary:(BOOL)allowBinary
                                                          base:(NSUInteger)base {
    double bytes = [[measurement measurementByConvertingToUnit:[self bytes]] doubleValue];
    NSUInteger count = 16;
    NSInteger highest = -1;
    NSUInteger step = 0;
    for (; step != count; step++) {
        if (mask & ((NSUInteger)1 << step)) highest = (NSInteger)step;
        NSUnitInformationStorage *candidate =
            [self _unitForAllowedUnitBit:((NSUInteger)1 << step) allowBinary:allowBinary];
        double magnitude = bytes / [(NSUnitConverterLinear *)[candidate converter] coefficient];
        double scale = pow(10.0, (double)_fractionDigitsForStep(step));
        double rounded = fabs(round(magnitude * scale) / scale);
        if (rounded < (double)base && highest >= 0) break;
    }
    NSUInteger index = (highest < 0) ? (count - 1) : (NSUInteger)highest;
    NSUnitInformationStorage *unit =
        [self _unitForAllowedUnitBit:((NSUInteger)1 << index) allowBinary:allowBinary];
    return [measurement measurementByConvertingToUnit:unit];
}

/* Storage's natural scale: leave sub-byte magnitudes (and negatives) alone,
 * otherwise walk up to the largest unit that fits. */
+ (NSMeasurement *)_measurementWithNaturalScale:(NSMeasurement *)measurement
                                         system:(NSInteger)system {
    double bytes = [[measurement measurementByConvertingToUnit:[self bytes]] doubleValue];
    double coefficient = [(NSUnitConverterLinear *)[[self bytes] converter] coefficient];
    if (bytes < coefficient) {
        return measurement;
    }
    BOOL binary = [[self _binaryUnits] containsObject:[measurement unit]];
    NSUInteger base = binary ? 1024 : 1000;
    return [self _measurementConvertedForFileSizeDescription:measurement
                                                        mask:0xffff
                                                 allowBinary:!binary
                                                        base:base];
}

@end
