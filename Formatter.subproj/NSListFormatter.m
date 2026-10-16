/*
 * Copyright (C) 2026, Samuel Zormeister.
 *
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 *
 * NSListFormatter joins items with the locale's list separator and
 * conjunction: for English, "a", "a and b", "a, b, and c" (an Oxford comma
 * before the final "and"); German and French drop the comma before their
 * conjunction.  Full CLDR list-pattern data is out of scope here, so the
 * three languages the behavior gate pins fall back to the English pattern.
 */

#import <Foundation/NSListFormatter.h>
#import <Foundation/NSLocale.h>
#import <Foundation/NSArray.h>
#import <Foundation/NSString.h>
#import <Foundation/NSNumber.h>
#import <Foundation/NSDate.h>

typedef struct {
    NSString *item;   /* between adjacent items */
    NSString *final;  /* before the last item in a list of three or more */
    NSString *two;    /* between exactly two items */
} NSListSeparators;

@implementation NSListFormatter {
    NSLocale *_locale;
    NSFormatter *_itemFormatter;
}

- (NSLocale *)locale {
    return _locale != nil ? _locale : [NSLocale autoupdatingCurrentLocale];
}

- (void)setLocale:(NSLocale *)locale {
    _locale = [locale copy];
}

- (NSFormatter *)itemFormatter {
    return _itemFormatter;
}

- (void)setItemFormatter:(NSFormatter *)itemFormatter {
    /* Stored without -copy: the port's NSNumberFormatter is not copyable, and
     * callers routinely hand it over as an NSFormatter. */
    _itemFormatter = itemFormatter;
}

- (NSListSeparators)_separators {
    NSString *language = [[self locale] objectForKey:NSLocaleLanguageCode];
    if ([language hasPrefix:@"de"]) {
        return (NSListSeparators){ @", ", @" und ", @" und " };
    }
    if ([language hasPrefix:@"fr"]) {
        return (NSListSeparators){ @", ", @" et ", @" et " };
    }
    return (NSListSeparators){ @", ", @", and ", @" and " };
}

- (NSString *)_stringForItem:(id)item {
    if (_itemFormatter != nil) {
        NSString *formatted = [_itemFormatter stringForObjectValue:item];
        if (formatted != nil) {
            return formatted;
        }
    }
    if ([item respondsToSelector:@selector(descriptionWithLocale:)]) {
        return [item descriptionWithLocale:[self locale]];
    }
    return [item description];
}

- (NSString *)_joinParts:(NSArray *)parts {
    NSUInteger count = [parts count];
    if (count == 0) {
        return @"";
    }
    if (count == 1) {
        return [parts objectAtIndex:0];
    }

    NSListSeparators separators = [self _separators];
    if (count == 2) {
        return [NSString stringWithFormat:@"%@%@%@",
                [parts objectAtIndex:0], separators.two, [parts objectAtIndex:1]];
    }

    NSMutableString *result = [NSMutableString string];
    for (NSUInteger i = 0; i + 1 < count; i++) {
        if (i > 0) {
            [result appendString:separators.item];
        }
        [result appendString:[parts objectAtIndex:i]];
    }
    [result appendString:separators.final];
    [result appendString:[parts objectAtIndex:count - 1]];
    return result;
}

- (NSString *)stringFromItems:(NSArray *)items {
    if (items == nil) {
        return nil;
    }

    NSMutableArray *parts = [NSMutableArray arrayWithCapacity:[items count]];
    for (id item in items) {
        NSString *part = [self _stringForItem:item];
        if (part == nil) {
            return nil;
        }
        [parts addObject:part];
    }
    return [self _joinParts:parts];
}

- (NSString *)stringForObjectValue:(id)obj {
    if ([obj isKindOfClass:[NSArray class]]) {
        return [self stringFromItems:obj];
    }
    return nil;
}

+ (NSString *)localizedStringByJoiningStrings:(NSArray *)strings {
    NSListFormatter *formatter = [[NSListFormatter alloc] init];
    return [formatter stringFromItems:strings];
}

@end
