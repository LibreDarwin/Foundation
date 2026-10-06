/*
 * Copyright (C) 2026, PureDarwin Project.
 *
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 *
 * This header mirrors Apple's NSValueTransformer.h.
 */

#import <Foundation/NSObject.h>

#if !defined(__FOUNDATION_NSVALUETRANSFORMER__)
#define __FOUNDATION_NSVALUETRANSFORMER__ 1

NS_HEADER_AUDIT_BEGIN(nullability, sendability)

@class NSArray<ObjectType>, NSString;

API_AVAILABLE(macos(10.5), ios(2.0))
typedef NSString *NSValueTransformerName NS_EXTENSIBLE_STRING_ENUM;

FOUNDATION_EXPORT NSValueTransformerName const NSNegateBooleanTransformerName;
FOUNDATION_EXPORT NSValueTransformerName const NSIsNilTransformerName;
FOUNDATION_EXPORT NSValueTransformerName const NSIsNotNilTransformerName;

FOUNDATION_EXPORT NSValueTransformerName const NSUnarchiveFromDataTransformerName API_DEPRECATED("This transformer is not able to guarantee security of the decoded data. Use NSSecureUnarchiveFromDataTransformerName instead.", macos(10.5, 10.13), ios(2.0, 11.0), watchos(2.0, 4.0), tvos(9.0, 11.0));
FOUNDATION_EXPORT NSValueTransformerName const NSKeyedUnarchiveFromDataTransformerName API_DEPRECATED("This transformer is not able to guarantee security of the decoded data. Use NSSecureUnarchiveFromDataTransformerName instead.", macos(10.5, 10.13), ios(2.0, 11.0), watchos(2.0, 4.0), tvos(9.0, 11.0));
FOUNDATION_EXPORT NSValueTransformerName const NSSecureUnarchiveFromDataTransformerName API_AVAILABLE(macos(10.13), ios(11.0), watchos(4.0), tvos(11.0));

API_AVAILABLE(macos(10.5), ios(2.0))
@interface NSValueTransformer : NSObject

// name-based registry

+ (void)setValueTransformer:(nullable NSValueTransformer *)transformer forName:(NSValueTransformerName)name;
+ (nullable NSValueTransformer *)valueTransformerForName:(NSValueTransformerName)name;

// takes precedence over the above
+ (NSArray<NSValueTransformerName> *)valueTransformerNames;

// class of the value returned by transformedValue:. Must be subclassed.
+ (nullable Class)transformedValueClass;

// Returns YES if the receiver can reverse a transformation. Must be subclassed.
+ (BOOL)allowsReverseTransformation;

- (nullable id)transformedValue:(nullable id)value;           // abstract, must be subclassed
- (nullable id)reverseTransformedValue:(nullable id)value;    // default raises if allowsReverseTransformation == NO

@end

NS_HEADER_AUDIT_END(nullability, sendability)
#endif // defined __FOUNDATION_NSVALUETRANSFORMER__