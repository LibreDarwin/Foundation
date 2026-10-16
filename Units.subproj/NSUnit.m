#import <Foundation/NSUnit.h>
#import <Foundation/NSRaise.h>
#import <Foundation/NSCoder.h>

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

@implementation NSDimension {
@private
    NSUnitConverter *_converter;
}

+ (BOOL)supportsSecureCoding {
    return YES;
}

- (instancetype)initWithSymbol:(NSString *)symbol converter:(NSUnitConverter *)converter {
    self = [super initWithSymbol:symbol];
    if (self) {
        _converter = [converter copy];
    }
    return self;
}

- (instancetype)initWithCoder:(NSCoder *)coder {
    if (self = [super initWithCoder:coder]) {
        _converter = [[coder decodeObjectOfClass:[NSUnitConverterLinear class] forKey:@"converter"] copy];
    }
    return self;
}

- (void)encodeWithCoder:(NSCoder *)coder {
    [super encodeWithCoder:coder];
    [coder encodeObject:_converter forKey:@"converter"];
}

- (NSUnitConverter *)converter {
    return _converter;
}

+ (instancetype)baseUnit {
    return nil;
}

@end

@implementation NSUnitInformationStorage

+ (instancetype)_unitWithSymbol:(NSString *)symbol coefficient:(double)coefficient {
    return [[self alloc] initWithSymbol:symbol
                              converter:[[NSUnitConverterLinear alloc] initWithCoefficient:coefficient]];
}

+ (instancetype)baseUnit {
    return [self bytes];
}

+ (NSUnitInformationStorage *)bytes {
    return [self _unitWithSymbol:@"B" coefficient:1.0];
}

+ (NSUnitInformationStorage *)bits {
    return [self _unitWithSymbol:@"bit" coefficient:0.125];
}

+ (NSUnitInformationStorage *)nibbles {
    return [self _unitWithSymbol:@"nibble" coefficient:0.5];
}

+ (NSUnitInformationStorage *)kilobytes {
    return [self _unitWithSymbol:@"kB" coefficient:1000.0];
}

+ (NSUnitInformationStorage *)megabytes {
    return [self _unitWithSymbol:@"MB" coefficient:1000000.0];
}

+ (NSUnitInformationStorage *)gigabytes {
    return [self _unitWithSymbol:@"GB" coefficient:1000000000.0];
}

+ (NSUnitInformationStorage *)terabytes {
    return [self _unitWithSymbol:@"TB" coefficient:1000000000000.0];
}

+ (NSUnitInformationStorage *)petabytes {
    return [self _unitWithSymbol:@"PB" coefficient:1000000000000000.0];
}

+ (NSUnitInformationStorage *)exabytes {
    return [self _unitWithSymbol:@"EB" coefficient:1.0e18];
}

+ (NSUnitInformationStorage *)zettabytes {
    return [self _unitWithSymbol:@"ZB" coefficient:1.0e21];
}

+ (NSUnitInformationStorage *)yottabytes {
    return [self _unitWithSymbol:@"YB" coefficient:1.0e24];
}

+ (NSUnitInformationStorage *)kilobits {
    return [self _unitWithSymbol:@"kb" coefficient:125.0];
}

+ (NSUnitInformationStorage *)megabits {
    return [self _unitWithSymbol:@"Mb" coefficient:125000.0];
}

+ (NSUnitInformationStorage *)gigabits {
    return [self _unitWithSymbol:@"Gb" coefficient:1.25e8];
}

+ (NSUnitInformationStorage *)terabits {
    return [self _unitWithSymbol:@"Tb" coefficient:1.25e11];
}

+ (NSUnitInformationStorage *)petabits {
    return [self _unitWithSymbol:@"Pb" coefficient:1.25e14];
}

+ (NSUnitInformationStorage *)exabits {
    return [self _unitWithSymbol:@"Eb" coefficient:1.25e17];
}

+ (NSUnitInformationStorage *)zettabits {
    return [self _unitWithSymbol:@"Zb" coefficient:1.25e20];
}

+ (NSUnitInformationStorage *)yottabits {
    return [self _unitWithSymbol:@"Yb" coefficient:1.25e23];
}

+ (NSUnitInformationStorage *)kibibytes {
    return [self _unitWithSymbol:@"KiB" coefficient:1024.0];
}

+ (NSUnitInformationStorage *)mebibytes {
    return [self _unitWithSymbol:@"MiB" coefficient:1048576.0];
}

+ (NSUnitInformationStorage *)gibibytes {
    return [self _unitWithSymbol:@"GiB" coefficient:1073741824.0];
}

+ (NSUnitInformationStorage *)tebibytes {
    return [self _unitWithSymbol:@"TiB" coefficient:1099511627776.0];
}

+ (NSUnitInformationStorage *)pebibytes {
    return [self _unitWithSymbol:@"PiB" coefficient:1125899906842624.0];
}

+ (NSUnitInformationStorage *)exbibytes {
    return [self _unitWithSymbol:@"EiB" coefficient:1152921504606846976.0];
}

+ (NSUnitInformationStorage *)zebibytes {
    return [self _unitWithSymbol:@"ZiB" coefficient:1180591620717411303424.0];
}

+ (NSUnitInformationStorage *)yobibytes {
    return [self _unitWithSymbol:@"YiB" coefficient:1208925819614629174706176.0];
}

+ (NSUnitInformationStorage *)kibibits {
    return [self _unitWithSymbol:@"Kib" coefficient:128.0];
}

+ (NSUnitInformationStorage *)mebibits {
    return [self _unitWithSymbol:@"Mib" coefficient:131072.0];
}

+ (NSUnitInformationStorage *)gibibits {
    return [self _unitWithSymbol:@"Gib" coefficient:134217728.0];
}

+ (NSUnitInformationStorage *)tebibits {
    return [self _unitWithSymbol:@"Tib" coefficient:137438953472.0];
}

+ (NSUnitInformationStorage *)pebibits {
    return [self _unitWithSymbol:@"Pib" coefficient:140737488355328.0];
}

+ (NSUnitInformationStorage *)exbibits {
    return [self _unitWithSymbol:@"Eib" coefficient:144115188075855872.0];
}

+ (NSUnitInformationStorage *)zebibits {
    return [self _unitWithSymbol:@"Zib" coefficient:147573952589676412928.0];
}

+ (NSUnitInformationStorage *)yobibits {
    return [self _unitWithSymbol:@"Yib" coefficient:151115727451828646838272.0];
}

@end
