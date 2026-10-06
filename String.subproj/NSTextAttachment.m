/*
 * Copyright (C) 2026, Samuel Zormeister.
 *
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */

#import <Foundation/NSTextAttachment.h>
#import <Foundation/NSDictionary.h>
#import <Foundation/NSData.h>
#import <Foundation/NSString.h>
#import <Foundation/NSCoder.h>

NSAttributedStringKey NSAttachmentAttributeName = @"NSAttachment";

@interface NSTextAttachment () {
    NSData *_contents;
    NSString *_fileType;
}
@end

@implementation NSTextAttachment

- (instancetype)initWithData:(NSData *)contentData
                      ofType:(NSString *)uti {
    if ((self = [super init])) {
        /* Contents and UTI are snapshotted, not borrowed: Apple copies an
         * NSMutableData at assignment time, and the port does the same here. */
        _contents = [contentData copy];
        _fileType = [uti copy];
    }
    return self;
}

/* Apple reads the designated initializer's store through the getters but its
 * -setFileType: writes a different (unused) slot on macOS 26, so a fileType
 * assigned after init never comes back.  The port refuses to enshrine that
 * quirk: both setters store, which is the documented contract. */

- (NSData *)contents {
    return _contents;
}

- (void)setContents:(NSData *)contents {
    _contents = [contents copy];
}

- (NSString *)fileType {
    return _fileType;
}

- (void)setFileType:(NSString *)fileType {
    _fileType = [fileType copy];
}

+ (BOOL)supportsSecureCoding {
    return YES;
}

- (void)encodeWithCoder:(NSCoder *)coder {
    /* Apple's node for a content-bearing attachment also carries an
     * NSFileWrapper whose data is the RTFD serialization of the rich text that
     * contains it, and -initWithCoder: ignores that wrapper: the decoded
     * attachment's contents and fileType survive.  The port therefore encodes
     * nil in the wrapper's place, which Apple's reader receives the same way.
     * The contents and UTI keys are written with the dots as Apple writes
     * them. */
    [coder encodeObject:_contents forKey:@"NS.contents"];
    [coder encodeObject:_fileType forKey:@"NS.fileType"];
    [coder encodeObject:nil forKey:@"NSFileWrapper"];
}

- (instancetype)initWithCoder:(NSCoder *)coder {
    return [self initWithData:[coder decodeObjectOfClass:[NSData class]
                                                  forKey:@"NS.contents"]
                       ofType:[coder decodeObjectOfClass:[NSString class]
                                                   forKey:@"NS.fileType"]];
}

@end

@implementation NSAttributedString (NSAttributedStringAttachmentConveniences)

+ (NSAttributedString *)attributedStringWithAttachment:(NSTextAttachment *)attachment {
    return [self attributedStringWithAttachment:attachment attributes:@{}];
}

+ (NSAttributedString *)attributedStringWithAttachment:(NSTextAttachment *)attachment
                                            attributes:(NSDictionary *)attributes {
    NSString *text = [NSString stringWithFormat:@"%C", (unichar)NSAttachmentCharacter];
    NSDictionary *resolved = attributes ?: @{};
    if (attachment != nil) {
        /* The attachment argument wins over any value already under the key. */
        NSMutableDictionary *merged = [resolved mutableCopy];
        [merged setObject:attachment forKey:NSAttachmentAttributeName];
        resolved = merged;
    }
    return [[NSAttributedString alloc] initWithString:text attributes:resolved];
}

@end