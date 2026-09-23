/*
 * Copyright (C) 2026, Samuel Zormeister.
 *
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 *
 * NSTimeZone is implemented directly against the system zoneinfo
 * database (/usr/share/zoneinfo, TZif format), since the port's local
 * CoreFoundation exposes no CFTZ surface.
 */

#import <Foundation/NSTimeZone.h>
#import <Foundation/NSString.h>
#import <Foundation/NSArray.h>
#import <Foundation/NSData.h>
#import <Foundation/NSDictionary.h>
#import <Foundation/NSException.h>
#import <Foundation/NSLocale.h>
#import <objc/runtime.h>
#import <dispatch/dispatch.h>

#include <assert.h>
#include <dirent.h>
#include <errno.h>
#include <limits.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>
#include <sys/stat.h>
#include <sys/types.h>

static int32_t NTZBE32(const void *p) {
    const uint8_t *b = (const uint8_t *)p;
    return (int32_t)(((uint32_t)b[0] << 24) | ((uint32_t)b[1] << 16) |
                     ((uint32_t)b[2] << 8) | (uint32_t)b[3]);
}

static NSInteger NTZGmtoffOfType(const uint8_t *ttinfo, int i) {
    return (NSInteger)NTZBE32(ttinfo + (size_t)i * 6);
}

static uint8_t NTZTypeIsdst(const uint8_t *ttinfo, int i) {
    return ttinfo[(size_t)i * 6 + 4];
}

static uint8_t NTZTypeDesig(const uint8_t *ttinfo, int i) {
    return ttinfo[(size_t)i * 6 + 5];
}

typedef struct {
    BOOL valid;
    int64_t tEnd;
    int timecnt;
    int typecnt;
    int charcnt;
    const int32_t *times;
    const uint8_t *typeidx;
    const uint8_t *ttinfo;
    const char *abbrs;
} NTZData;

static BOOL NTZParse(NSData *data, NTZData *out) {
    out->valid = NO;
    if (data == nil || [data length] < 44) return NO;
    const unsigned char *b = (const unsigned char *)[data bytes];
    NSUInteger len = [data length];
    if (b[0] != 'T' || b[1] != 'Z' || b[2] != 'i' || b[3] != 'f') return NO;
    int32_t isut = NTZBE32(b + 20);
    int32_t isstd = NTZBE32(b + 24);
    int32_t leap = NTZBE32(b + 28);
    int32_t timecnt = NTZBE32(b + 32);
    int32_t typecnt = NTZBE32(b + 36);
    int32_t charcnt = NTZBE32(b + 40);
    if (timecnt < 0 || typecnt < 0 || charcnt < 0 ||
        isut < 0 || isstd < 0 || leap < 0) return NO;

    size_t off = 44;
    size_t need = (size_t)timecnt * 4 + (size_t)timecnt + (size_t)typecnt * 6 +
                  (size_t)charcnt + (size_t)leap * 8 + (size_t)isstd + (size_t)isut;
    if (off + need > len) return NO;

    out->timecnt = timecnt;
    out->typecnt = typecnt;
    out->charcnt = charcnt;
    out->times = (const int32_t *)(b + off);
    off += (size_t)timecnt * 4;
    out->typeidx = b + off;
    off += (size_t)timecnt;
    out->ttinfo = b + off;
    off += (size_t)typecnt * 6;
    out->abbrs = (const char *)(b + off);
    out->tEnd = (int64_t)len;
    out->valid = YES;
    return YES;
}

static int64_t NTZTimeAt(const int32_t *times, int i) {
    return (int64_t)NTZBE32((const void *)(times + i));
}

/* Index of the transition type in effect at absolute time t, or 0 if before
 * the first transition. */
static int NTZActiveType(NTZData *d, double t) {
    int64_t tt = (int64_t)t;
    int lo = 0, hi = d->timecnt - 1, ans = -1;
    while (lo <= hi) {
        int mid = (lo + hi) / 2;
        if (NTZTimeAt(d->times, mid) <= tt) {
            ans = mid;
            lo = mid + 1;
        } else {
            hi = mid - 1;
        }
    }
    if (ans < 0) return 0;
    return d->typeidx[ans];
}

static NSInteger NTZGmtoffAt(NTZData *d, double t) {
    int ty = NTZActiveType(d, t);
    return NTZGmtoffOfType(d->ttinfo, ty);
}

static NSString *NTZAbbrAt(NTZData *d, double t) {
    int ty = NTZActiveType(d, t);
    if (ty < 0 || ty >= d->typecnt) return @"";
    size_t idx = NTZTypeDesig(d->ttinfo, ty);
    if (idx >= (size_t)d->charcnt) return @"";
    return [NSString stringWithUTF8String:d->abbrs + idx];
}

static BOOL NTZIsDSTAt(NTZData *d, double t) {
    int ty = NTZActiveType(d, t);
    return NTZTypeIsdst(d->ttinfo, ty) != 0;
}

static NSTimeInterval NTZDSTOffsetAt(NTZData *d, double t) {
    int active = NTZActiveType(d, t);
    if (!NTZTypeIsdst(d->ttinfo, active)) return 0.0;
    NSInteger dstOff = NTZGmtoffOfType(d->ttinfo, active);
    int std = -1;
    for (int i = d->timecnt - 1; i >= 0; i--) {
        int ty = d->typeidx[i];
        if (!NTZTypeIsdst(d->ttinfo, ty)) {
            std = ty;
            break;
        }
    }
    if (std < 0) std = 0;
    return (NSTimeInterval)(dstOff - NTZGmtoffOfType(d->ttinfo, std));
}

static NSDate *NTZNextDSTTransition(NTZData *d, double t) {
    int active = NTZActiveType(d, t);
    BOOL activeDST = NTZTypeIsdst(d->ttinfo, active) != 0;
    for (int i = 0; i < d->timecnt; i++) {
        if (NTZTimeAt(d->times, i) <= t) continue;
        int ty = d->typeidx[i];
        if ((NTZTypeIsdst(d->ttinfo, ty) != 0) != activeDST) {
            return [NSDate dateWithTimeIntervalSince1970:(double)NTZTimeAt(d->times, i)];
        }
    }
    return nil;
}

static NSData *NTZReadFile(NSString *path) {
    if (path == nil) return nil;
    FILE *f = fopen([path UTF8String], "rb");
    if (f == NULL) return nil;
    if (fseek(f, 0, SEEK_END) != 0) { fclose(f); return nil; }
    long n = ftell(f);
    if (fseek(f, 0, SEEK_SET) != 0) { fclose(f); return nil; }
    if (n < 0) { fclose(f); return nil; }
    if (n == 0) { fclose(f); return nil; }
    char *buf = (char *)malloc((size_t)n);
    if (buf == NULL) { fclose(f); return nil; }
    if (fread(buf, 1, (size_t)n, f) != (size_t)n) {
        free(buf);
        fclose(f);
        return nil;
    }
    fclose(f);
    NSData *d = [NSData dataWithBytes:buf length:(NSUInteger)n];
    free(buf);
    return d;
}

static BOOL NTZGMTNameOffset(NSString *name, NSInteger *outSecs) {
    const char *c = [name UTF8String];
    if (c == NULL) return NO;
    if (strcmp(c, "GMT") == 0 || strcmp(c, "UTC") == 0) {
        *outSecs = 0;
        return YES;
    }
    if (strncmp(c, "GMT", 3) != 0) return NO;
    const char *p = c + 3;
    int sign = 1;
    if (*p == '-') {
        sign = -1;
        p++;
    } else if (*p == '+') {
        p++;
    } else {
        return NO;
    }
    if (p[0] < '0' || p[0] > '9' || p[1] < '0' || p[1] > '9') return NO;
    int hh = (p[0] - '0') * 10 + (p[1] - '0');
    p += 2;
    int mm = 0;
    if (*p == ':') p++;
    if (*p != 0) {
        if (p[0] < '0' || p[0] > '9' || p[1] < '0' || p[1] > '9') return NO;
        mm = (p[0] - '0') * 10 + (p[1] - '0');
    }
    *outSecs = (NSInteger)sign * (hh * 3600 + mm * 60);
    return YES;
}

static NSString *NTZZoneinfoPathForName(NSString *name) {
    if ([name isEqualToString:@"UTC"]) name = @"Etc/UTC";
    if ([name isEqualToString:@"GMT"]) name = @"Etc/GMT";
    return [@"/usr/share/zoneinfo/" stringByAppendingString:name];
}

static NSTimeZone *gSystemTimeZone = nil;

static void NSSystemTimeZoneReset(void) {
    gSystemTimeZone = nil;
}

typedef struct {
    char **items;
    size_t count;
    size_t cap;
} NTZNameList;

static void NTZListAdd(NTZNameList *list, const char *s) {
    if (list->count == list->cap) {
        size_t nc = list->cap ? list->cap * 2 : 64;
        char **ni = (char **)realloc(list->items, nc * sizeof(char *));
        if (ni == NULL) return;
        list->items = ni;
        list->cap = nc;
    }
    list->items[list->count] = strdup(s);
    if (list->items[list->count] != NULL) list->count++;
}

static int NTZNameCmp(const void *a, const void *b) {
    return strcmp(*(const char *const *)a, *(const char *const *)b);
}

static void NTZCollectNames(const char *base, const char *rel, NTZNameList *list) {
    char full[PATH_MAX] = "/usr/share/zoneinfo/";
    if (rel[0] != 0) {
        snprintf(full, sizeof(full), "%s/%s", base, rel);
    }
    DIR *d = opendir(full);
    if (d == NULL) return;
    struct dirent *e;
    while ((e = readdir(d)) != NULL) {
        const char *en = e->d_name;
        if (en[0] == '.') continue;
        if (strcmp(en, "posix") == 0 || strcmp(en, "right") == 0 ||
            strcmp(en, "SystemV") == 0 || strcmp(en, "posixrules") == 0 ||
            strcmp(en, "localtime") == 0 || strcmp(en, "Factory") == 0) continue;
        char child[PATH_MAX];
        char childrel[PATH_MAX];
        snprintf(child, sizeof(child), "%s/%s", full, en);
        snprintf(childrel, sizeof(childrel), "%s%s%s", rel, rel[0] ? "/" : "", en);
        struct stat st;
        if (lstat(child, &st) == 0 && S_ISDIR(st.st_mode)) {
            NTZCollectNames(base, childrel, list);
            continue;
        }
        FILE *f = fopen(child, "rb");
        if (f == NULL) continue;
        char magic[4];
        size_t r = fread(magic, 1, 4, f);
        fclose(f);
        if (r == 4 && memcmp(magic, "TZif", 4) == 0) {
            NTZListAdd(list, childrel);
        }
    }
    closedir(d);
}

@implementation NSTimeZone {
    NSData *_parsed;
}

+ (NSTimeZone *)systemTimeZone {
    if (gSystemTimeZone == nil) {
        NSTimeZone *tz = nil;
        char link[PATH_MAX];
        ssize_t n = readlink("/etc/localtime", link, sizeof(link) - 1);
        NSString *name = nil;
        if (n > 0) {
            link[n] = 0;
            NSString *raw = [NSString stringWithUTF8String:link];
            NSArray *prefixes = [NSArray arrayWithObjects:(id[]){
                @"/var/db/timezone/zoneinfo/", @"/usr/share/zoneinfo/"
            } count:2];
            for (NSUInteger i = 0; i < [prefixes count]; i++) {
                NSString *pre = [prefixes objectAtIndex:i];
                if ([raw hasPrefix:pre]) {
                    name = [raw substringFromIndex:[pre length]];
                    break;
                }
            }
        }
        if (name != nil && [name length] > 0) {
            tz = [self timeZoneWithName:name];
        }
        if (tz == nil) {
            tzset();
            time_t now = time(NULL);
            struct tm tmv;
            localtime_r(&now, &tmv);
            tz = [self timeZoneForSecondsFromGMT:(NSInteger)tmv.tm_gmtoff];
        }
        gSystemTimeZone = tz;
    }
    return gSystemTimeZone;
}

+ (NSTimeZone *)defaultTimeZone {
    NSTimeZone *tz = (NSTimeZone *)objc_getAssociatedObject(self, "NTZDefault");
    if (tz == nil) return [self systemTimeZone];
    return tz;
}

+ (void)setDefaultTimeZone:(NSTimeZone *)tz {
    objc_setAssociatedObject(self, "NTZDefault", [tz copy], OBJC_ASSOCIATION_RETAIN);
}

+ (NSTimeZone *)localTimeZone {
    return [self defaultTimeZone];
}

+ (void)resetSystemTimeZone {
    NSSystemTimeZoneReset();
}

+ (NSTimeZone *)timeZoneWithName:(NSString *)tzName {
    if (tzName == nil) return nil;
    NSInteger secs;
    if (NTZGMTNameOffset(tzName, &secs)) {
        return [self timeZoneForSecondsFromGMT:secs];
    }
    NSData *data = NTZReadFile(NTZZoneinfoPathForName(tzName));
    if (data == nil) return nil;
    return [self timeZoneWithName:tzName data:data];
}

+ (NSTimeZone *)timeZoneWithName:(NSString *)tzName data:(NSData *)aData {
    return [[self alloc] initWithName:tzName data:aData];
}

+ (NSTimeZone *)timeZoneForSecondsFromGMT:(NSInteger)seconds {
    NSString *name;
    if (seconds == 0) {
        name = @"GMT";
    } else {
        NSInteger h = seconds / 3600;
        NSInteger m = (seconds % 3600) / 60;
        BOOL negative = seconds < 0;
        if (negative) {
            h = -h;
            m = -m;
        }
        name = [NSString stringWithFormat:@"GMT%@%02ld%02ld", negative ? @"-" : @"+",
                (long)h, (long)m];
    }
    return [[self alloc] initWithName:name data:nil];
}

static NSDictionary *NTZAbbreviationTable(void) {
    static NSDictionary *table = nil;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        table = @{
            @"ACDT": @"Australia/Adelaide", @"ACST": @"Australia/Adelaide",
            @"ADT": @"America/Halifax", @"AEDT": @"Australia/Sydney",
            @"AEST": @"Australia/Sydney", @"AKDT": @"America/Anchorage",
            @"AKST": @"America/Anchorage", @"AST": @"America/Halifax",
            @"AWST": @"Australia/Perth", @"BST": @"Europe/London",
            @"CAT": @"Africa/Harare", @"CDT": @"America/Chicago",
            @"CEST": @"Europe/Paris", @"CET": @"Europe/Paris",
            @"CST": @"America/Chicago", @"EAT": @"Africa/Addis_Ababa",
            @"EDT": @"America/New_York", @"EEST": @"Europe/Paris",
            @"EET": @"Europe/Paris", @"EST": @"America/New_York",
            @"GMT": @"GMT", @"HST": @"Pacific/Honolulu",
            @"IST": @"Asia/Kolkata", @"JST": @"Asia/Tokyo",
            @"KST": @"Asia/Seoul", @"MDT": @"America/Denver",
            @"MST": @"America/Denver", @"NZDT": @"Pacific/Auckland",
            @"NZST": @"Pacific/Auckland", @"PST": @"America/Los_Angeles",
            @"SAST": @"Africa/Johannesburg", @"SGT": @"Asia/Singapore",
            @"UTC": @"UTC", @"WEST": @"Europe/Paris", @"WET": @"Europe/Paris",
        };
    });
    return table;
}

+ (NSTimeZone *)timeZoneWithAbbreviation:(NSString *)abbreviation {
    if (abbreviation == nil) return nil;
    NSString *name = [NTZAbbreviationTable() objectForKey:abbreviation];
    if (name == nil) return nil;
    return [self timeZoneWithName:name];
}

+ (NSArray *)knownTimeZoneNames {
    NTZNameList list;
    memset(&list, 0, sizeof(list));
    NTZCollectNames("/usr/share/zoneinfo/", "", &list);
    NSArray *result;
    if (list.count == 0) {
        result = [NSArray array];
    } else {
        if (list.count > 1) {
            qsort(list.items, list.count, sizeof(char *), NTZNameCmp);
        }
        id __unsafe_unretained *objs = (id __unsafe_unretained *)malloc(list.count * sizeof(id));
        for (size_t i = 0; i < list.count; i++) {
            objs[i] = [NSString stringWithUTF8String:list.items[i]];
        }
        result = [NSArray arrayWithObjects:(const id _Nonnull *)(void *)objs count:list.count];
        free(objs);
    }
    for (size_t i = 0; i < list.count; i++) free(list.items[i]);
    free(list.items);
    return result;
}

+ (NSDictionary *)abbreviationDictionary {
    return NTZAbbreviationTable();
}

- (instancetype)initWithName:(NSString *)tzName data:(NSData *)aData {
    self = [super init];
    if (self != nil) {
        _name = [tzName copy];
        _secondsFromGMT = 0;
        if (aData != nil) {
            _parsed = [aData copy];
        } else {
            NSInteger secs;
            if (NTZGMTNameOffset(tzName, &secs)) {
                _secondsFromGMT = secs;
            } else {
                _parsed = NTZReadFile(NTZZoneinfoPathForName(tzName));
            }
        }
    }
    return self;
}

- (NSString *)name { return _name; }

- (NSData *)data { return _parsed; }

- (NSInteger)secondsFromGMT {
    if (_parsed == nil) return _secondsFromGMT;
    return [self secondsFromGMTForDate:[NSDate date]];
}

- (NSInteger)secondsFromGMTForDate:(NSDate *)aDate {
    if (_parsed == nil) return _secondsFromGMT;
    NTZData d;
    if (!NTZParse(_parsed, &d)) return _secondsFromGMT;
    return NTZGmtoffAt(&d, [aDate timeIntervalSince1970]);
}

- (NSString *)abbreviation {
    return [self abbreviationForDate:[NSDate date]];
}

- (NSString *)abbreviationForDate:(NSDate *)aDate {
    if (_parsed == nil) {
        if (_secondsFromGMT == 0) return @"GMT";
        return [self name];
    }
    NTZData d;
    if (!NTZParse(_parsed, &d)) return @"";
    double t = [aDate timeIntervalSince1970];
    NSString *abbr = NTZAbbrAt(&d, t);
    if ([abbr isEqualToString:@"CET"] || [abbr isEqualToString:@"CEST"] ||
        [abbr isEqualToString:@"EET"] || [abbr isEqualToString:@"EEST"] ||
        [abbr isEqualToString:@"WET"] || [abbr isEqualToString:@"WEST"]) {
        NSInteger h = NTZGmtoffAt(&d, t) / 3600;
        if (h < 0) return [NSString stringWithFormat:@"GMT%ld", (long)h];
        return [NSString stringWithFormat:@"GMT+%ld", (long)h];
    }
    return abbr;
}

- (BOOL)isDaylightSavingTime {
    return [self isDaylightSavingTimeForDate:[NSDate date]];
}

- (BOOL)isDaylightSavingTimeForDate:(NSDate *)aDate {
    if (_parsed == nil) return NO;
    NTZData d;
    if (!NTZParse(_parsed, &d)) return NO;
    return NTZIsDSTAt(&d, [aDate timeIntervalSince1970]);
}

- (NSTimeInterval)daylightSavingTimeOffset {
    return [self daylightSavingTimeOffsetForDate:[NSDate date]];
}

- (NSTimeInterval)daylightSavingTimeOffsetForDate:(NSDate *)aDate {
    if (_parsed == nil) return 0.0;
    NTZData d;
    if (!NTZParse(_parsed, &d)) return 0.0;
    return NTZDSTOffsetAt(&d, [aDate timeIntervalSince1970]);
}

- (NSDate *)nextDaylightSavingTimeTransition {
    return [self nextDaylightSavingTimeTransitionAfterDate:[NSDate date]];
}

- (NSDate *)nextDaylightSavingTimeTransitionAfterDate:(NSDate *)aDate {
    if (_parsed == nil) return nil;
    NTZData d;
    if (!NTZParse(_parsed, &d)) return nil;
    return NTZNextDSTTransition(&d, [aDate timeIntervalSince1970]);
}

- (BOOL)isEqualToTimeZone:(NSTimeZone *)aTimeZone {
    if (aTimeZone == nil) return NO;
    if (self == aTimeZone) return YES;
    if ([aTimeZone class] != [self class]) return NO;
    if (_parsed != nil) {
        return [_name isEqualToString:[aTimeZone name]];
    }
    return _secondsFromGMT == [aTimeZone secondsFromGMT] &&
           [_name isEqualToString:[aTimeZone name]];
}

- (BOOL)isEqual:(id)object {
    return [self isEqualToTimeZone:(NSTimeZone *)object];
}

- (NSUInteger)hash { return [_name hash]; }

- (id)copyWithZone:(NSZone *)zone { return self; }

- (NSString *)localizedName:(NSTimeZoneNameStyle)style locale:(NSLocale *)locale {
    (void)style;
    (void)locale;
    return [self name];
}

@end