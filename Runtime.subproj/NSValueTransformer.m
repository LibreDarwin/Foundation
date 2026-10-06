/*
 * Copyright (C) 2026, PureDarwin Project.
 *
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 *
 * NSValueTransformer mirrors Apple's class hierarchy transformed from the
 * name-based registry: setValueTransformer:forName:, valueTransformerForName:
 * (with the class-name fallback that instantiates and self-registers), and
 * the four built-in transformers.  The base -transformedValue: passes the
 * value through; -reverseTransformedValue: raises when +allowsReverse-
 * Transformation is NO, as Apple documents.
 */

#import <Foundation/NSValueTransformer.h>
#import <Foundation/NSArray.h>
#import <Foundation/NSData.h>
#import <Foundation/NSDate.h>
#import <Foundation/NSDictionary.h>
#import <Foundation/NSException.h>
#import <Foundation/NSKeyedArchiver.h>
#import <Foundation/NSNull.h>
#import <Foundation/NSSet.h>
#import <Foundation/NSUUID.h>
#import <Foundation/NSNumber.h>
#import <Foundation/NSString.h>

#include <pthread.h>

NSValueTransformerName const NSNegateBooleanTransformerName = @"NSNegateBooleanTransformer";
NSValueTransformerName const NSIsNilTransformerName = @"NSIsNilTransformer";
NSValueTransformerName const NSIsNotNilTransformerName = @"NSIsNotNilTransformer";

NSValueTransformerName const NSUnarchiveFromDataTransformerName = @"NSUnarchiveFromDataTransformer";
NSValueTransformerName const NSKeyedUnarchiveFromDataTransformerName = @"NSKeyedUnarchiveFromDataTransformer";
NSValueTransformerName const NSSecureUnarchiveFromDataTransformerName = @"NSSecureUnarchiveFromDataTransformer";

static NSMutableDictionary *NSVTRegistry = nil;
static pthread_mutex_t NSVTRegistryLock = PTHREAD_MUTEX_INITIALIZER;

static void NSVTRegisterBuiltins(void);

@implementation NSValueTransformer

+ (void)setValueTransformer:(nullable NSValueTransformer *)transformer forName:(NSValueTransformerName)name {
    if (name == nil) {
        [NSException raise:NSInvalidArgumentException format:@"value transformer name must not be nil"];
    }
    pthread_mutex_lock(&NSVTRegistryLock);
    if (NSVTRegistry == nil) NSVTRegistry = [NSMutableDictionary dictionary];
    if (transformer == nil) {
        [NSVTRegistry removeObjectForKey:name];
    } else {
        [NSVTRegistry setObject:transformer forKey:name];
    }
    pthread_mutex_unlock(&NSVTRegistryLock);
}

+ (nullable NSValueTransformer *)valueTransformerForName:(NSValueTransformerName)name {
    if (name == nil) return nil;
    pthread_mutex_lock(&NSVTRegistryLock);
    if (NSVTRegistry == nil) NSVTRegistry = [NSMutableDictionary dictionary];
    NSValueTransformer *transformer = [NSVTRegistry objectForKey:name];
    pthread_mutex_unlock(&NSVTRegistryLock);
    if (transformer == nil) {
        /* Class-name fallback: instantiate a class named by the transformer name. */
        Class cls = NSClassFromString(name);
        if (cls != Nil && [cls isSubclassOfClass:[NSValueTransformer class]]) {
            transformer = [(NSValueTransformer *)[cls alloc] init];
            if (transformer) {
                [self setValueTransformer:transformer forName:name];
            }
        }
    }
    return transformer;
}

+ (NSArray<NSValueTransformerName> *)valueTransformerNames {
    pthread_mutex_lock(&NSVTRegistryLock);
    if (NSVTRegistry == nil) NSVTRegistry = [NSMutableDictionary dictionary];
    NSArray *names = [NSVTRegistry allKeys];
    pthread_mutex_unlock(&NSVTRegistryLock);
    return names;
}

+ (nullable Class)transformedValueClass {
    return Nil;
}

+ (BOOL)allowsReverseTransformation {
    return NO;
}

- (nullable id)transformedValue:(nullable id)value {
    return value;
}

- (nullable id)reverseTransformedValue:(nullable id)value {
    if (![[self class] allowsReverseTransformation]) {
        [NSException raise:NSInvalidArgumentException
                    format:@"value transformer %@ does not allow reverse transformations", [self class]];
    }
    return [self transformedValue:value];
}

@end

/* ---- built-in transformers ---- */

@interface _NSNegateBooleanTransformer : NSValueTransformer @end
@implementation _NSNegateBooleanTransformer
+ (Class)transformedValueClass { return [NSNumber class]; }
+ (BOOL)allowsReverseTransformation { return YES; }
- (id)transformedValue:(id)value {
    return [NSNumber numberWithBool:![[NSNumber numberWithBool:value ? [value boolValue] : NO] boolValue]];
}
- (id)reverseTransformedValue:(id)value {
    return [self transformedValue:value];
}
@end

@interface _NSIsNilTransformer : NSValueTransformer @end
@implementation _NSIsNilTransformer
+ (Class)transformedValueClass { return [NSNumber class]; }
+ (BOOL)allowsReverseTransformation { return YES; }
- (id)transformedValue:(id)value {
    return [NSNumber numberWithBool:(value == nil)];
}
@end

@interface _NSIsNotNilTransformer : NSValueTransformer @end
@implementation _NSIsNotNilTransformer
+ (Class)transformedValueClass { return [NSNumber class]; }
+ (BOOL)allowsReverseTransformation { return YES; }
- (id)transformedValue:(id)value {
    return [NSNumber numberWithBool:(value != nil)];
}
@end

/* Coding wrapper: the generic table-available classes for secure unarchive,
 * mirroring Apple's documented default allowed-top-level class list. */
static NSArray *NSSecureUnarchiveAllowedClasses(void) {
    return [NSArray arrayWithObjects:
            [NSArray class], [NSDictionary class], [NSSet class],
            [NSString class], [NSNumber class], [NSData class],
            [NSDate class], [NSNull class], [NSUUID class], nil];
}

@interface NSSecureUnarchiveFromDataTransformer : NSValueTransformer @end
@implementation NSSecureUnarchiveFromDataTransformer
+ (Class)transformedValueClass { return Nil; }
+ (BOOL)allowsReverseTransformation { return YES; }
+ (NSArray *)allowedTopLevelClasses {
    return NSSecureUnarchiveAllowedClasses();
}
- (id)transformedValue:(id)value {
    if (value == nil) return nil;
    NSError *error = nil;
    id result = [NSKeyedUnarchiver unarchivedObjectOfClasses:[NSSecureUnarchiveFromDataTransformer allowedTopLevelClasses]
                                                   fromData:value
                                                      error:&error];
    return result;
}
- (id)reverseTransformedValue:(id)value {
    if (value == nil) return nil;
    NSError *error = nil;
    return [NSKeyedArchiver archivedDataWithRootObject:value requiringSecureCoding:YES error:&error];
}
@end

/* Deprecated legacy transformers: plain (unsecure) keyed unarchiving. */
@interface _NSUnarchiveFromDataTransformer : NSValueTransformer @end
@interface _NSKeyedUnarchiveFromDataTransformer : NSValueTransformer @end
@implementation _NSUnarchiveFromDataTransformer
+ (Class)transformedValueClass { return [NSData class]; }
+ (BOOL)allowsReverseTransformation { return YES; }
- (id)transformedValue:(id)value {
    if (value == nil) return nil;
    return [NSKeyedUnarchiver unarchiveObjectWithData:value];
}
- (id)reverseTransformedValue:(id)value {
    if (value == nil) return nil;
    return [NSKeyedArchiver archivedDataWithRootObject:value];
}
@end
@implementation _NSKeyedUnarchiveFromDataTransformer
+ (Class)transformedValueClass { return [NSData class]; }
+ (BOOL)allowsReverseTransformation { return YES; }
- (id)transformedValue:(id)value {
    if (value == nil) return nil;
    return [NSKeyedUnarchiver unarchiveObjectWithData:value];
}
- (id)reverseTransformedValue:(id)value {
    if (value == nil) return nil;
    return [NSKeyedArchiver archivedDataWithRootObject:value];
}
@end

static void NSVTRegisterBuiltins(void) {
    static BOOL registered = NO;
    if (registered) return;
    registered = YES;
    [NSValueTransformer setValueTransformer:[[_NSNegateBooleanTransformer alloc] init]
                                    forName:NSNegateBooleanTransformerName];
    [NSValueTransformer setValueTransformer:[[_NSIsNilTransformer alloc] init]
                                    forName:NSIsNilTransformerName];
    [NSValueTransformer setValueTransformer:[[_NSIsNotNilTransformer alloc] init]
                                    forName:NSIsNotNilTransformerName];
    [NSValueTransformer setValueTransformer:[[NSSecureUnarchiveFromDataTransformer alloc] init]
                                    forName:NSSecureUnarchiveFromDataTransformerName];
    /* deprecated names resolve to the legacy transformers */
    [NSValueTransformer setValueTransformer:[[_NSUnarchiveFromDataTransformer alloc] init]
                                    forName:NSUnarchiveFromDataTransformerName];
    [NSValueTransformer setValueTransformer:[[_NSKeyedUnarchiveFromDataTransformer alloc] init]
                                    forName:NSKeyedUnarchiveFromDataTransformerName];
}

__attribute__((constructor))
static void NSVTInitialize(void) {
    NSVTRegisterBuiltins();
}