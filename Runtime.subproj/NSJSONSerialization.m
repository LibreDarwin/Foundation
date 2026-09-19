/*
 * Copyright (C) 2026, PureDarwin Project.
 *
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */

#import <Foundation/NSJSONSerialization.h>
#import <Foundation/NSArray.h>
#import <Foundation/NSDictionary.h>
#import <Foundation/NSNumber.h>
#import <Foundation/NSNull.h>
#import <Foundation/NSError.h>
#import <Foundation/NSString.h>
#include <stdlib.h>
#include <string.h>
#include <errno.h>
#include <ctype.h>

static void JSONSetError(NSError **error) {
    if (error != NULL) {
        *error = [NSError errorWithDomain:@"NSJSONSerializationErrorDomain" code:1];
    }
}

typedef struct {
    const unsigned char *bytes;
    NSUInteger length;
    NSUInteger index;
    BOOL failed;
    NSJSONReadingOptions options;
} JSONParser;

static void JSONSkipSpace(JSONParser *parser) {
    while (parser->index < parser->length &&
           isspace(parser->bytes[parser->index])) {
        parser->index++;
    }
}

static BOOL JSONConsume(JSONParser *parser, unsigned char character) {
    JSONSkipSpace(parser);
    if (parser->index < parser->length && parser->bytes[parser->index] == character) {
        parser->index++;
        return YES;
    }
    parser->failed = YES;
    return NO;
}

static int JSONHex(unsigned char character) {
    if (character >= '0' && character <= '9') return character - '0';
    if (character >= 'a' && character <= 'f') return character - 'a' + 10;
    if (character >= 'A' && character <= 'F') return character - 'A' + 10;
    return -1;
}

static NSString *JSONParseString(JSONParser *parser) {
    if (!JSONConsume(parser, '"')) return nil;
    NSUInteger capacity = parser->length - parser->index + 1;
    unichar *characters = calloc(capacity, sizeof(unichar));
    if (characters == NULL) { parser->failed = YES; return nil; }
    NSUInteger count = 0;
    while (parser->index < parser->length) {
        unsigned char character = parser->bytes[parser->index++];
        if (character == '"') {
            NSString *result = [NSString stringWithCharacters:characters length:count];
            free(characters);
            return result;
        }
        if (character < 0x20) { parser->failed = YES; break; }
        if (character == '\\') {
            if (parser->index >= parser->length) { parser->failed = YES; break; }
            unsigned char escaped = parser->bytes[parser->index++];
            switch (escaped) {
                case '"': character = '"'; break;
                case '\\': character = '\\'; break;
                case '/': character = '/'; break;
                case 'b': character = '\b'; break;
                case 'f': character = '\f'; break;
                case 'n': character = '\n'; break;
                case 'r': character = '\r'; break;
                case 't': character = '\t'; break;
                case 'u': {
                    int value = 0;
                    for (int i = 0; i < 4; i++) {
                        if (parser->index >= parser->length ||
                            JSONHex(parser->bytes[parser->index]) < 0) {
                            parser->failed = YES;
                            break;
                        }
                        value = (value << 4) | JSONHex(parser->bytes[parser->index++]);
                    }
                    if (parser->failed) break;
                    if (count == capacity) { parser->failed = YES; break; }
                    characters[count++] = (unichar)value;
                    continue;
                }
                default: parser->failed = YES; break;
            }
            if (parser->failed) break;
        } else if (character >= 0x80) {
            /* Preserve UTF-8 bytes by decoding the complete source substring. */
            NSUInteger start = parser->index - 1;
            while (parser->index < parser->length &&
                   (parser->bytes[parser->index] & 0xc0) == 0x80) parser->index++;
            NSString *part = [[NSString alloc] initWithBytes:parser->bytes + start
                                                       length:parser->index - start
                                                     encoding:NSUTF8StringEncoding];
            if (part == nil || count + [part length] >= capacity) { parser->failed = YES; break; }
            [part getCharacters:characters + count range:NSMakeRange(0, [part length])];
            count += [part length];
            continue;
        }
        if (count == capacity) { parser->failed = YES; break; }
        characters[count++] = character;
    }
    free(characters);
    parser->failed = YES;
    return nil;
}

static id JSONParseValue(JSONParser *parser);

static id JSONParseArray(JSONParser *parser) {
    if (!JSONConsume(parser, '[')) return nil;
    NSMutableArray *array = [NSMutableArray array];
    JSONSkipSpace(parser);
    if (parser->index < parser->length && parser->bytes[parser->index] == ']') {
        parser->index++;
        return array;
    }
    while (!parser->failed) {
        id value = JSONParseValue(parser);
        if (value == nil) { parser->failed = YES; break; }
        [array addObject:value];
        JSONSkipSpace(parser);
        if (parser->index < parser->length && parser->bytes[parser->index] == ']') {
            parser->index++;
            return array;
        }
        if (!JSONConsume(parser, ',')) break;
    }
    return nil;
}

static id JSONParseObject(JSONParser *parser) {
    if (!JSONConsume(parser, '{')) return nil;
    NSMutableDictionary *dictionary = [NSMutableDictionary dictionary];
    JSONSkipSpace(parser);
    if (parser->index < parser->length && parser->bytes[parser->index] == '}') {
        parser->index++;
        return dictionary;
    }
    while (!parser->failed) {
        NSString *key = JSONParseString(parser);
        if (key == nil || !JSONConsume(parser, ':')) break;
        id value = JSONParseValue(parser);
        if (value == nil) break;
        [dictionary setObject:value forKey:key];
        JSONSkipSpace(parser);
        if (parser->index < parser->length && parser->bytes[parser->index] == '}') {
            parser->index++;
            return dictionary;
        }
        if (!JSONConsume(parser, ',')) break;
    }
    return nil;
}

static id JSONParseNumber(JSONParser *parser) {
    NSUInteger start = parser->index;
    while (parser->index < parser->length &&
           strchr("+-0123456789.eE", parser->bytes[parser->index]) != NULL) parser->index++;
    NSString *token = [[NSString alloc] initWithBytes:parser->bytes + start
                                                length:parser->index - start
                                              encoding:NSUTF8StringEncoding];
    if (token == nil || [token length] == 0) { parser->failed = YES; return nil; }
    const char *text = [token UTF8String];
    char *end = NULL;
    errno = 0;
    double number = strtod(text, &end);
    if (errno == ERANGE || end == text || *end != '\0') { parser->failed = YES; return nil; }
    if (strchr(text, '.') != NULL || strchr(text, 'e') != NULL || strchr(text, 'E') != NULL)
        return [NSNumber numberWithDouble:number];
    return [NSNumber numberWithLongLong:strtoll(text, NULL, 10)];
}

static id JSONParseValue(JSONParser *parser) {
    JSONSkipSpace(parser);
    if (parser->index >= parser->length) { parser->failed = YES; return nil; }
    unsigned char first = parser->bytes[parser->index];
    if (first == '"') return JSONParseString(parser);
    if (first == '[') return JSONParseArray(parser);
    if (first == '{') return JSONParseObject(parser);
    if (first == 't' && parser->index + 4 <= parser->length &&
        memcmp(parser->bytes + parser->index, "true", 4) == 0) {
        parser->index += 4; return [NSNumber numberWithBool:YES];
    }
    if (first == 'f' && parser->index + 5 <= parser->length &&
        memcmp(parser->bytes + parser->index, "false", 5) == 0) {
        parser->index += 5; return [NSNumber numberWithBool:NO];
    }
    if (first == 'n' && parser->index + 4 <= parser->length &&
        memcmp(parser->bytes + parser->index, "null", 4) == 0) {
        parser->index += 4; return [NSNull null];
    }
    return JSONParseNumber(parser);
}

static void JSONAppendString(NSMutableData *data, NSString *string) {
    [data appendBytes:"\"" length:1];
    const unichar *characters = NULL;
    NSUInteger length = [string length];
    unichar *buffer = malloc(sizeof(unichar) * length);
    if (buffer != NULL) {
        [string getCharacters:buffer range:NSMakeRange(0, length)];
        characters = buffer;
    }
    for (NSUInteger i = 0; i < length; i++) {
        unichar c = characters[i];
        const char *escaped = NULL;
        switch (c) {
            case '"': escaped = "\\\""; break;
            case '\\': escaped = "\\\\"; break;
            case '\b': escaped = "\\b"; break;
            case '\f': escaped = "\\f"; break;
            case '\n': escaped = "\\n"; break;
            case '\r': escaped = "\\r"; break;
            case '\t': escaped = "\\t"; break;
            default: break;
        }
        if (escaped != NULL) [data appendBytes:escaped length:strlen(escaped)];
        else if (c < 0x20) {
            NSString *hex = [NSString stringWithFormat:@"\\u%04x", c];
            [data appendData:[hex dataUsingEncoding:NSUTF8StringEncoding]];
        } else {
            NSString *one = [NSString stringWithCharacters:&c length:1];
            [data appendData:[one dataUsingEncoding:NSUTF8StringEncoding]];
        }
    }
    free(buffer);
    [data appendBytes:"\"" length:1];
}

static void JSONAppendIndent(NSMutableData *data, NSUInteger depth) {
    for (NSUInteger i = 0; i < depth; i++) [data appendBytes:"  " length:2];
}

static int JSONCompareKeys(const void *left, const void *right) {
    NSString *a = *(NSString * const *)left;
    NSString *b = *(NSString * const *)right;
    return strcmp([a UTF8String], [b UTF8String]);
}

static BOOL JSONWriteValue(id object, NSMutableData *data, NSJSONWritingOptions options,
                           NSUInteger depth) {
    BOOL pretty = (options & NSJSONWritingPrettyPrinted) != 0;
    if ([object isKindOfClass:[NSString class]]) { JSONAppendString(data, object); return YES; }
    if ([object isKindOfClass:[NSNumber class]]) {
        const char *type = [object objCType];
        if (strcmp(type, @encode(BOOL)) == 0 || strcmp(type, "c") == 0 || strcmp(type, "B") == 0) {
            const char *literal = [object boolValue] ? "true" : "false";
            [data appendBytes:literal length:strlen(literal)];
            return YES;
        }
        NSString *text = [object descriptionWithLocale:nil];
        [data appendData:[text dataUsingEncoding:NSUTF8StringEncoding]];
        return YES;
    }
    if (object == [NSNull null]) { [data appendBytes:"null" length:4]; return YES; }
    if ([object isKindOfClass:[NSArray class]]) {
        NSArray *array = object;
        [data appendBytes:"[" length:1];
        for (NSUInteger i = 0; i < [array count]; i++) {
            if (i != 0) [data appendBytes:"," length:1];
            if (pretty) { [data appendBytes:"\n" length:1]; JSONAppendIndent(data, depth + 1); }
            if (!JSONWriteValue([array objectAtIndex:i], data, options, depth + 1)) return NO;
        }
        if (pretty && [array count] != 0) {
            [data appendBytes:"\n" length:1];
            JSONAppendIndent(data, depth);
        }
        [data appendBytes:"]" length:1];
        return YES;
    }
    if ([object isKindOfClass:[NSDictionary class]]) {
        NSDictionary *dictionary = object;
        NSArray *keys = [dictionary allKeys];
        if (options & NSJSONWritingSortedKeys) {
            NSUInteger count = [keys count];
            NSString *__unsafe_unretained *sorted = (NSString *__unsafe_unretained *)calloc(count, sizeof(*sorted));
            if (sorted == NULL && count != 0) return NO;
            for (NSUInteger i = 0; i < count; i++) sorted[i] = [keys objectAtIndex:i];
            qsort(sorted, count, sizeof(*sorted), JSONCompareKeys);
            keys = [NSArray arrayWithObjects:sorted count:count];
            free(sorted);
        }
        [data appendBytes:"{" length:1];
        for (NSUInteger i = 0; i < [keys count]; i++) {
            if (i != 0) [data appendBytes:"," length:1];
            if (pretty) { [data appendBytes:"\n" length:1]; JSONAppendIndent(data, depth + 1); }
            id key = [keys objectAtIndex:i];
            if (![key isKindOfClass:[NSString class]]) return NO;
            JSONAppendString(data, key);
            [data appendBytes:":" length:1];
            if (!JSONWriteValue([dictionary objectForKey:key], data, options, depth + 1)) return NO;
        }
        if (pretty && [keys count] != 0) {
            [data appendBytes:"\n" length:1];
            JSONAppendIndent(data, depth);
        }
        [data appendBytes:"}" length:1];
        return YES;
    }
    return NO;
}

BOOL NSJSONSerializationIsValidJSONObject(id object) {
    if (object == [NSNull null] || [object isKindOfClass:[NSString class]] ||
        [object isKindOfClass:[NSNumber class]]) return YES;
    if ([object isKindOfClass:[NSArray class]]) {
        for (NSUInteger i = 0; i < [object count]; i++)
            if (!NSJSONSerializationIsValidJSONObject([object objectAtIndex:i])) return NO;
        return YES;
    }
    if ([object isKindOfClass:[NSDictionary class]]) {
        __block BOOL valid = YES;
        [object enumerateKeysAndObjectsUsingBlock:^(id key, id value, BOOL *stop) {
            if (![key isKindOfClass:[NSString class]] || !NSJSONSerializationIsValidJSONObject(value)) {
                valid = NO; *stop = YES;
            }
        }];
        return valid;
    }
    return NO;
}

@implementation NSJSONSerialization

+ (id)JSONObjectWithData:(NSData *)data options:(NSJSONReadingOptions)options error:(NSError **)error {
    if (data == nil) { JSONSetError(error); return nil; }
    JSONParser parser = { [data bytes], [data length], 0, NO, options };
    id object = JSONParseValue(&parser);
    JSONSkipSpace(&parser);
    if (parser.failed || object == nil || parser.index != parser.length ||
        (!(options & NSJSONReadingAllowFragments) &&
         ![object isKindOfClass:[NSArray class]] && ![object isKindOfClass:[NSDictionary class]])) {
        JSONSetError(error);
        return nil;
    }
    return object;
}

+ (id)JSONObjectWithStream:(NSInputStream *)stream options:(NSJSONReadingOptions)options error:(NSError **)error {
    if (stream == nil) { JSONSetError(error); return nil; }
    NSMutableData *data = [NSMutableData data];
    uint8_t buffer[4096];
    [stream open];
    while ([stream hasBytesAvailable]) {
        NSInteger count = [stream read:buffer maxLength:sizeof(buffer)];
        if (count < 0) { [stream close]; JSONSetError(error); return nil; }
        if (count == 0) break;
        [data appendBytes:buffer length:(NSUInteger)count];
    }
    [stream close];
    return [self JSONObjectWithData:data options:options error:error];
}

+ (NSData *)dataWithJSONObject:(id)object options:(NSJSONWritingOptions)options error:(NSError **)error {
    if (!NSJSONSerializationIsValidJSONObject(object)) { JSONSetError(error); return nil; }
    NSMutableData *data = [NSMutableData data];
    if (!JSONWriteValue(object, data, options, 0)) { JSONSetError(error); return nil; }
    return data;
}

+ (BOOL)writeJSONObject:(id)object toStream:(NSOutputStream *)stream
                options:(NSJSONWritingOptions)options error:(NSError **)error {
    if (stream == nil) { JSONSetError(error); return NO; }
    NSData *data = [self dataWithJSONObject:object options:options error:error];
    if (data == nil) return NO;
    [stream open];
    const uint8_t *bytes = [data bytes];
    NSUInteger remaining = [data length];
    while (remaining != 0) {
        NSInteger count = [stream write:bytes maxLength:remaining];
        if (count <= 0) { [stream close]; JSONSetError(error); return NO; }
        bytes += count;
        remaining -= (NSUInteger)count;
    }
    [stream close];
    return YES;
}

@end
