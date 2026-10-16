/*
 * Copyright (C) 2026, Samuel Zormeister.
 *
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */

#ifndef NSListFormatter_h
#define NSListFormatter_h

#import <Foundation/NSFormatter.h>
#import <Foundation/NSObject.h>
#import <Foundation/NSArray.h>

@class NSString, NSLocale, NSFormatter;

/* NSListFormatter joins an array of already-displayable items with the
 * locale's list separator and conjunction ("a, b, and c").  It performs no
 * capitalization adjustment; it is meant for standalone lists. */
@interface NSListFormatter : NSFormatter

/* The locale used for the separator/conjunction.  Defaults to the
 * autoupdating current locale; assigning nil resets it. */
@property (null_resettable, copy) NSLocale *locale;

/* Optional formatter applied to each item before joining.  When nil, each
 * item is rendered with -descriptionWithLocale: or -description. */
@property (nullable, copy) NSFormatter *itemFormatter;

/* Convenience: join strings with the current locale's list format. */
+ (NSString *)localizedStringByJoiningStrings:(NSArray *)strings;

/* Join an array of items (each run through itemFormatter).  Returns nil when
 * the list formatter cannot render every item. */
- (nullable NSString *)stringFromItems:(NSArray *)items;

- (nullable NSString *)stringForObjectValue:(nullable id)obj;

@end

#endif /* NSListFormatter_h */
