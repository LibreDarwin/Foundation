#ifndef __NSMEASUREMENT_H
#define __NSMEASUREMENT_H 1

#import <Foundation/NSObject.h>
#import <Foundation/NSUnit.h>

NS_ASSUME_NONNULL_BEGIN

@interface NSMeasurement<__covariant UnitType : NSUnit *> : NSObject <NSCopying, NSSecureCoding>

@property (readonly, copy) UnitType unit;
@property (readonly) double doubleValue;

- (instancetype)init NS_UNAVAILABLE;
- (instancetype)initWithDoubleValue:(double)doubleValue unit:(UnitType)unit NS_DESIGNATED_INITIALIZER;

- (BOOL)canBeConvertedToUnit:(NSUnit *)unit;
- (NSMeasurement *)measurementByConvertingToUnit:(UnitType)unit;
- (NSMeasurement<UnitType> *)measurementByAddingMeasurement:(NSMeasurement<UnitType> *)measurement;
- (NSMeasurement<UnitType> *)measurementBySubtractingMeasurement:(NSMeasurement<UnitType> *)measurement;

@end

NS_ASSUME_NONNULL_END

#endif
