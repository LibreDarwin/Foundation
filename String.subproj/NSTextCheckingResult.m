/* Copyright (c) 2006-2007 Christopher J. W. Lloyd
   Copyright (c) 2025 xnuports project

Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the "Software"), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE. */

#import <Foundation/NSTextCheckingResult.h>
#import "NSRaise.h"
#import <Foundation/NSDictionary.h>

@implementation NSTextCheckingResult

- (instancetype)initWithResultType:(NSTextCheckingType)resultType range:(NSRange)range properties:(NSDictionary *)properties {
   _resultType = resultType;
   _range = range;
   _properties = [properties copy];
   return self;
}

- (instancetype)initWithResultType:(NSTextCheckingType)resultType range:(NSRange)range property:(id)property name:(NSString *)name {
   NSDictionary *properties = [NSDictionary dictionaryWithObjectsAndKeys:property, name, nil];
   return [self initWithResultType:resultType range:range properties:properties];
}

+ (NSTextCheckingResult *)addressCheckingResultWithRange:(NSRange)range components:(NSDictionary *)components {
    NSUnimplementedMethod();
    return nil;
}

+ (NSTextCheckingResult *)correctionCheckingResultWithRange:(NSRange)range replacementString:(NSString *)replacement {
    NSUnimplementedMethod();
    return nil;
}

+ (NSTextCheckingResult *)dashCheckingResultWithRange:(NSRange)range replacementString:(NSString *)replacement {
    NSUnimplementedMethod();
    return nil;
}

+ (NSTextCheckingResult *)dateCheckingResultWithRange:(NSRange)range date:(NSDate *)date {
    NSUnimplementedMethod();
    return nil;
}

+ (NSTextCheckingResult *)dateCheckingResultWithRange:(NSRange)range date:(NSDate *)date timeZone:(NSTimeZone *)timeZone duration:(NSTimeInterval)duration {
    NSUnimplementedMethod();
    return nil;
}

+ (NSTextCheckingResult *)grammarCheckingResultWithRange:(NSRange)range details:(NSArray *)details {
    NSUnimplementedMethod();
    return nil;
}

+ (NSTextCheckingResult *)linkCheckingResultWithRange:(NSRange)range URL:(NSURL *)url {
    NSUnimplementedMethod();
    return nil;
}

+ (NSTextCheckingResult *)orthographyCheckingResultWithRange:(NSRange)range orthography:(NSOrthography *)orthography {
    NSUnimplementedMethod();
    return nil;
}

+ (NSTextCheckingResult *)quoteCheckingResultWithRange:(NSRange)range replacementString:(NSString *)replacement {
    NSUnimplementedMethod();
    return nil;
}

+ (NSTextCheckingResult *)replacementCheckingResultWithRange:(NSRange)range replacementString:(NSString *)replacement {
    NSUnimplementedMethod();
    return nil;
}

+ (NSTextCheckingResult *)spellCheckingResultWithRange:(NSRange)range {
   return [[self alloc] initWithResultType:NSTextCheckingTypeSpelling range:range properties:nil];
}

- (NSDictionary *)addressComponents {
    NSUnimplementedMethod();
    return nil;
}

- (NSDate *)date {
    NSUnimplementedMethod();
    return nil;
}

- (NSTimeInterval)duration {
    NSUnimplementedMethod();
    return 0;
}

- (NSArray *)grammarDetails {
    NSUnimplementedMethod();
    return nil;
}

- (NSOrthography *)orthography {
    NSUnimplementedMethod();
    return nil;
}

- (NSRange)range {
    return _range;
}

- (NSString *)replacementString {
    NSUnimplementedMethod();
    return nil;
}

- (NSTextCheckingType)resultType {
    return _resultType;
}

- (NSTimeZone *)timeZone {
    NSUnimplementedMethod();
    return nil;
}

- (NSURL *)URL {
    NSUnimplementedMethod();
    return nil;
}

+ (NSTextCheckingResult *)regularExpressionCheckingResultWithRanges:(NSRange *)ranges count:(NSUInteger)count regularExpression:(NSRegularExpression *)regularExpression {
    NSUnimplementedMethod();
    return nil;
}

+ (NSTextCheckingResult *)phoneNumberCheckingResultWithRange:(NSRange)range phoneNumber:(NSString *)phoneNumber {
    NSUnimplementedMethod();
    return nil;
}

+ (NSTextCheckingResult *)transitInformationCheckingResultWithRange:(NSRange)range components:(NSDictionary *)components {
    NSUnimplementedMethod();
    return nil;
}

+ (NSTextCheckingResult *)correctionCheckingResultWithRange:(NSRange)range replacementString:(NSString *)replacementString alternativeStrings:(NSArray *)alternativeStrings {
    NSUnimplementedMethod();
    return nil;
}

- (NSRange)rangeAtIndex:(NSUInteger)idx {
    NSUnimplementedMethod();
    return NSMakeRange(NSNotFound, 0);
}

- (NSTextCheckingResult *)resultByAdjustingRangesWithOffset:(NSInteger)offset {
    NSUnimplementedMethod();
    return nil;
}

- (NSArray *)alternativeStrings {
    NSUnimplementedMethod();
    return nil;
}

- (NSString *)phoneNumber {
    NSUnimplementedMethod();
    return nil;
}

- (NSRegularExpression *)regularExpression {
    NSUnimplementedMethod();
    return nil;
}

- (NSDictionary *)components {
    NSUnimplementedMethod();
    return nil;
}

@end
