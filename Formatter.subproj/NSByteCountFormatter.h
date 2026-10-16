/*
 * Copyright (C) 2026, Samuel Zormeister.
 *
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */

#ifndef NSByteCountFormatter_h
#define NSByteCountFormatter_h

#import <Foundation/NSFormatter.h>
#import <Foundation/NSObjCRuntime.h>

@class NSString;

typedef NS_OPTIONS(NSUInteger, NSByteCountFormatterUnits) {
    NSByteCountFormatterUseDefault      = 0,
    NSByteCountFormatterUseBytes        = 1UL << 0,
    NSByteCountFormatterUseKB           = 1UL << 1,
    NSByteCountFormatterUseMB           = 1UL << 2,
    NSByteCountFormatterUseGB           = 1UL << 3,
    NSByteCountFormatterUseTB           = 1UL << 4,
    NSByteCountFormatterUsePB           = 1UL << 5,
    NSByteCountFormatterUseEB           = 1UL << 6,
    NSByteCountFormatterUseZB           = 1UL << 7,
    NSByteCountFormatterUseYBOrHigher   = 0x0FFUL << 8,
    NSByteCountFormatterUseAll          = 0x0FFFFUL
};

typedef NS_ENUM(NSInteger, NSByteCountFormatterCountStyle) {
    /* File/storage sizes: decimal (1000-based) on modern macOS. */
    NSByteCountFormatterCountStyleFile   = 0,
    /* Memory sizes: binary (1024-based). */
    NSByteCountFormatterCountStyleMemory = 1,
    /* Force 1000 bytes == 1 KB. */
    NSByteCountFormatterCountStyleDecimal = 2,
    /* Force 1024 bytes == 1 KB. */
    NSByteCountFormatterCountStyleBinary  = 3
};

@interface NSByteCountFormatter : NSFormatter

+ (NSString *)stringFromByteCount:(long long)byteCount
                       countStyle:(NSByteCountFormatterCountStyle)countStyle;

- (NSString *)stringFromByteCount:(long long)byteCount;

- (nullable NSString *)stringForObjectValue:(nullable id)obj;

@property NSByteCountFormatterUnits allowedUnits;
@property NSByteCountFormatterCountStyle countStyle;
@property BOOL allowsNonnumericFormatting;
@property BOOL includesUnit;
@property BOOL includesCount;
@property BOOL includesActualByteCount;
@property (getter=isAdaptive) BOOL adaptive;
@property BOOL zeroPadsFractionDigits;
@property NSFormattingContext formattingContext;

@end

#endif /* NSByteCountFormatter_h */
