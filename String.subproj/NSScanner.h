/*
 * Copyright (C) 2026, PureDarwin Project.
 *
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 *
 * The scanner state machine is adapted from Cocotron Foundation's
 * NSScanner implementation by Christopher J. W. Lloyd and Markus Hitter,
 * used under its MIT license. The original implementation is kept at
 * local/ravynos/Frameworks/Foundation/NSScanner.
 */

#ifndef NSScanner_h
#define NSScanner_h

#import <Foundation/NSObject.h>
#import <Foundation/NSString.h>
#import <Foundation/NSCharacterSet.h>

@class NSDictionary;

@interface NSScanner : NSObject <NSCopying> {
    NSString *_string;
    NSCharacterSet *_charactersToBeSkipped;
    id _locale;
    NSUInteger _scanLocation;
    BOOL _caseSensitive;
}

+ (instancetype)scannerWithString:(NSString *)string;
+ (instancetype)localizedScannerWithString:(NSString *)string;

- (instancetype)initWithString:(NSString *)string;

@property (readonly, copy) NSString *string;
@property NSUInteger scanLocation;
@property (copy) NSCharacterSet *charactersToBeSkipped;
@property BOOL caseSensitive;
@property (retain) id locale;
@property (readonly, getter=isAtEnd) BOOL atEnd;

- (BOOL)scanInt:(int *)result;
- (BOOL)scanInteger:(NSInteger *)result;
- (BOOL)scanLongLong:(long long *)result;
- (BOOL)scanUnsignedLongLong:(unsigned long long *)result;
- (BOOL)scanFloat:(float *)result;
- (BOOL)scanDouble:(double *)result;
- (BOOL)scanHexInt:(unsigned *)result;
- (BOOL)scanHexLongLong:(unsigned long long *)result;
- (BOOL)scanHexFloat:(float *)result;
- (BOOL)scanHexDouble:(double *)result;

- (BOOL)scanString:(NSString *)string intoString:(NSString **)result;
- (BOOL)scanCharactersFromSet:(NSCharacterSet *)set intoString:(NSString **)result;
- (BOOL)scanUpToString:(NSString *)string intoString:(NSString **)result;
- (BOOL)scanUpToCharactersFromSet:(NSCharacterSet *)set intoString:(NSString **)result;

@end

#endif /* NSScanner_h */
