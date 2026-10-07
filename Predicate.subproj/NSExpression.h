/*
 * Copyright (C) 2026, PureDarwin Project.
 *
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 *
 * This header mirrors Apple's NSExpression.h.
 */

#import <Foundation/NSObject.h>

#if !defined(__FOUNDATION_NSEXPRESSION__)
#define __FOUNDATION_NSEXPRESSION__ 1

@class NSString;
@class NSArray;
@class NSMutableDictionary;
@class NSPredicate;

NS_HEADER_AUDIT_BEGIN(nullability, sendability)

typedef NS_ENUM(NSUInteger, NSExpressionType) {
    NSConstantValueExpressionType = 0,
    NSEvaluatedObjectExpressionType,
    NSVariableExpressionType,
    NSKeyPathExpressionType,
    NSFunctionExpressionType,
    NSUnionSetExpressionType API_AVAILABLE(macos(10.5), ios(3.0), watchos(2.0), tvos(9.0)),
    NSIntersectSetExpressionType API_AVAILABLE(macos(10.5), ios(3.0), watchos(2.0), tvos(9.0)),
    NSMinusSetExpressionType API_AVAILABLE(macos(10.5), ios(3.0), watchos(2.0), tvos(9.0)),
    NSSubqueryExpressionType API_AVAILABLE(macos(10.5), ios(3.0), watchos(2.0), tvos(9.0)) = 13,
    NSAggregateExpressionType API_AVAILABLE(macos(10.5), ios(3.0), watchos(2.0), tvos(9.0)) = 14,
    NSAnyKeyExpressionType API_AVAILABLE(macos(10.9), ios(7.0), watchos(2.0), tvos(9.0)) = 15,
    NSBlockExpressionType = 19,
    NSConditionalExpressionType API_AVAILABLE(macos(10.11), ios(9.0), watchos(2.0), tvos(9.0)) = 20
};

API_AVAILABLE(macos(10.4), ios(3.0), watchos(2.0), tvos(9.0))
@interface NSExpression : NSObject <NSSecureCoding, NSCopying> {
    @package
    struct _expressionFlags {
        unsigned int _evaluationBlocked:1;
        unsigned int _usesKVC:1;
        unsigned int _validatedExpression:1;
        unsigned int _validatedKeys:1;
        unsigned int _reservedExpressionFlags:28;
    } _expressionFlags;
    NSExpressionType _expressionType;
}

+ (NSExpression *)expressionWithFormat:(NSString *)expressionFormat argumentArray:(NSArray *)arguments API_AVAILABLE(macos(10.6), ios(4.0), watchos(2.0), tvos(9.0));
+ (NSExpression *)expressionWithFormat:(NSString *)expressionFormat, ...  API_AVAILABLE(macos(10.6), ios(4.0), watchos(2.0), tvos(9.0));
+ (NSExpression *)expressionWithFormat:(NSString *)expressionFormat arguments:(va_list)argList API_AVAILABLE(macos(10.6), ios(4.0), watchos(2.0), tvos(9.0));

+ (NSExpression *)expressionForConstantValue:(nullable id)obj;
+ (NSExpression *)expressionForEvaluatedObject;
+ (NSExpression *)expressionForVariable:(NSString *)string;
+ (NSExpression *)expressionForKeyPath:(NSString *)keyPath;
+ (NSExpression *)expressionForFunction:(NSString *)name arguments:(NSArray *)parameters;

+ (NSExpression *)expressionForAggregate:(NSArray *)subexpressions API_AVAILABLE(macos(10.5), ios(3.0), watchos(2.0), tvos(9.0));
+ (NSExpression *)expressionForUnionSet:(NSExpression *)left with:(NSExpression *)right API_AVAILABLE(macos(10.5), ios(3.0), watchos(2.0), tvos(9.0));
+ (NSExpression *)expressionForIntersectSet:(NSExpression *)left with:(NSExpression *)right API_AVAILABLE(macos(10.5), ios(3.0), watchos(2.0), tvos(9.0));
+ (NSExpression *)expressionForMinusSet:(NSExpression *)left with:(NSExpression *)right API_AVAILABLE(macos(10.5), ios(3.0), watchos(2.0), tvos(9.0));
+ (NSExpression *)expressionForSubquery:(NSExpression *)expression usingIteratorVariable:(NSString *)variable predicate:(NSPredicate *)predicate API_AVAILABLE(macos(10.5), ios(3.0), watchos(2.0), tvos(9.0));
+ (NSExpression *)expressionForFunction:(NSExpression *)target selectorName:(NSString *)name arguments:(nullable NSArray *)parameters API_AVAILABLE(macos(10.5), ios(3.0), watchos(2.0), tvos(9.0));
+ (NSExpression *)expressionForAnyKey API_AVAILABLE(macos(10.9), ios(7.0), watchos(2.0), tvos(9.0));
+ (NSExpression *)expressionForBlock:(id (^)(id _Nullable evaluatedObject, NSArray *expressions, NSMutableDictionary * _Nullable context))block arguments:(nullable NSArray *)arguments API_AVAILABLE(macos(10.6), ios(4.0), watchos(2.0), tvos(9.0));
+ (NSExpression *)expressionForConditional:(NSPredicate *)predicate trueExpression:(NSExpression *)trueExpression falseExpression:(NSExpression *)falseExpression  API_AVAILABLE(macos(10.11), ios(9.0), watchos(2.0), tvos(9.0));

- (instancetype)initWithExpressionType:(NSExpressionType)type NS_DESIGNATED_INITIALIZER;
- (nullable instancetype)initWithCoder:(NSCoder *)coder NS_DESIGNATED_INITIALIZER;

@property (readonly) NSExpressionType expressionType;
@property (nullable, readonly, retain) id constantValue;
@property (readonly, copy) NSString *keyPath;
@property (readonly, copy) NSString *function;
@property (readonly, copy) NSString *variable;
@property (readonly, copy) NSExpression *operand;
@property (nullable, readonly, copy) NSArray *arguments;

@property (readonly, retain) id collection API_AVAILABLE(macos(10.5), ios(3.0), watchos(2.0), tvos(9.0));
@property (readonly, copy) NSPredicate *predicate API_AVAILABLE(macos(10.5), ios(3.0), watchos(2.0), tvos(9.0));
@property (readonly, copy) NSExpression *leftExpression API_AVAILABLE(macos(10.5), ios(3.0), watchos(2.0), tvos(9.0));
@property (readonly, copy) NSExpression *rightExpression API_AVAILABLE(macos(10.5), ios(3.0), watchos(2.0), tvos(9.0));

@property (readonly, copy) NSExpression *trueExpression API_AVAILABLE(macos(10.11), ios(9.0), watchos(2.0), tvos(9.0));
@property (readonly, copy) NSExpression *falseExpression API_AVAILABLE(macos(10.11), ios(9.0), watchos(2.0), tvos(9.0));

@property (readonly, copy) id (^expressionBlock)(id _Nullable, NSArray *, NSMutableDictionary * _Nullable) API_AVAILABLE(macos(10.6), ios(4.0), watchos(2.0), tvos(9.0));

- (nullable id)expressionValueWithObject:(nullable id)object context:(nullable NSMutableDictionary *)context;

- (void)allowEvaluation API_AVAILABLE(macos(10.9), ios(7.0), watchos(2.0), tvos(9.0));

@end

NS_HEADER_AUDIT_END(nullability, sendability)
#endif /* defined __FOUNDATION_NSEXPRESSION__ */