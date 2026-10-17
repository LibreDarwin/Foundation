/*
 * Copyright (C) 2026, LibreDarwin.
 *
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */

#import <Foundation/NSPersonNameComponents.h>
#import <Foundation/NSCoder.h>
#import <Foundation/NSSet.h>
#import <Foundation/NSArray.h>
#import <Foundation/NSKeyedArchiver.h>

/* The seven name fields live in a private value object, mirroring Apple's
   layout: NSPersonNameComponents holds a single _private ivar pointing at a
   _NSPersonNameComponentsData, and the keyed archive stores that data object
   under "NS.nameComponentsPrivate". */

@interface _NSPersonNameComponentsData : NSObject <NSCopying, NSSecureCoding> {
@private
    NSString *_namePrefix;
    NSString *_givenName;
    NSString *_middleName;
    NSString *_familyName;
    NSString *_nameSuffix;
    NSString *_nickname;
    NSPersonNameComponents *_phoneticRepresentation;
}
@property (copy, nullable) NSString *namePrefix;
@property (copy, nullable) NSString *givenName;
@property (copy, nullable) NSString *middleName;
@property (copy, nullable) NSString *familyName;
@property (copy, nullable) NSString *nameSuffix;
@property (copy, nullable) NSString *nickname;
@property (copy, nullable) NSPersonNameComponents *phoneticRepresentation;
@end

@implementation _NSPersonNameComponentsData

+ (BOOL)supportsSecureCoding {
    return YES;
}

- (instancetype)initWithCoder:(NSCoder *)coder {
    if ((self = [super init])) {
        _namePrefix = [[coder decodeObjectOfClass:[NSString class] forKey:@"NS.namePrefix"] copy];
        _givenName = [[coder decodeObjectOfClass:[NSString class] forKey:@"NS.givenName"] copy];
        _middleName = [[coder decodeObjectOfClass:[NSString class] forKey:@"NS.middleName"] copy];
        _familyName = [[coder decodeObjectOfClass:[NSString class] forKey:@"NS.familyName"] copy];
        _nameSuffix = [[coder decodeObjectOfClass:[NSString class] forKey:@"NS.nameSuffix"] copy];
        _nickname = [[coder decodeObjectOfClass:[NSString class] forKey:@"NS.nickname"] copy];
        _phoneticRepresentation = [[coder decodeObjectOfClass:[NSPersonNameComponents class]
                                                       forKey:@"NS.phoneticRepresentation"] copy];
    }
    return self;
}

- (void)encodeWithCoder:(NSCoder *)coder {
    [coder encodeObject:_namePrefix forKey:@"NS.namePrefix"];
    [coder encodeObject:_givenName forKey:@"NS.givenName"];
    [coder encodeObject:_middleName forKey:@"NS.middleName"];
    [coder encodeObject:_familyName forKey:@"NS.familyName"];
    [coder encodeObject:_nameSuffix forKey:@"NS.nameSuffix"];
    [coder encodeObject:_nickname forKey:@"NS.nickname"];
    [coder encodeObject:_phoneticRepresentation forKey:@"NS.phoneticRepresentation"];
}

- (id)copyWithZone:(NSZone *)zone {
    _NSPersonNameComponentsData *copy = [[_NSPersonNameComponentsData allocWithZone:zone] init];
    copy->_namePrefix = [_namePrefix copy];
    copy->_givenName = [_givenName copy];
    copy->_middleName = [_middleName copy];
    copy->_familyName = [_familyName copy];
    copy->_nameSuffix = [_nameSuffix copy];
    copy->_nickname = [_nickname copy];
    copy->_phoneticRepresentation = [_phoneticRepresentation copy];
    return copy;
}

- (NSString *)namePrefix { return _namePrefix; }
- (NSString *)givenName { return _givenName; }
- (NSString *)middleName { return _middleName; }
- (NSString *)familyName { return _familyName; }
- (NSString *)nameSuffix { return _nameSuffix; }
- (NSString *)nickname { return _nickname; }
- (NSPersonNameComponents *)phoneticRepresentation { return _phoneticRepresentation; }

- (void)setNamePrefix:(NSString *)namePrefix { _namePrefix = [namePrefix copy]; }
- (void)setGivenName:(NSString *)givenName { _givenName = [givenName copy]; }
- (void)setMiddleName:(NSString *)middleName { _middleName = [middleName copy]; }
- (void)setFamilyName:(NSString *)familyName { _familyName = [familyName copy]; }
- (void)setNameSuffix:(NSString *)nameSuffix { _nameSuffix = [nameSuffix copy]; }
- (void)setNickname:(NSString *)nickname { _nickname = [nickname copy]; }
- (void)setPhoneticRepresentation:(NSPersonNameComponents *)phoneticRepresentation {
    _phoneticRepresentation = [phoneticRepresentation copy];
}

- (BOOL)isEqual:(id)other {
    if (self == other) {
        return YES;
    }
    if (![other isKindOfClass:[_NSPersonNameComponentsData class]]) {
        return NO;
    }
    _NSPersonNameComponentsData *data = other;
    return (_namePrefix == data->_namePrefix || [_namePrefix isEqual:data->_namePrefix]) &&
           (_givenName == data->_givenName || [_givenName isEqual:data->_givenName]) &&
           (_middleName == data->_middleName || [_middleName isEqual:data->_middleName]) &&
           (_familyName == data->_familyName || [_familyName isEqual:data->_familyName]) &&
           (_nameSuffix == data->_nameSuffix || [_nameSuffix isEqual:data->_nameSuffix]) &&
           (_nickname == data->_nickname || [_nickname isEqual:data->_nickname]) &&
           (_phoneticRepresentation == data->_phoneticRepresentation ||
            [_phoneticRepresentation isEqual:data->_phoneticRepresentation]);
}

- (NSUInteger)hash {
    NSUInteger hash = 0;
    if (_namePrefix) hash ^= [_namePrefix hash];
    if (_givenName) hash ^= [_givenName hash] << 1;
    if (_middleName) hash ^= [_middleName hash] << 2;
    if (_familyName) hash ^= [_familyName hash] << 3;
    if (_nameSuffix) hash ^= [_nameSuffix hash] << 4;
    if (_nickname) hash ^= [_nickname hash] << 5;
    if (_phoneticRepresentation) hash ^= [_phoneticRepresentation hash] << 6;
    return hash;
}

@end

@implementation NSPersonNameComponents

- (_NSPersonNameComponentsData *)_data {
    if (_private == nil) {
        _private = [[_NSPersonNameComponentsData alloc] init];
    }
    return _private;
}

+ (BOOL)supportsSecureCoding {
    return YES;
}

- (instancetype)initWithCoder:(NSCoder *)coder {
    if ((self = [super init])) {
        _private = [coder decodeObjectOfClass:[_NSPersonNameComponentsData class]
                                       forKey:@"NS.nameComponentsPrivate"];
    }
    return self;
}

- (void)encodeWithCoder:(NSCoder *)coder {
    [coder encodeObject:[self _data] forKey:@"NS.nameComponentsPrivate"];
}

- (id)copyWithZone:(NSZone *)zone {
    NSPersonNameComponents *copy = [[NSPersonNameComponents allocWithZone:zone] init];
    copy->_private = [_private copy];
    return copy;
}

- (NSString *)namePrefix { return [(_NSPersonNameComponentsData *)[self _data] namePrefix]; }
- (NSString *)givenName { return [(_NSPersonNameComponentsData *)[self _data] givenName]; }
- (NSString *)middleName { return [(_NSPersonNameComponentsData *)[self _data] middleName]; }
- (NSString *)familyName { return [(_NSPersonNameComponentsData *)[self _data] familyName]; }
- (NSString *)nameSuffix { return [(_NSPersonNameComponentsData *)[self _data] nameSuffix]; }
- (NSString *)nickname { return [(_NSPersonNameComponentsData *)[self _data] nickname]; }
- (NSPersonNameComponents *)phoneticRepresentation {
    return [(_NSPersonNameComponentsData *)[self _data] phoneticRepresentation];
}

- (void)setNamePrefix:(NSString *)namePrefix {
    [(_NSPersonNameComponentsData *)[self _data] setNamePrefix:namePrefix];
}
- (void)setGivenName:(NSString *)givenName {
    [(_NSPersonNameComponentsData *)[self _data] setGivenName:givenName];
}
- (void)setMiddleName:(NSString *)middleName {
    [(_NSPersonNameComponentsData *)[self _data] setMiddleName:middleName];
}
- (void)setFamilyName:(NSString *)familyName {
    [(_NSPersonNameComponentsData *)[self _data] setFamilyName:familyName];
}
- (void)setNameSuffix:(NSString *)nameSuffix {
    [(_NSPersonNameComponentsData *)[self _data] setNameSuffix:nameSuffix];
}
- (void)setNickname:(NSString *)nickname {
    [(_NSPersonNameComponentsData *)[self _data] setNickname:nickname];
}
- (void)setPhoneticRepresentation:(NSPersonNameComponents *)phoneticRepresentation {
    [(_NSPersonNameComponentsData *)[self _data] setPhoneticRepresentation:phoneticRepresentation];
}

- (BOOL)isEqual:(id)other {
    if (self == other) {
        return YES;
    }
    if (![other isKindOfClass:[NSPersonNameComponents class]]) {
        return NO;
    }
    NSPersonNameComponents *components = other;
    return [[self _data] isEqual:[components _data]];
}

- (NSUInteger)hash {
    return [[self _data] hash];
}

- (NSString *)description {
    _NSPersonNameComponentsData *data = [self _data];
    return [NSString stringWithFormat:@"<NSPersonNameComponents: %p> {givenName = %@, familyName = %@, "
            @"middleName = %@, namePrefix = %@, nameSuffix = %@, nickname = %@ "
            @"phoneticRepresentation = %@ }",
            self, data.givenName, data.familyName, data.middleName, data.namePrefix,
            data.nameSuffix, data.nickname, data.phoneticRepresentation];
}

+ (NSSet *)_allProperties {
    return [NSSet setWithObjects:@"namePrefix", @"givenName", @"middleName", @"familyName",
            @"nameSuffix", @"nickname", @"phoneticRepresentation", nil];
}

+ (NSSet *)_allComponents {
    return [NSSet setWithObjects:@"namePrefix", @"givenName", @"middleName", @"familyName",
            @"nameSuffix", @"nickname", nil];
}

@end
