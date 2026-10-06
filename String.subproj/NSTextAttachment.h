/*
 * Copyright (C) 2026, Samuel Zormeister.
 *
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */

#ifndef NSTextAttachment_h
#define NSTextAttachment_h

#import <Foundation/NSObject.h>
#import <Foundation/NSCoder.h>
#import <Foundation/NSAttributedString.h>

/* The port surfaces NSTextAttachment and NSAttachmentAttributeName from
 * Foundation, where Apple keeps them behind AppKit (its NSTextAttachment.h
 * rests on UIFoundation).  LibreDarwin has no AppKit in this stack, so the
 * AppKit-dependent surface -- image, bounds, fileWrapper, cell, view provider
 * and the NSTextAttachmentLayout protocol -- is deliberately omitted. */

@class NSData;

enum {
    NSAttachmentCharacter = 0xFFFC /* Replacement character is used for attachments */
};

FOUNDATION_EXPORT NSAttributedStringKey NSAttachmentAttributeName;

@interface NSTextAttachment : NSObject <NSSecureCoding>

- (instancetype)initWithData:(nullable NSData *)contentData
                      ofType:(nullable NSString *)uti;

/* The contents are copied on assignment (an NSMutableData passed in is
 * permanently snapshotted), and -fileType is stored verbatim. */
@property (nullable, copy) NSData *contents;
@property (nullable, copy) NSString *fileType;

- (void)encodeWithCoder:(NSCoder *)coder;
- (nullable instancetype)initWithCoder:(NSCoder *)coder;
+ (BOOL)supportsSecureCoding;

@end

@interface NSAttributedString (NSAttributedStringAttachmentConveniences)

/* A one-character string holding NSAttachmentCharacter, whose
 * NSAttachmentAttributeName attribute is the given NSTextAttachment.  The
 * attachment itself is not copied: the same instance is the attribute value. */
+ (NSAttributedString *)attributedStringWithAttachment:(NSTextAttachment *)attachment;

/* As above, but NSAttachmentAttributeName is merged into the given attributes
 * (the attachment argument wins over any value already under the key) rather
 * than being added to an empty dictionary. */
+ (NSAttributedString *)attributedStringWithAttachment:(NSTextAttachment *)attachment
                                            attributes:(NSDictionary<NSAttributedStringKey, id> *)attributes;

@end

#endif /* NSTextAttachment_h */