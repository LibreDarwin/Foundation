/*
 * Copyright (C) 2026, LibreDarwin
 *
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */

#import <Foundation/NSRange.h>
#import <Foundation/NSString.h>
#import <Foundation/NSScanner.h>
#import <Foundation/NSCharacterSet.h>

NSRange NSUnionRange(NSRange range1, NSRange range2) {
    NSUInteger end1 = NSMaxRange(range1);
    NSUInteger end2 = NSMaxRange(range2);
    NSRange unionRange;
    unionRange.location = range1.location < range2.location ? range1.location : range2.location;
    unionRange.length = (end1 > end2 ? end1 : end2) - unionRange.location;
    return unionRange;
}

NSRange NSIntersectionRange(NSRange range1, NSRange range2) {
    NSUInteger minEnd = NSMaxRange(range1) < NSMaxRange(range2) ? NSMaxRange(range1) : NSMaxRange(range2);
    NSUInteger maxStart = range1.location > range2.location ? range1.location : range2.location;
    NSRange intersectionRange;
    if (minEnd < maxStart) {
        intersectionRange.location = 0;
        intersectionRange.length = 0;
    } else {
        intersectionRange.location = maxStart;
        intersectionRange.length = minEnd - maxStart;
    }
    return intersectionRange;
}

NSString *NSStringFromRange(NSRange range) {
    return [NSString stringWithFormat:@"{%lu, %lu}", (unsigned long)range.location, (unsigned long)range.length];
}

NSRange NSRangeFromString(NSString *aString) {
    NSRange result = NSMakeRange(0, 0);
    if (aString == nil) {
        return result;
    }
    NSScanner *scanner = [NSScanner scannerWithString:aString];
    NSCharacterSet *digits = [NSCharacterSet decimalDigitCharacterSet];
    unsigned long long location = 0, length = 0;
    [scanner scanUpToCharactersFromSet:digits intoString:NULL];
    if ([scanner scanUnsignedLongLong:&location]) {
        [scanner scanUpToCharactersFromSet:digits intoString:NULL];
        [scanner scanUnsignedLongLong:&length];
        result.location = (NSUInteger)location;
        result.length = (NSUInteger)length;
    }
    return result;
}