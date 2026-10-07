/* Copyright (c) 2006-2007 Christopher J. W. Lloyd
   Copyright (c) 2025 xnuports project

Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the "Software"), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE. */

/* NSRegularExpression.m */

#import <Foundation/NSRegularExpression.h>
#import "NSRaise.h"
#import <Foundation/NSTextCheckingResult.h>

@implementation NSRegularExpression

+ (NSRegularExpression *)regularExpressionWithPattern:(NSString *)pattern options:(NSRegularExpressionOptions)options error:(NSError **)error {
    NSUnimplementedMethod();
    return nil;
}

- (instancetype)initWithPattern:(NSString *)pattern options:(NSRegularExpressionOptions)options error:(NSError **)error {
    NSUnimplementedMethod();
    return nil;
}

- (NSString *)pattern {
    return _pattern;
}

- (NSRegularExpressionOptions)options {
    return _options;
}

- (NSUInteger)numberOfCaptureGroups {
    NSUnimplementedMethod();
    return 0;
}

+ (NSString *)escapedPatternForString:(NSString *)string {
    NSUnimplementedMethod();
    return nil;
}

@end

@implementation NSRegularExpression (NSMatching)

- (void)enumerateMatchesInString:(NSString *)string options:(NSMatchingOptions)options range:(NSRange)range usingBlock:(void (^)(NSTextCheckingResult * _Nullable, NSMatchingFlags, BOOL *))block {
    NSUnimplementedMethod();
}

- (NSArray *)matchesInString:(NSString *)string options:(NSMatchingOptions)options range:(NSRange)range {
    NSUnimplementedMethod();
    return nil;
}

- (NSUInteger)numberOfMatchesInString:(NSString *)string options:(NSMatchingOptions)options range:(NSRange)range {
    NSUnimplementedMethod();
    return 0;
}

- (NSTextCheckingResult *)firstMatchInString:(NSString *)string options:(NSMatchingOptions)options range:(NSRange)range {
    NSUnimplementedMethod();
    return nil;
}

- (NSRange)rangeOfFirstMatchInString:(NSString *)string options:(NSMatchingOptions)options range:(NSRange)range {
    NSUnimplementedMethod();
    return NSMakeRange(NSNotFound, 0);
}

@end

@implementation NSRegularExpression (NSReplacement)

- (NSString *)stringByReplacingMatchesInString:(NSString *)string options:(NSMatchingOptions)options range:(NSRange)range withTemplate:(NSString *)templ {
    NSUnimplementedMethod();
    return nil;
}

- (NSUInteger)replaceMatchesInString:(NSMutableString *)string options:(NSMatchingOptions)options range:(NSRange)range withTemplate:(NSString *)templ {
    NSUnimplementedMethod();
    return 0;
}

- (NSString *)replacementStringForResult:(NSTextCheckingResult *)result inString:(NSString *)string offset:(NSInteger)offset template:(NSString *)templ {
    NSUnimplementedMethod();
    return nil;
}

+ (NSString *)escapedTemplateForString:(NSString *)string {
    NSUnimplementedMethod();
    return nil;
}

@end

@implementation NSDataDetector

+ (nullable NSDataDetector *)dataDetectorWithTypes:(NSTextCheckingTypes)checkingTypes error:(NSError **)error {
    NSUnimplementedMethod();
    return nil;
}

- (nullable instancetype)initWithTypes:(NSTextCheckingTypes)checkingTypes error:(NSError **)error {
    NSUnimplementedMethod();
    return nil;
}

@end
