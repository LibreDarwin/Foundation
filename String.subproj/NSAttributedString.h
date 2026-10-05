/*
 * Copyright (C) 2026, Samuel Zormeister.
 *
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */

#ifndef NSAttributedString_h
#define NSAttributedString_h

#import <Foundation/NSObject.h>
#import <Foundation/NSRange.h>
#import <Foundation/NSString.h>
#import <Foundation/NSDictionary.h>

typedef NSString *NSAttributedStringKey NS_TYPED_EXTENSIBLE_ENUM;

typedef NS_OPTIONS(NSUInteger, NSAttributedStringEnumerationOptions) {
  NSAttributedStringEnumerationReverse = (1UL << 1),
  NSAttributedStringEnumerationLongestEffectiveRangeNotRequired = (1UL << 20)
};

@interface NSAttributedString : NSObject <NSCopying, NSMutableCopying>

/* NSAttributedString owns a CFAttributedString rather than bridging to it, for
 * the reason documented beside NSAttributedStringBacking() in
 * NSAttributedString.m: CoreFoundation registers its own NSAttributedString
 * before this library loads, so a toll-free port class would lose every
 * instance method. */

@property (readonly, copy) NSString *string;
@property (readonly) NSUInteger length;

- (NSDictionary<NSAttributedStringKey, id> *)attributesAtIndex:(NSUInteger)location
                                                effectiveRange:(NSRangePointer)range;

- (id)attribute:(NSAttributedStringKey)attrName
        atIndex:(NSUInteger)location
 effectiveRange:(NSRangePointer)range;

- (NSDictionary<NSAttributedStringKey, id> *)
    attributesAtIndex:(NSUInteger)location
  longestEffectiveRange:(NSRangePointer)range
              inRange:(NSRange)rangeLimit;

- (id)attribute:(NSAttributedStringKey)attrName
        atIndex:(NSUInteger)location
 longestEffectiveRange:(NSRangePointer)range
        inRange:(NSRange)rangeLimit;

- (NSAttributedString *)attributedSubstringFromRange:(NSRange)range;

- (BOOL)isEqualToAttributedString:(NSAttributedString *)other;

- (instancetype)initWithString:(NSString *)str;
- (instancetype)initWithString:(NSString *)str
                    attributes:(NSDictionary<NSAttributedStringKey, id> *)attrs;
- (instancetype)initWithAttributedString:(NSAttributedString *)attrStr;

- (void)enumerateAttributesInRange:(NSRange)enumerationRange
                           options:(NSAttributedStringEnumerationOptions)opts
                        usingBlock:(void (NS_NOESCAPE ^)(NSDictionary<NSAttributedStringKey, id> *attrs,
                                                         NSRange range, BOOL *stop))block;

- (void)enumerateAttribute:(NSAttributedStringKey)attrName
                   inRange:(NSRange)enumerationRange
                   options:(NSAttributedStringEnumerationOptions)opts
                usingBlock:(void (NS_NOESCAPE ^)(id value, NSRange range, BOOL *stop))block;

@end

@interface NSMutableAttributedString : NSAttributedString

- (void)replaceCharactersInRange:(NSRange)range withString:(NSString *)str;
- (void)setAttributes:(NSDictionary<NSAttributedStringKey, id> *)attrs range:(NSRange)range;

@property (readonly, retain) NSMutableString *mutableString;

- (void)addAttribute:(NSAttributedStringKey)name value:(id)value range:(NSRange)range;
- (void)addAttributes:(NSDictionary<NSAttributedStringKey, id> *)attrs range:(NSRange)range;
- (void)removeAttribute:(NSAttributedStringKey)name range:(NSRange)range;

- (void)replaceCharactersInRange:(NSRange)range
         withAttributedString:(NSAttributedString *)attrString;
- (void)insertAttributedString:(NSAttributedString *)attrString atIndex:(NSUInteger)loc;
- (void)appendAttributedString:(NSAttributedString *)attrString;
- (void)deleteCharactersInRange:(NSRange)range;
- (void)setAttributedString:(NSAttributedString *)attrString;

- (void)beginEditing;
- (void)endEditing;

@end

#endif /* NSAttributedString_h */
