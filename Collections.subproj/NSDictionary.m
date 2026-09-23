/*
 * Copyright (C) 2026, Samuel Zormeister.
 *
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */

#import <Foundation/NSDictionary.h>
#import <Foundation/NSURL.h>
#import <Foundation/NSError.h>
#import <Foundation/NSString.h>
#include <CoreFoundation/CFDictionary.h>
#include <CoreFoundation/CFPropertyList.h>
#include <CoreFoundation/CFURL.h>
#include <CoreFoundation/CFData.h>
#include <CoreFoundation/CFStream.h>
#include <CoreFoundation/ForFoundationOnly.h>
#include <objc/runtime.h>
#include <stdio.h>
#include <stdlib.h>

#if __has_feature(objc_arc)
#define NSDICT_ID(value) ((__bridge_transfer id)(value))
#define NSDICT_BORROWED(value) ((__bridge id)(value))
#define NSDICT_CF(type, value) ((__bridge type)(value))
#else
#define NSDICT_ID(value) ((id)(value))
#define NSDICT_BORROWED(value) ((id)(value))
#define NSDICT_CF(type, value) ((type)(value))
#endif

static CFDictionaryRef NSNSDictionaryCreate(const id *objects, const id *keys,
                                             NSUInteger count) {
    const void **objectValues = count == 0 ? NULL : malloc(count * sizeof(*objectValues));
    const void **keyValues = count == 0 ? NULL : malloc(count * sizeof(*keyValues));
    if ((count != 0 && objectValues == NULL) || (count != 0 && keyValues == NULL)) {
        free(objectValues);
        free(keyValues);
        return NULL;
    }
    for (NSUInteger index = 0; index < count; index++) {
        objectValues[index] = NSDICT_CF(const void *, objects[index]);
        keyValues[index] = NSDICT_CF(const void *, keys[index]);
    }
    CFDictionaryRef result = CFDictionaryCreate(kCFAllocatorDefault, keyValues, objectValues,
                                                (CFIndex)count,
                                                &kCFTypeDictionaryKeyCallBacks,
                                                &kCFTypeDictionaryValueCallBacks);
    free(objectValues);
    free(keyValues);
    return result;
}

/* Read a whole file into a CFData. CFReadStream would do, but plists are small
 * and stdio keeps this independent of the stream machinery. */
static CFDataRef pd_read_file(CFStringRef path) {
    char buf[1024];
    if (!CFStringGetCString(path, buf, sizeof(buf), kCFStringEncodingUTF8)) {
        return NULL;
    }

    FILE *f = fopen(buf, "rb");
    if (f == NULL) {
        return NULL;
    }
    if (fseek(f, 0, SEEK_END) != 0) {
        fclose(f);
        return NULL;
    }
    long size = ftell(f);
    if (size < 0) {
        fclose(f);
        return NULL;
    }
    rewind(f);

    UInt8 *bytes = malloc((size_t)size);
    if (bytes == NULL) {
        fclose(f);
        return NULL;
    }
    size_t got = fread(bytes, 1, (size_t)size, f);
    fclose(f);

    CFDataRef data = CFDataCreate(kCFAllocatorDefault, bytes, (CFIndex)got);
    free(bytes);
    return data;
}

static CFPropertyListRef pd_plist_from_path(CFStringRef path) {
    CFDataRef data = pd_read_file(path);
    if (data == NULL) {
        return NULL;
    }
    CFPropertyListRef plist = CFPropertyListCreateWithData(
        kCFAllocatorDefault, data, kCFPropertyListImmutable, NULL, NULL);
    CFRelease(data);

    if (plist != NULL && CFGetTypeID(plist) != CFDictionaryGetTypeID()) {
        CFRelease(plist);
        return NULL;
    }
    return plist;
}

@implementation NSDictionary

+ (instancetype)dictionary {
    return NSDICT_ID(CFDictionaryCreate(kCFAllocatorDefault, NULL, NULL, 0,
                                        &kCFTypeDictionaryKeyCallBacks,
                                        &kCFTypeDictionaryValueCallBacks));
}

/* CFDictionaryCreate takes keys first, the ObjC spelling takes objects first. */
+ (instancetype)dictionaryWithObjects:(const id *)objects
                              forKeys:(const id *)keys
                                count:(NSUInteger)count {
    return NSDICT_ID(NSNSDictionaryCreate(objects, keys, count));
}

- (instancetype)init {
    return NSDICT_ID(CFDictionaryCreate(kCFAllocatorDefault, NULL, NULL, 0,
                                        &kCFTypeDictionaryKeyCallBacks,
                                        &kCFTypeDictionaryValueCallBacks));
}

- (void)enumerateKeysAndObjectsUsingBlock:(void (^)(id, id, BOOL *))block {
    CFIndex n = CFDictionaryGetCount(NSDICT_CF(CFDictionaryRef, self));
    if (n <= 0 || block == NULL) {
        return;
    }
    const void **keys = malloc((size_t)n * sizeof(*keys));
    const void **values = malloc((size_t)n * sizeof(*values));
    if (keys == NULL || values == NULL) {
        free(keys);
        free(values);
        return;
    }
    /* Snapshot first: the block is allowed to mutate a mutable receiver. */
    CFDictionaryGetKeysAndValues(NSDICT_CF(CFDictionaryRef, self), keys, values);
    BOOL stop = NO;
    for (CFIndex i = 0; i < n && !stop; i++) {
        block(NSDICT_BORROWED(keys[i]), NSDICT_BORROWED(values[i]), &stop);
    }
    free(keys);
    free(values);
}

+ (nullable instancetype)dictionaryWithContentsOfURL:(NSURL *)url
                                               error:(NSError **)error {
    if (error != NULL) {
        *error = nil;
    }
    if (url == nil) {
        return nil;
    }

    CFStringRef path = CFURLCopyFileSystemPath(NSDICT_CF(CFURLRef, url), kCFURLPOSIXPathStyle);
    if (path == NULL) {
        return nil;
    }
    CFPropertyListRef plist = pd_plist_from_path(path);
    CFRelease(path);
    return NSDICT_ID(plist);
}

+ (nullable instancetype)dictionaryWithContentsOfFile:(NSString *)path {
    if (path == nil) {
        return nil;
    }
    return NSDICT_ID(pd_plist_from_path(NSDICT_CF(CFStringRef, path)));
}

- (NSUInteger)count {
    return (NSUInteger)CFDictionaryGetCount(NSDICT_CF(CFDictionaryRef, self));
}

- (nullable id)objectForKey:(id)key {
    return NSDICT_BORROWED(CFDictionaryGetValue(NSDICT_CF(CFDictionaryRef, self),
                                                NSDICT_CF(const void *, key)));
}

- (nullable id)objectForKeyedSubscript:(id)key {
    return [self objectForKey:key];
}

- (BOOL)isEqualToDictionary:(NSDictionary *)dictionary {
    return dictionary != nil && CFEqual(NSDICT_CF(CFTypeRef, self),
                                        NSDICT_CF(CFTypeRef, dictionary));
}

- (NSUInteger)hash {
    return (NSUInteger)CFHash(NSDICT_CF(CFTypeRef, self));
}

- (id)copyWithZone:(NSZone *)zone {
    (void)zone;
    return NSDICT_ID(CFDictionaryCreateCopy(kCFAllocatorDefault, NSDICT_CF(CFDictionaryRef, self)));
}

- (id)mutableCopyWithZone:(NSZone *)zone {
    (void)zone;
    return NSDICT_ID(CFDictionaryCreateMutableCopy(kCFAllocatorDefault, 0,
                                                    NSDICT_CF(CFDictionaryRef, self)));
}

- (NSArray *)allKeys {
    CFIndex n = CFDictionaryGetCount(NSDICT_CF(CFDictionaryRef, self));
    const void **keys = malloc(sizeof(void *) * (size_t)(n > 0 ? n : 1));
    if (keys == NULL) {
        return nil;
    }
    CFDictionaryGetKeysAndValues(NSDICT_CF(CFDictionaryRef, self), keys, NULL);
    CFArrayRef array = CFArrayCreate(kCFAllocatorDefault, keys, n,
                                     &kCFTypeArrayCallBacks);
    free(keys);
    return NSDICT_ID(array);
}

/* Fast enumeration walks the keys.  A dictionary instance is a bare
 * CFDictionary (bridged, not a laid-out ObjC object), so the once-per-loop
 * keys snapshot cannot live in an ivar; it is parked in an associated object,
 * which works on bridged instances and is released at the end of the loop.
 * Like NSArray, the cursor rides in state->state and mutationsPtr points at
 * state->extra[0], which is never written. */
static const void *NSDICT_FastEnumerationKeysKey = &NSDICT_FastEnumerationKeysKey;

- (NSUInteger)countByEnumeratingWithState:(NSFastEnumerationState *)state
                                 objects:(id __unsafe_unretained _Nullable[_Nonnull])stackbuf
                                   count:(NSUInteger)len {
    NSUInteger index = state->state;
    NSArray *keys;
    if (index == 0) {
        keys = [self allKeys];
        if (keys == nil) {
            return 0;
        }
        objc_setAssociatedObject(self, NSDICT_FastEnumerationKeysKey, keys,
                                 OBJC_ASSOCIATION_RETAIN);
    } else {
        keys = objc_getAssociatedObject(self, NSDICT_FastEnumerationKeysKey);
        if (keys == nil) {
            return 0;
        }
    }
    NSUInteger total = keys.count;
    if (index >= total) {
        objc_setAssociatedObject(self, NSDICT_FastEnumerationKeysKey, nil,
                                 OBJC_ASSOCIATION_RETAIN);
        return 0;
    }
    state->mutationsPtr = &state->extra[0];
    state->itemsPtr = stackbuf;
    NSUInteger filled = 0;
    while (index < total && filled < len) {
        stackbuf[filled++] = [keys objectAtIndex:index];
        index++;
    }
    state->state = index;
    return filled;
}

@end

@implementation NSMutableDictionary

+ (instancetype)dictionaryWithCapacity:(NSUInteger)capacity {
    return NSDICT_ID(CFDictionaryCreateMutable(kCFAllocatorDefault, (CFIndex)capacity,
                                               &kCFTypeDictionaryKeyCallBacks,
                                               &kCFTypeDictionaryValueCallBacks));
}

+ (instancetype)dictionary {
    return [self dictionaryWithCapacity:0];
}

- (instancetype)init {
    return NSDICT_ID(CFDictionaryCreateMutable(kCFAllocatorDefault, 0,
                                               &kCFTypeDictionaryKeyCallBacks,
                                               &kCFTypeDictionaryValueCallBacks));
}

- (void)setObject:(id)object forKey:(id)key {
    CFDictionarySetValue(NSDICT_CF(CFMutableDictionaryRef, self),
                         NSDICT_CF(const void *, key), NSDICT_CF(const void *, object));
}

- (void)setObject:(id)object forKeyedSubscript:(id)key {
    [self setObject:object forKey:key];
}

- (void)removeObjectForKey:(id)key {
    CFDictionaryRemoveValue(NSDICT_CF(CFMutableDictionaryRef, self),
                            NSDICT_CF(const void *, key));
}

@end

#if DEPLOYMENT_RUNTIME_OBJC
__attribute__((constructor))
static void __NSCFDictionaryBridgeInit(void) {
    _CFRuntimeBridgeClasses(CFDictionaryGetTypeID(), "NSDictionary");
}
#endif
