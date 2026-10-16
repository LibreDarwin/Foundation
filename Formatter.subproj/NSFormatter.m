/*
 * Copyright (C) 2026, Samuel Zormeister.
 *
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 *
 * NSFormatter is abstract.  Its "convert a value to a string" entry points
 * raise NSInvalidArgumentException when reached on the base class, exactly as
 * Apple's do; the parsing/validation entry points that have a sane identity
 * default answer it (attributedStringForObjectValue: returns nil,
 * isPartialStringValid:... returns YES).
 */

#import <Foundation/NSFormatter.h>
#import <Foundation/NSString.h>
#import <Foundation/NSAttributedString.h>
#import <Foundation/NSDictionary.h>
#import <Foundation/NSException.h>
#import <Foundation/NSObjCRuntime.h>
#import <Foundation/NSCoder.h>

@implementation NSFormatter

- (NSString *)stringForObjectValue:(id)obj {
    [NSException raise:NSInvalidArgumentException
                format:@"*** -stringForObjectValue: cannot be sent to an abstract object of class %@: Create a concrete instance!",
                       NSStringFromClass([self class])];
    return nil;
}

- (NSAttributedString *)attributedStringForObjectValue:(id)obj
                                  withDefaultAttributes:(NSDictionary *)attrs {
    return nil;
}

- (NSString *)editingStringForObjectValue:(id)obj {
    /* Apple's -editingStringForObjectValue: reports the abstract invocation
     * under -stringForObjectValue:'s name, so mirror that wording. */
    [NSException raise:NSInvalidArgumentException
                format:@"*** -stringForObjectValue: cannot be sent to an abstract object of class %@: Create a concrete instance!",
                       NSStringFromClass([self class])];
    return nil;
}

- (BOOL)getObjectValue:(id *)obj
             forString:(NSString *)string
      errorDescription:(NSString **)error {
    [NSException raise:NSInvalidArgumentException
                format:@"*** -getObjectValue:forString:errorDescription: cannot be sent to an abstract object of class %@: Create a concrete instance!",
                       NSStringFromClass([self class])];
    return NO;
}

- (BOOL)isPartialStringValid:(NSString *)partialString
            newEditingString:(NSString **)newString
            errorDescription:(NSString **)error {
    return YES;
}

- (BOOL)isPartialStringValid:(NSString **)partialStringPtr
        proposedSelectedRange:(NSRange *)proposedSelRangePtr
               originalString:(NSString *)origString
        originalSelectedRange:(NSRange)origSelRange
             errorDescription:(NSString **)error {
    /* The compatibility contract: the selection-range variant forwards to the
     * older three-argument method and, if that returns a replacement string,
     * installs it and moves the selection to its end. */
    NSString *newString = nil;
    BOOL result = [self isPartialStringValid:*partialStringPtr
                             newEditingString:&newString
                             errorDescription:error];
    if (newString != nil) {
        *partialStringPtr = newString;
        if (proposedSelRangePtr != NULL) {
            *proposedSelRangePtr = NSMakeRange([newString length], 0);
        }
    }
    return result;
}

#pragma mark NSCopying / NSCoding

- (id)copyWithZone:(NSZone *)zone {
    return self;
}

- (void)encodeWithCoder:(NSCoder *)coder {
}

- (instancetype)initWithCoder:(NSCoder *)coder {
    return [super init];
}

@end
