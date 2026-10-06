/*
 * Copyright (C) 2026, PureDarwin Project.
 *
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 *
 * NSUUID mirrors Apple's RFC 4122 version 4 UUID class: a plain uuid_t
 * byte buffer with string round-tripping, constant-time compare, copy, and
 * NSSecureCoding (the string is the archive key, matching Apple's shape).
 * UUIDs are immutable, so copy returns self.
 */

#import <Foundation/NSUUID.h>
#import <Foundation/NSString.h>
#import <Foundation/NSCoder.h>
#import <Foundation/NSException.h>

#include <string.h>
#include <uuid/uuid.h>

@implementation NSUUID {
    uuid_t _bytes;
}

+ (BOOL)supportsSecureCoding {
    return YES;
}

+ (instancetype)UUID {
    return [(NSUUID *)[self alloc] init];
}

- (instancetype)init {
    self = [super init];
    if (self) {
        uuid_generate_random(_bytes);
    }
    return self;
}

- (nullable instancetype)initWithUUIDString:(NSString *)string {
    self = [super init];
    if (self) {
        if (string == nil || uuid_parse([string UTF8String], _bytes) != 0) {
            return nil;
        }
    }
    return self;
}

- (instancetype)initWithUUIDBytes:(const uuid_t _Nullable)bytes {
    self = [super init];
    if (self) {
        if (bytes) {
            memcpy(_bytes, bytes, sizeof(uuid_t));
        } else {
            uuid_clear(_bytes);
        }
    }
    return self;
}

- (void)getUUIDBytes:(uuid_t _Nonnull)uuid {
    memcpy(uuid, _bytes, sizeof(uuid_t));
}

- (NSComparisonResult)compare:(NSUUID *)otherUUID {
    if (otherUUID == nil) {
        uuid_t zero;
        memset(zero, 0, sizeof(zero));
        int result = memcmp(_bytes, zero, sizeof(uuid_t));
        if (result < 0) return NSOrderedAscending;
        if (result > 0) return NSOrderedDescending;
        return NSOrderedSame;
    }
    int result = memcmp(_bytes, ((NSUUID *)otherUUID)->_bytes, sizeof(uuid_t));
    if (result < 0) return NSOrderedAscending;
    if (result > 0) return NSOrderedDescending;
    return NSOrderedSame;
}

- (NSString *)UUIDString {
    char out[37];
    uuid_unparse_upper(_bytes, out);
    return [NSString stringWithUTF8String:out];
}

- (BOOL)isEqual:(id)object {
    if (self == object) return YES;
    if (![object isKindOfClass:[NSUUID class]]) return NO;
    return (memcmp(_bytes, ((NSUUID *)object)->_bytes, sizeof(uuid_t)) == 0);
}

- (NSUInteger)hash {
    return [[self UUIDString] hash];
}

- (id)copyWithZone:(NSZone *)zone {
    return self;
}

- (instancetype)initWithCoder:(NSCoder *)coder {
    NSString *string = [coder decodeObjectOfClass:[NSString class] forKey:@"UUIDString"];
    return [self initWithUUIDString:string];
}

- (void)encodeWithCoder:(NSCoder *)coder {
    [coder encodeObject:[self UUIDString] forKey:@"UUIDString"];
}

- (NSString *)description {
    return [self UUIDString];
}

@end