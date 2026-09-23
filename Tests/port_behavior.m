#import <Foundation/Foundation.h>
#import <CoreFoundation/CFBase.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <limits.h>
#include <math.h>
#include <objc/runtime.h>

#pragma clang diagnostic ignored "-Wobjc-literal-conversion"

static void p(const char *label, NSString *value) {
    printf("%-42s | %s\n", label, value ? value.UTF8String : "(null)");
}

static void exHandler(NSException *e) { (void)e; }

static NSString *csMember(NSCharacterSet *cs, unsigned int c) {
    return [NSString stringWithFormat:@"%d", [cs characterIsMember:(unichar)c]];
}

static NSString *joinWith(NSArray *arr, NSString *sep) {
    NSMutableString *s = [NSMutableString stringWithCapacity:0];
    NSUInteger n = [arr count];
    for (NSUInteger i = 0; i < n; i++) {
        if (i != 0) [s appendString:sep];
        [s appendString:[arr objectAtIndex:i]];
    }
    return [NSString stringWithFormat:@"%@", s];
}

static NSString *nnInfo(NSNumber *n) {
    return [NSString stringWithFormat:@"%s %@", [n objCType], [n stringValue]];
}

static NSString *fmtRange(NSRange r) {
    return [NSString stringWithFormat:@"{%lu,%lu}", (unsigned long)r.location, (unsigned long)r.length];
}

static NSString *sortedJoin(NSArray *arr) {
    if (arr.count == 0) return @"";
    NSString * __unsafe_unretained *buf = (NSString * __unsafe_unretained *)calloc(arr.count, sizeof(NSString *));
    for (NSUInteger i = 0; i < arr.count; i++) buf[i] = [arr objectAtIndex:i];
    qsort_b(buf, arr.count, sizeof(NSString *), ^int(const void *a, const void *b) {
        return [*(NSString * const *)a compare:*(NSString * const *)b];
    });
    NSMutableString *out = [NSMutableString string];
    for (NSUInteger i = 0; i < arr.count; i++) {
        if (i > 0) [out appendString:@","];
        [out appendString:buf[i]];
    }
    free(buf);
    return out;
}

static NSString *sortedKeys(NSDictionary *dict) {
    return sortedJoin(dict.allKeys);
}

static void catchProbe(const char *label, id (^block)(void)) {
    @try {
        id v = block();
        p(label, v == nil ? @"nil" : [NSString stringWithFormat:@"%@", v]);
    } @catch (id e) {
        p(label, [NSString stringWithFormat:@"raise %@", [e name]]);
    }
}

static NSString *sortedObjects(NSSet *set) {
    return sortedJoin(set.allObjects);
}

static NSString *plainJoin(NSArray *arr, NSString *sep) {
    NSMutableString *out = [NSMutableString string];
    for (NSUInteger i = 0; i < arr.count; i++) {
        if (i > 0) [out appendString:sep];
        [out appendString:[arr objectAtIndex:i]];
    }
    return out;
}

static NSDecimal dmv(int limb, int exponent, int negative) {
    NSDecimal d;
    memset(&d, 0, sizeof d);
    if (limb != 0) {
        d._mantissa[0] = (unsigned short)(limb & 0xffff);
        d._length = 1;
    }
    d._exponent = (signed char)exponent;
    d._isNegative = (unsigned int)(negative ? 1 : 0);
    d._isCompact = 1;
    return d;
}

static NSString *dmfmt(NSDecimal *d, NSCalculationError err) {
    return [NSString stringWithFormat:@"%@ err=%ld", NSDecimalString(d, nil), (long)err];
}

static NSString *dmround(NSDecimal *r, NSDecimal *v, NSInteger scale, NSRoundingMode mode) {
    NSDecimalRound(r, v, scale, mode);
    return NSDecimalString(r, nil);
}

static NSString *calFmt(NSCalendar *cal, NSDate *d) {
    if (!d) return @"(nil)";
    NSDateComponents *c = [cal components:(NSCalendarUnitYear | NSCalendarUnitMonth | NSCalendarUnitDay |
                                           NSCalendarUnitHour | NSCalendarUnitMinute | NSCalendarUnitSecond)
                                fromDate:d];
    return [NSString stringWithFormat:@"%04ld-%02ld-%02ld %02ld:%02ld:%02ld",
            (long)c.year, (long)c.month, (long)c.day,
            (long)c.hour, (long)c.minute, (long)c.second];
}

static void p_cal(const char *label, NSCalendar *cal, NSDate *got, NSString *expected) {
    NSString *gots = calFmt(cal, got);
    BOOL ok = [gots isEqualToString:expected];
    p(label, [NSString stringWithFormat:@"%s%s", gots.UTF8String, ok ? "" : "  <<< DIFF"]);
}

static void calCheck(NSCalendar *cal, const char *label, NSDate *base,
                     NSDateComponents *comps, NSCalendarOptions opts, NSString *expected) {
    NSDate *got = [cal nextDateAfterDate:base matchingComponents:comps options:opts];
    p_cal(label, cal, got, expected);
}

static void calCheckUnit(NSCalendar *cal, const char *label, NSDate *base,
                         NSCalendarUnit unit, NSInteger value, NSCalendarOptions opts, NSString *expected) {
    NSDate *got = [cal nextDateAfterDate:base matchingUnit:unit value:value options:opts];
    p_cal(label, cal, got, expected);
}

int main(void) {
    /* Line-buffer stdout so a crash reveals the exact failing probe. */
    setvbuf(stdout, NULL, _IOLBF, 0);
    /* Pin the process timezone so calendar probes are deterministic and the
     * golden file is portable across machines.  Both the port and Apple honor
     * the TZ environment variable. */
    setenv("TZ", "UTC", 1);
    tzset();
    printf("PORT_BEHAVIOR_BEGIN\n");

    /* ---------- NSDate ---------- */
    NSDate *d0 = [NSDate dateWithTimeIntervalSinceReferenceDate:0.0];
    p("date ref0 -1970", [NSString stringWithFormat:@"%.9f", d0.timeIntervalSince1970]);
    p("date ref0 -ref", [NSString stringWithFormat:@"%.9f", d0.timeIntervalSinceReferenceDate]);
    p("date 0.0 desc", d0.description);
    NSDate *d1 = [NSDate dateWithTimeIntervalSince1970:1234567890.0];
    p("d1 -1970", [NSString stringWithFormat:@"%.9f", d1.timeIntervalSince1970]);
    p("d1 -ref", [NSString stringWithFormat:@"%.9f", d1.timeIntervalSinceReferenceDate]);
    NSDate *d2 = [d1 dateByAddingTimeInterval:3600.0];
    p("d2 add 3600 to d1", [NSString stringWithFormat:@"%.9f", d2.timeIntervalSince1970]);
    p("d2 earlierDate d1", ([d1 earlierDate:d2] == d1 && [d2 earlierDate:d1] == d1) ? @"==d1" : @"!=d1");
    p("d1 laterDate d2", ([d1 laterDate:d2] == d2 && [d2 laterDate:d1] == d2) ? @"==d2" : @"!=d2");
    p("compare d1 vs d2", [NSString stringWithFormat:@"%ld", (long)[d1 compare:d2]]);
    p("compare d2 vs d1", [NSString stringWithFormat:@"%ld", (long)[d2 compare:d1]]);
    p("isEqualToDate same", [NSString stringWithFormat:@"%d", [d1 isEqualToDate:[d1 copy]]]);
    p("timeIntervalSinceDate", [NSString stringWithFormat:@"%.9f", [d2 timeIntervalSinceDate:d1]]);
    p("distantFuture ref", [NSString stringWithFormat:@"%.9f", [NSDate distantFuture].timeIntervalSinceReferenceDate]);
    p("distantPast ref", [NSString stringWithFormat:@"%.9f", [NSDate distantPast].timeIntervalSinceReferenceDate]);
    p("now ~ today", [NSString stringWithFormat:@"%d", [NSDate now].timeIntervalSinceReferenceDate > 700000000.0]);

    /* ---------- NSNumber ---------- */
    /* Factories instead of @-literals: the compiler lowers @42/@YES/@3.14 to
     * Apple-only NSConstant*Number classes the port does not ship. */
    NSNumber *nInt = [NSNumber numberWithInt:42];
    p("nInt intValue", [NSString stringWithFormat:@"%ld", (long)nInt.integerValue]);
    p("nInt objCType", [NSString stringWithFormat:@"%s", nInt.objCType]);
    p("nBool boolValue", [NSString stringWithFormat:@"%d", [[NSNumber numberWithBool:YES] boolValue]]);
    p("nBool trueValue", [NSString stringWithFormat:@"%d", [[NSNumber numberWithBool:NO] boolValue]]);
    NSNumber *nFloat = [NSNumber numberWithDouble:3.14159];
    p("nFloat doubleValue", [NSString stringWithFormat:@"%.5f", nFloat.doubleValue]);
    p("nFloat floatValue", [NSString stringWithFormat:@"%.5f", nFloat.floatValue]);
    NSNumber *nLng = [NSNumber numberWithLongLong:9007199254740993LL];
    p("nLng longLongValue", [NSString stringWithFormat:@"%lld", nLng.longLongValue]);
    NSNumber *nChar = [NSNumber numberWithChar:'A'];
    p("nChar charValue", [NSString stringWithFormat:@"%c", (char)nChar.charValue]);
    p("compare 1 vs 2", [NSString stringWithFormat:@"%ld", (long)[[NSNumber numberWithInt:1] compare:[NSNumber numberWithInt:2]]]);
    p("compare 2 vs 1", [NSString stringWithFormat:@"%ld", (long)[[NSNumber numberWithInt:2] compare:[NSNumber numberWithInt:1]]]);
    p("equalNumber 42", [NSString stringWithFormat:@"%d", [nInt isEqualToNumber:[NSNumber numberWithInt:42]]]);
    p("equalNumber 43", [NSString stringWithFormat:@"%d", [nInt isEqualToNumber:[NSNumber numberWithInt:43]]]);
    p("intvalue from numWithInt", [NSString stringWithFormat:@"%ld", (long)[NSNumber numberWithInt:-7].intValue]);

    /* ---------- NSString ---------- */
    NSString *s = @"Hello, Foundation";
    p("str len", [NSString stringWithFormat:@"%lu", (unsigned long)s.length]);
    p("str charAt0", [NSString stringWithFormat:@"%c", [s characterAtIndex:0]]);
    p("str charAt7", [NSString stringWithFormat:@"%c", [s characterAtIndex:7]]);
    p("str substr(0,5)", [s substringWithRange:NSMakeRange(0, 5)]);
    p("str substringFromIndex 7", [s substringFromIndex:7]);
    p("str substringToIndex 5", [s substringToIndex:5]);
    p("str hasPrefix Hello", [NSString stringWithFormat:@"%d", [s hasPrefix:@"Hello"]]);
    p("str hasPrefix hey", [NSString stringWithFormat:@"%d", [s hasPrefix:@"hey"]]);
    p("str hasSuffix Foundation", [NSString stringWithFormat:@"%d", [s hasSuffix:@"Foundation"]]);
    p("str containsString Found", [NSString stringWithFormat:@"%d", [s containsString:@"Found"]]);
    p("str isEqualToString", [NSString stringWithFormat:@"%d", [s isEqualToString:@"Hello, Foundation"]]);
    p("str != other", [NSString stringWithFormat:@"%d", [s isEqualToString:@"hello, foundation"]]);
    p("str lowercase", s.lowercaseString);
    p("str uppercase", s.uppercaseString);
    p("str stringByAppending", [s stringByAppendingString:@"!"]);

    NSString *fmt = [NSString stringWithFormat:@"%d + %d = %d", 2, 3, 2 + 3];
    p("str format ints", fmt);
    NSString *fmtf = [NSString stringWithFormat:@"%.2f %@ %s", 3.14159, @"pi", "nice"];
    p("str format mixed", fmtf);
    p("str rangeOfString Found", fmtRange([s rangeOfString:@"Found"]));
    p("str rangeOfString xyz", fmtRange([s rangeOfString:@"xyz"]));
    p("str compare case", [NSString stringWithFormat:@"%ld", (long)[@"apple" compare:@"banana"]]);
    p("str compareIC ab", [NSString stringWithFormat:@"%ld", (long)[@"ABC" caseInsensitiveCompare:@"abc"]]);
    p("str trim ws", [@"  padded  " stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]]);

    NSString *csv = @"a,b,c,,e";
    NSArray *parts = [csv componentsSeparatedByString:@","];
    p("csv count", [NSString stringWithFormat:@"%lu", (unsigned long)parts.count]);
    p("csv joined", plainJoin(parts, @"|"));

    NSMutableString *mut = [NSMutableString stringWithCapacity:16];
    [mut appendString:@"foo"];
    p("mutable append", mut);
    [mut appendFormat:@"-%d", 42];
    p("mutable appendFormat", mut);
    [mut setString:@"reset"];
    p("mutable setString", mut);
    [mut replaceCharactersInRange:NSMakeRange(0, 2) withString:@"XY"];
    p("mutable replaceRange", mut);
    [mut deleteCharactersInRange:NSMakeRange(1, 1)];
    p("mutable deleteRange", mut);
    [mut insertString:@"Z" atIndex:0];
    p("mutable insert", mut);

    NSString *rep = [@"one two one" stringByReplacingOccurrencesOfString:@"one" withString:@"1"];
    p("str replaceOccurrences", rep);
    p("str UTF8 roundtrip", [NSString stringWithUTF8String:"caf\xc3\xa9"]);

    /* ---------- NSURL ---------- */
    NSURL *u1 = [NSURL URLWithString:@"https://example.com/path?q=1#frag"];
    p("url absoluteString", u1.absoluteString);
    p("url isFileURL", [NSString stringWithFormat:@"%d", u1.isFileURL]);
    NSURL *u2 = [NSURL fileURLWithPath:@"/tmp/my file.txt"];
    p("url file isFileURL", [NSString stringWithFormat:@"%d", u2.isFileURL]);
    p("url file path", u2.path);
    p("url bad -> nil", [NSString stringWithFormat:@"%d", [NSURL URLWithString:@""] == nil]);

    /* NSURL contract bundle (CFURL bridge, port NSURL is the bridged isa) */
    p("uu init string abs", [[[[NSURL alloc] initWithString:@"https://x.example/pa?q=2"] absoluteString] description]);
    catchProbe("uu init string nil", ^{ return [[[NSURL alloc] initWithString:nil] absoluteString]; });
    /* Space-containing strings are dropped: Apple's private URL parser
     * percent-encodes them ("has space" -> has%20space), the port delegates to
     * strict CFURLCreateWithString which rejects them. Documented gap, not
     * probed. */
    p("uu absolute file", [[NSURL fileURLWithPath:@"/tmp/my file.txt"] absoluteString]);
    p("uu path http", [[NSURL URLWithString:@"https://x.example/pa?q=2"] path] == nil ? @"nil" : [[NSURL URLWithString:@"https://x.example/pa?q=2"] path]);
    p("uu path root file", [[NSURL fileURLWithPath:@"/"] path]);
    /* "not a url" and the ftp-with-space case are also Apple-parser-only (see
     * the space comment above) and are not probed. */
    catchProbe("uu nsstring nil", ^{ return [NSURL URLWithString:nil] != nil ? @"1" : @"0"; });
    p("uu file scheme init", [[[NSURL alloc] initWithString:@"file:///a/b"] isFileURL] ? @"1" : @"0");
    p("uu http scheme init", [[[NSURL alloc] initWithString:@"http://e/"] isFileURL] ? @"1" : @"0");
    p("uu file localhost path", [[NSURL URLWithString:@"file://localhost/etc/hosts"] path]);
    p("uu fragment abs", [[NSURL URLWithString:@"https://x/#f"] absoluteString]);

    /* ---------- NSArray ---------- */
    /* Built via +arrayWithObjects:count: (no @[] literal: the compiler lowers
     * that to the Apple-only NSConstantArray class the port does not ship). */
    NSArray *a = [NSArray arrayWithObjects:(id[]){@"z", @"a", @"m"} count:3];
    p("array count", [NSString stringWithFormat:@"%lu", (unsigned long)a.count]);
    p("array idx0", a[0]);
    p("array idx2", [a objectAtIndex:2]);
    p("array contains a", [NSString stringWithFormat:@"%d", [a containsObject:@"a"]]);
    p("array contains q", [NSString stringWithFormat:@"%d", [a containsObject:@"q"]]);
    NSEnumerator *en = a.objectEnumerator;
    p("enumerator next1", en.nextObject);
    p("enumerator next2", en.nextObject);
    p("enumerator next3", en.nextObject);
    p("enumerator next4", en.nextObject);
    NSEnumerator *ren = a.reverseObjectEnumerator;
    p("rev enumerate", plainJoin(ren.allObjects, @","));
    NSMutableArray *ma = [NSMutableArray arrayWithArray:a];
    [ma addObject:@"b"];
    p("mutable addObject", plainJoin(ma, @","));
    [ma removeObjectAtIndex:0];
    p("mutable removeObjIdx0", plainJoin(ma, @","));
    [ma removeAllObjects];
    p("mutable count after removeAll", [NSString stringWithFormat:@"%lu", (unsigned long)ma.count]);

    /* ---------- NSSet ---------- */
    NSSet *set = [NSSet setWithObjects:@"x", @"y", @"y", nil];
    p("set count", [NSString stringWithFormat:@"%lu", (unsigned long)set.count]);
    p("set contains x", [NSString stringWithFormat:@"%d", [set containsObject:@"x"]]);
    p("set contains z", [NSString stringWithFormat:@"%d", [set containsObject:@"z"]]);
    p("set member x", [set member:@"x"]);
    p("set sortedObjects", sortedObjects(set));
    NSSet *sub = [NSSet setWithObjects:@"x", nil];
    p("set isSubsetOf", [NSString stringWithFormat:@"%d", [sub isSubsetOfSet:set]]);
    p("set isSubsetOf reverse", [NSString stringWithFormat:@"%d", [set isSubsetOfSet:sub]]);
    NSSet *aug = [set setByAddingObject:@"w"];
    p("set add w count/sorted", [NSString stringWithFormat:@"%lu=%@", (unsigned long)aug.count, sortedObjects(aug)]);

    /* ---------- NSDictionary ---------- */
    /* Built via +dictionaryWithObjects:forKeys:count: (no @{} literal: the
     * compiler lowers that to the Apple-only NSConstantDictionary class). */
    NSDictionary *dict = [NSDictionary dictionaryWithObjects:(id[]){@"2", @"1", @"3"}
                                                      forKeys:(id[]){@"b", @"a", @"c"}
                                                        count:3];
    p("dict count", [NSString stringWithFormat:@"%lu", (unsigned long)dict.count]);
    p("dict a", dict[@"a"]);
    p("dict c", [dict objectForKey:@"c"]);
    p("dict missing", [NSString stringWithFormat:@"%d", [dict objectForKey:@"z"] == nil]);
    p("dict sortedKeys", sortedKeys(dict));
    NSSet *kset = [NSSet setWithArray:dict.allKeys];
    p("dict allKeys via set", [NSString stringWithFormat:@"%@", sortedObjects(kset)]);
    NSMutableDictionary *md = [NSMutableDictionary dictionary];
    md[@"k1"] = @"v1";
    [md setObject:@"v2" forKey:@"k2"];
    p("mutable dict count", [NSString stringWithFormat:@"%lu", (unsigned long)md.count]);
    p("mutable dict k1", md[@"k1"]);
    [md removeObjectForKey:@"k1"];
    p("mutable dict count after remove", [NSString stringWithFormat:@"%lu", (unsigned long)md.count]);
    p("mutable dict k2", md[@"k2"]);

    /* ---------- NSData ---------- */
    const unsigned char bytes[] = {0x00, 0x01, 0x02, 0x80, 0xff, 0x10, 0x20, 0x30};
    NSData *data = [NSData dataWithBytes:bytes length:8];
    p("data length", [NSString stringWithFormat:@"%lu", (unsigned long)data.length]);
    const unsigned char *dbytes = (const unsigned char *)data.bytes;
    p("data byte0", [NSString stringWithFormat:@"%02x", dbytes[0]]);
    p("data byte3", [NSString stringWithFormat:@"%02x", dbytes[3]]);
    p("data byte7", [NSString stringWithFormat:@"%02x", dbytes[7]]);
    NSData *subd = [data subdataWithRange:NSMakeRange(2, 3)];
    p("subdata len", [NSString stringWithFormat:@"%lu", (unsigned long)subd.length]);
    const unsigned char *sb = (const unsigned char *)subd.bytes;
    p("subdata b0", [NSString stringWithFormat:@"%02x", sb[0]]);
    p("subdata b2", [NSString stringWithFormat:@"%02x", sb[2]]);
    p("isEqualToData same", [NSString stringWithFormat:@"%d", [data isEqualToData:[data copy]]]);
    p("isEqualToData diff", [NSString stringWithFormat:@"%d", [data isEqualToData:subd]]);

    /* ---------- NSCalendar ---------- */
    NSCalendar *cal = [NSCalendar calendarWithIdentifier:NSCalendarIdentifierGregorian];
    NSDateComponents *hms = [NSDateComponents new];
    hms.hour = 10; hms.minute = 0; hms.second = 0;
    NSDate *t1 = [cal dateWithEra:1 year:2024 month:3 day:15 hour:10 minute:0 second:0 nanosecond:0];
    calCheck(cal, "cal self-match opts=0", t1, hms, 0, @"2024-03-16 10:00:00");
    calCheck(cal, "cal self-match strict", t1, hms, NSCalendarMatchStrictly, @"2024-03-16 10:00:00");

    NSDateComponents *d3 = [NSDateComponents new]; d3.day = 3;
    NSDate *j5 = [cal dateWithEra:1 year:2024 month:1 day:5 hour:0 minute:0 second:0 nanosecond:0];
    calCheck(cal, "cal day=3 from Jan 5", j5, d3, 0, @"2024-02-03 00:00:00");
    NSDateComponents *d15 = [NSDateComponents new]; d15.day = 15;
    NSDate *j20 = [cal dateWithEra:1 year:2024 month:1 day:20 hour:0 minute:0 second:0 nanosecond:0];
    calCheck(cal, "cal day=15 from Jan 20", j20, d15, 0, @"2024-02-15 00:00:00");

    NSDateComponents *f29 = [NSDateComponents new]; f29.month = 2; f29.day = 29;
    NSDate *mar21 = [cal dateWithEra:1 year:2024 month:3 day:1 hour:0 minute:0 second:0 nanosecond:0];
    calCheck(cal, "cal feb29 opts=0", mar21, f29, 0, @"2025-03-01 00:00:00");
    calCheck(cal, "cal feb29 +NextTime", mar21, f29, NSCalendarMatchNextTime, @"2025-03-01 00:00:00");
    calCheck(cal, "cal feb29 strict", mar21, f29, NSCalendarMatchStrictly, @"2028-02-29 00:00:00");
    NSDate *mar22 = [cal dateWithEra:1 year:2022 month:3 day:1 hour:0 minute:0 second:0 nanosecond:0];
    calCheck(cal, "cal feb29 from Mar1 2022", mar22, f29, 0, @"2023-03-01 00:00:00");
    NSDate *mar27 = [cal dateWithEra:1 year:2027 month:3 day:1 hour:0 minute:0 second:0 nanosecond:0];
    calCheck(cal, "cal feb29 from Mar1 2027", mar27, f29, 0, @"2028-02-29 00:00:00");

    NSDateComponents *fri = [NSDateComponents new]; fri.weekday = 6;
    NSDate *wed = [cal dateWithEra:1 year:2024 month:3 day:13 hour:0 minute:0 second:0 nanosecond:0];
    calCheck(cal, "cal weekday=6 Fri", wed, fri, 0, @"2024-03-15 00:00:00");

    NSDateComponents *h6 = [NSDateComponents new]; h6.hour = 6;
    NSDate *t1000 = [cal dateWithEra:1 year:2024 month:3 day:15 hour:10 minute:0 second:0 nanosecond:0];
    calCheck(cal, "cal hour=6 from 10:00", t1000, h6, 0, @"2024-03-16 06:00:00");

    calCheckUnit(cal, "cal unit year=2030", t1000, NSCalendarUnitYear, 2030, 0, @"2030-01-01 00:00:00");
    calCheckUnit(cal, "cal unit year=2030 strict", t1000, NSCalendarUnitYear, 2030, NSCalendarMatchStrictly, @"2030-01-01 00:00:00");
    calCheckUnit(cal, "cal unit year=2020 past", t1000, NSCalendarUnitYear, 2020, 0, @"(nil)");

    NSDateComponents *f30 = [NSDateComponents new]; f30.month = 2; f30.day = 30;
    calCheck(cal, "cal feb30 strict", mar21, f30, NSCalendarMatchStrictly, @"(nil)");

    NSDateComponents *q1 = [NSDateComponents new]; q1.quarter = 1;
    NSDate *may5 = [cal dateWithEra:1 year:2024 month:5 day:5 hour:0 minute:0 second:0 nanosecond:0];
    calCheck(cal, "cal quarter=1 from May5", may5, q1, 0, @"2025-01-01 00:00:00");

    NSDateComponents *empty = [NSDateComponents new];
    calCheck(cal, "cal empty comps", t1, empty, 0, @"(nil)");

    /* ---------- NSLocale ---------- */
    /* Explicit identifiers only: the golden stays portable (current/system
     * locale follow host preferences).  The port and Apple both read locale
     * data from CoreFoundation. */
    NSLocale *lUS = [NSLocale localeWithLocaleIdentifier:@"en_US"];
    p("locale en_US identifier", lUS.localeIdentifier);
    p("locale en_US country", [lUS objectForKey:NSLocaleCountryCode]);
    p("locale en_US currency", [lUS objectForKey:NSLocaleCurrencyCode]);
    p("locale en_US decimalSep", [lUS objectForKey:NSLocaleDecimalSeparator]);
    p("locale en_US groupSep", [lUS objectForKey:NSLocaleGroupingSeparator]);
    p("locale en_US usesMetric", [NSString stringWithFormat:@"%@", [lUS objectForKey:NSLocaleUsesMetricSystem]]);
    NSLocale *lDE = [NSLocale localeWithLocaleIdentifier:@"de_DE"];
    p("locale de_DE identifier", lDE.localeIdentifier);
    p("locale de_DE country", [lDE objectForKey:NSLocaleCountryCode]);
    p("locale de_DE currency", [lDE objectForKey:NSLocaleCurrencyCode]);
    p("locale de_DE decimalSep", [lDE objectForKey:NSLocaleDecimalSeparator]);
    p("locale de_DE groupSep", [lDE objectForKey:NSLocaleGroupingSeparator]);
    p("locale en displayName fr", [lUS displayNameForKey:NSLocaleLanguageCode value:@"fr"]);
    p("locale en displayName Country:DE", [lUS displayNameForKey:NSLocaleCountryCode value:@"DE"]);
    p("locale de displayName fr", [lDE displayNameForKey:NSLocaleLanguageCode value:@"fr"]);
    p("locale en_US isEqual en_US", [NSString stringWithFormat:@"%d", [lUS isEqual:[NSLocale localeWithLocaleIdentifier:@"en_US"]]]);
    p("locale en_US isEqual de_DE", [NSString stringWithFormat:@"%d", [lUS isEqual:lDE]]);
    p("locale equal hash", [NSString stringWithFormat:@"%lu=%lu", (unsigned long)lUS.hash, (unsigned long)[NSLocale localeWithLocaleIdentifier:@"en_US"].hash]);
    p("locale copy roundtrip", [[lUS copy] localeIdentifier]);
    p("locale init alloc de_DE", [[[NSLocale alloc] initWithLocaleIdentifier:@"de_DE"] localeIdentifier]);
    p("locale autoupdating eq current", [[NSLocale autoupdatingCurrentLocale].localeIdentifier isEqualToString:[NSLocale currentLocale].localeIdentifier] ? @"1" : @"0");
    p("locale preferred count", [NSLocale preferredLanguages].count > 0 ? @"1" : @"0");
    p("locale available count", [NSLocale availableLocaleIdentifiers].count > 100 ? @"1" : @"0");
    p("locale avail contains en_US", [[NSLocale availableLocaleIdentifiers] containsObject:@"en_US"] ? @"1" : @"0");
    p("locale avail contains de_DE", [[NSLocale availableLocaleIdentifiers] containsObject:@"de_DE"] ? @"1" : @"0");
    p("locale availloc contains qq", [[NSLocale availableLocaleIdentifiers] containsObject:@"qq"] ? @"1" : @"0");
    p("locale lang contains en", [[NSLocale ISOLanguageCodes] containsObject:@"en"] ? @"1" : @"0");
    p("locale lang contains qq", [[NSLocale ISOLanguageCodes] containsObject:@"qq"] ? @"1" : @"0");
    p("locale country contains US", [[NSLocale ISOCountryCodes] containsObject:@"US"] ? @"1" : @"0");
    p("locale country contains GB", [[NSLocale ISOCountryCodes] containsObject:@"GB"] ? @"1" : @"0");
    p("locale country contains qq", [[NSLocale ISOCountryCodes] containsObject:@"qq"] ? @"1" : @"0");
    p("locale currency contains USD", [[NSLocale ISOCurrencyCodes] containsObject:@"USD"] ? @"1" : @"0");
    p("locale currency contains JPY", [[NSLocale ISOCurrencyCodes] containsObject:@"JPY"] ? @"1" : @"0");
    p("locale currency contains qqq", [[NSLocale ISOCurrencyCodes] containsObject:@"QQQ"] ? @"1" : @"0");
    p("locale common currencies", ([[NSLocale commonISOCurrencyCodes] containsObject:@"USD"] &&
                                   [[NSLocale commonISOCurrencyCodes] containsObject:@"EUR"] &&
                                   [[NSLocale commonISOCurrencyCodes] containsObject:@"JPY"] &&
                                   [[NSLocale commonISOCurrencyCodes] containsObject:@"GBP"]) ? @"1" : @"0");

    /* ---------- NSDateFormatter ---------- */
    /* ASCII-only date formats (digits never localize) keep the output
     * independent of the host locale; TZ=UTC is pinned at the top of main. */
    NSDateFormatter *dfmt = [[NSDateFormatter alloc] init];
    p("df default dateStyle", [NSString stringWithFormat:@"%lu", (unsigned long)dfmt.dateStyle]);
    p("df default timeStyle", [NSString stringWithFormat:@"%lu", (unsigned long)dfmt.timeStyle]);
    [dfmt setDateFormat:@"yyyy-MM-dd HH:mm:ss"];
    p("df dateFormat getter", dfmt.dateFormat);
    NSDate *fmtBase = [NSDate dateWithTimeIntervalSince1970:1234567890.0];
    p("df stringFromDate ymd", [dfmt stringFromDate:fmtBase]);
    p("df parse roundtrip", [NSString stringWithFormat:@"%.0f", [dfmt dateFromString:@"2009-02-13 23:31:30"].timeIntervalSince1970]);
    p("df parse invalid nil", [NSString stringWithFormat:@"%d", [dfmt dateFromString:@"garbage"] == nil]);
    NSDateFormatter *dfmtMillis = [[NSDateFormatter alloc] init];
    [dfmtMillis setDateFormat:@"yyyy-MM-dd HH:mm:ss.SSS"];
    p("df fractional SSS", [dfmtMillis stringFromDate:fmtBase]);
    NSDateFormatter *dfLen = [[NSDateFormatter alloc] init];
    p("df lenient default", [NSString stringWithFormat:@"%d", dfLen.isLenient]);
    [dfLen setLenient:YES];
    p("df lenient set", [NSString stringWithFormat:@"%d", dfLen.isLenient]);
    p("df defaultDate default nil", [NSString stringWithFormat:@"%d", dfLen.defaultDate == nil]);
    [dfLen setDateFormat:@"yyyy-MM-dd"];
    [dfLen setDefaultDate:[NSDate dateWithTimeIntervalSince1970:1234567890.0]];
    p("df defaultDate getter", [NSString stringWithFormat:@"%.0f", dfLen.defaultDate.timeIntervalSince1970]);
    NSDate *dfParsed = [dfLen dateFromString:@"2009-02-13"];
    p("df defaultDate parse", [NSString stringWithFormat:@"%.0f|%@", dfParsed.timeIntervalSince1970, [dfLen stringFromDate:dfParsed]]);
    NSDateFormatter *dfLoc = [[NSDateFormatter alloc] init];
    [dfLoc setLocale:[NSLocale localeWithLocaleIdentifier:@"fr_FR"]];
    p("df locale set roundtrip", dfLoc.locale.localeIdentifier);
    [dfLoc setDateFormat:@"yyyy-MM-dd HH:mm:ss"];
    p("df locale formatted", [dfLoc stringFromDate:fmtBase]);
    NSDateFormatter *dfObj = [[NSDateFormatter alloc] init];
    [dfObj setDateFormat:@"yyyy-MM-dd HH:mm:ss"];
    id dv = nil;
    NSError *derr = nil;
    NSRange dr = NSMakeRange(0, 19);
    BOOL dgot = [dfObj getObjectValue:&dv forString:@"2009-02-13 23:31:30" range:&dr error:&derr];
    p("df getObjectValue ok", [NSString stringWithFormat:@"%d val=%.0f err=%d range=%ld/%ld",
                               dgot, dv ? [dv timeIntervalSince1970] : 0.0, derr != nil,
                               (long)dr.location, (long)dr.length]);
    dv = nil;
    derr = nil;
    dgot = [dfObj getObjectValue:&dv forString:@"garbage" range:NULL error:&derr];
    p("df getObjectValue bad", [NSString stringWithFormat:@"%d val=%d err=%d", dgot, dv != nil, derr != nil]);
    NSDateFormatter *dfTZ = [[NSDateFormatter alloc] init];
    [dfTZ setDateFormat:@"yyyy-MM-dd HH:mm:ss"];
    p("df tz default name", [dfTZ timeZone].name);
    [dfTZ setTimeZone:[NSTimeZone timeZoneWithName:@"Asia/Tokyo"]];
    p("df tz tokyo name", [dfTZ timeZone].name);
    p("df tz tokyo spread", [dfTZ stringFromDate:fmtBase]);
    [dfTZ setTimeZone:[NSTimeZone timeZoneWithName:@"America/New_York"]];
    p("df tz ny spread", [dfTZ stringFromDate:fmtBase]);
    [dfTZ setTimeZone:nil];
    p("df tz nil spread", [dfTZ stringFromDate:fmtBase]);
    NSDateFormatter *dfCal = [[NSDateFormatter alloc] init];
    [dfCal setDateFormat:@"yyyy-MM-dd"];
    p("df cal default id", dfCal.calendar.calendarIdentifier);
    [dfCal setCalendar:[NSCalendar calendarWithIdentifier:NSCalendarIdentifierGregorian]];
    p("df cal set id", dfCal.calendar.calendarIdentifier);
    [dfCal setCalendar:[NSCalendar calendarWithIdentifier:NSCalendarIdentifierIslamic]];
    p("df cal islamic id", dfCal.calendar.calendarIdentifier);
    p("df cal islamic spread", [dfCal stringFromDate:fmtBase]);
    [dfCal setCalendar:nil];
    p("df cal reset id", dfCal.calendar.calendarIdentifier);

    /* ---------- NSScanner ---------- */
    NSScanner *sc = [NSScanner scannerWithString:@"  123 45"];
    int scVal = 0;
    BOOL scOK = [sc scanInt:&scVal];
    p("sc int first", [NSString stringWithFormat:@"%d ok=%d loc=%ld", scVal, scOK, (long)sc.scanLocation]);
    p("sc atEnd between", [NSString stringWithFormat:@"%d", sc.isAtEnd]);
    scOK = [sc scanInt:&scVal];
    p("sc int second", [NSString stringWithFormat:@"%d ok=%d loc=%ld", scVal, scOK, (long)sc.scanLocation]);
    p("sc atEnd done", [NSString stringWithFormat:@"%d", sc.isAtEnd]);

    NSScanner *scL = [NSScanner scannerWithString:@"-9223372036854775808"];
    long long ll = 0;
    [scL scanLongLong:&ll];
    p("sc longlong min", [NSString stringWithFormat:@"%lld loc=%ld", ll, (long)scL.scanLocation]);
    NSScanner *scOv = [NSScanner scannerWithString:@"9223372036854775808"];
    [scOv scanLongLong:&ll];
    p("sc longlong overflow", [NSString stringWithFormat:@"%lld", ll]);
    NSScanner *scI2 = [NSScanner scannerWithString:@"2147483648"];
    [scI2 scanInt:&scVal];
    p("sc int overflows-max", [NSString stringWithFormat:@"%d", scVal]);

    unsigned long long ull = 0;
    NSScanner *scU = [NSScanner scannerWithString:@"18446744073709551615"];
    [scU scanUnsignedLongLong:&ull];
    p("sc ull max", [NSString stringWithFormat:@"%llu loc=%ld", ull, (long)scU.scanLocation]);

    unsigned hexV = 0;
    NSScanner *scH = [NSScanner scannerWithString:@"0xFF 10"];
    [scH scanHexInt:&hexV];
    p("sc hex ff", [NSString stringWithFormat:@"%u loc=%ld", hexV, (long)scH.scanLocation]);
    [scH scanHexInt:&hexV];
    p("sc hex second", [NSString stringWithFormat:@"%u loc=%ld", hexV, (long)scH.scanLocation]);

    double scD = 0.0;
    NSScanner *scDbl = [NSScanner scannerWithString:@"3.14159 rest"];
    [scDbl scanDouble:&scD];
    p("sc double", [NSString stringWithFormat:@"%.5f loc=%ld", scD, (long)scDbl.scanLocation]);
    NSScanner *scFlt = [NSScanner scannerWithString:@"1.5"];
    float scF = 0.0f;
    [scFlt scanFloat:&scF];
    p("sc float", [NSString stringWithFormat:@"%1.1f loc=%ld", scF, (long)scFlt.scanLocation]);

    NSString *scTok = nil;
    NSScanner *scS = [NSScanner scannerWithString:@"start foo end"];
    scOK = [scS scanUpToString:@"end" intoString:&scTok];
    p("sc upTo end", [NSString stringWithFormat:@"%@ ok=%d loc=%ld", scTok, scOK, (long)scS.scanLocation]);
    NSScanner *scCS = [NSScanner scannerWithString:@"abcDEF"];
    scTok = nil;
    scOK = [scCS scanCharactersFromSet:[NSCharacterSet lowercaseLetterCharacterSet] intoString:&scTok];
    p("sc chars lower", [NSString stringWithFormat:@"%@ ok=%d loc=%ld", scTok, scOK, (long)scCS.scanLocation]);
    NSScanner *scUpC = [NSScanner scannerWithString:@"a,b"];
    scTok = nil;
    [scUpC scanUpToCharactersFromSet:[NSCharacterSet characterSetWithCharactersInString:@","] intoString:&scTok];
    p("sc upToChars a", [NSString stringWithFormat:@"%@ loc=%ld", scTok, (long)scUpC.scanLocation]);

    NSScanner *scCI = [NSScanner scannerWithString:@"AbCextra"];
    scTok = nil;
    scOK = [scCI scanString:@"abc" intoString:&scTok];
    p("sc CI default match", [NSString stringWithFormat:@"%@ ok=%d loc=%ld", scTok, scOK, (long)scCI.scanLocation]);
    NSScanner *scCS2 = [NSScanner scannerWithString:@"AbCextra"];
    [scCS2 setCaseSensitive:YES];
    scOK = [scCS2 scanString:@"abc" intoString:&scTok];
    p("sc CI strict mismatch", [NSString stringWithFormat:@"ok=%d loc=%ld", scOK, (long)scCS2.scanLocation]);

    NSScanner *scLoc = [NSScanner scannerWithString:@"abc123"];
    [scLoc setScanLocation:3];
    scTok = nil;
    scOK = [scLoc scanCharactersFromSet:[NSCharacterSet decimalDigitCharacterSet] intoString:&scTok];
    p("sc manual loc digits", [NSString stringWithFormat:@"%@ ok=%d loc=%ld", scTok, scOK, (long)scLoc.scanLocation]);
    [scLoc setScanLocation:0];
    p("sc reset atEnd", [NSString stringWithFormat:@"%d", scLoc.isAtEnd]);
    NSScanner *scEmpty = [NSScanner scannerWithString:@""];
    p("sc empty isAtEnd", [NSString stringWithFormat:@"%d", scEmpty.isAtEnd]);

    NSScanner *scAtEnd = [NSScanner scannerWithString:@"abc"];
    [scAtEnd setScanLocation:3];
    p("sc loc at end", [NSString stringWithFormat:@"%ld", (long)scAtEnd.scanLocation]);
    catchProbe("sc loc past end", ^id{
        [scAtEnd setScanLocation:99];
        return [NSString stringWithFormat:@"loc=%ld", (long)scAtEnd.scanLocation];
    });
    NSScanner *scSkipDef = [NSScanner scannerWithString:@""];
    p("sc default skip sp", [scSkipDef.charactersToBeSkipped characterIsMember:' '] ? @"1" : @"0");
    p("sc default skip nl", [scSkipDef.charactersToBeSkipped characterIsMember:'\n'] ? @"1" : @"0");
    NSScanner *scNoSkip = [NSScanner scannerWithString:@"  42"];
    [scNoSkip setCharactersToBeSkipped:[NSCharacterSet characterSetWithCharactersInString:@""]];
    int scIV2 = -1;
    scOK = [scNoSkip scanInt:&scIV2];
    p("sc no skip scanInt", [NSString stringWithFormat:@"ok=%d val=%d loc=%ld", scOK, scIV2, (long)scNoSkip.scanLocation]);
    NSScanner *scHexLL = [NSScanner scannerWithString:@"  0xffffffffffffffff end"];
    unsigned long long scULL = 0;
    scOK = [scHexLL scanHexLongLong:&scULL];
    p("sc hexLongLong max", [NSString stringWithFormat:@"ok=%d val=%llu loc=%ld", scOK, scULL, (long)scHexLL.scanLocation]);
    NSScanner *scHexLLB = [NSScanner scannerWithString:@"  zz"];
    scOK = [scHexLLB scanHexLongLong:&scULL];
    p("sc hexLongLong bad", [NSString stringWithFormat:@"ok=%d loc=%ld", scOK, (long)scHexLLB.scanLocation]);
    NSScanner *scHexD = [NSScanner scannerWithString:@"  0x1.8p1"];
    double scHV = 0;
    scOK = [scHexD scanHexDouble:&scHV];
    p("sc hexDouble", [NSString stringWithFormat:@"ok=%d val=%.2f loc=%ld", scOK, scHV, (long)scHexD.scanLocation]);
    NSScanner *scHexF = [NSScanner scannerWithString:@"  0x1.8p1"];
    float scHF = 0;
    scOK = [scHexF scanHexFloat:&scHF];
    p("sc hexFloat", [NSString stringWithFormat:@"ok=%d val=%.6f loc=%ld", scOK, scHF, (long)scHexF.scanLocation]);
    NSScanner *scIntg = [NSScanner scannerWithString:@"  -42 rest"];
    NSInteger scIVal = 0;
    scOK = [scIntg scanInteger:&scIVal];
    p("sc integer neg", [NSString stringWithFormat:@"ok=%d val=%ld loc=%ld", scOK, (long)scIVal, (long)scIntg.scanLocation]);
    NSScanner *scMid = [NSScanner scannerWithString:@"alpha-beta"];
    scTok = nil;
    scOK = [scMid scanUpToCharactersFromSet:[NSCharacterSet characterSetWithCharactersInString:@"-"] intoString:&scTok];
    p("sc upToChars mid", [NSString stringWithFormat:@"%@ ok=%d loc=%ld", scTok, scOK, (long)scMid.scanLocation]);
    NSScanner *scHexB = [NSScanner scannerWithString:@"ABC"];
    scTok = nil;
    scOK = [scHexB scanString:@"abc" intoString:&scTok];
    p("sc CI match lower", [NSString stringWithFormat:@"%@ ok=%d loc=%ld", scTok, scOK, (long)scHexB.scanLocation]);

    NSScanner *scCp = [NSScanner scannerWithString:@"  123"];
    [scCp scanInt:&scVal];
    NSScanner *scCp2 = [scCp copy];
    p("sc copy location", [NSString stringWithFormat:@"%ld", (long)scCp2.scanLocation]);
    scVal = 0;
    [scCp2 setScanLocation:0];
    scOK = [scCp2 scanInt:&scVal];
    p("sc copy scans", [NSString stringWithFormat:@"%d ok=%d", scVal, scOK]);

    NSLocale *scLocDE = [NSLocale localeWithLocaleIdentifier:@"de_DE"];
    NSLocale *scLocEN = [NSLocale localeWithLocaleIdentifier:@"en_US"];
    double scLV = -1.0;
    NSScanner *scLD = [NSScanner scannerWithString:@"3,14"];
    scLD.locale = scLocDE;
    scOK = [scLD scanDouble:&scLV];
    p("sc loc de comma", [NSString stringWithFormat:@"ok=%d val=%.2f loc=%ld", scOK, scLV, (long)scLD.scanLocation]);
    scLV = -1.0;
    NSScanner *scLDot = [NSScanner scannerWithString:@"3.14"];
    scLDot.locale = scLocDE;
    scOK = [scLDot scanDouble:&scLV];
    p("sc loc de dot stop", [NSString stringWithFormat:@"ok=%d val=%.2f loc=%ld", scOK, scLV, (long)scLDot.scanLocation]);
    scLV = -1.0;
    NSScanner *scLGrp = [NSScanner scannerWithString:@"1.234,56"];
    scLGrp.locale = scLocDE;
    scOK = [scLGrp scanDouble:&scLV];
    p("sc loc de grouped", [NSString stringWithFormat:@"ok=%d val=%.2f loc=%ld", scOK, scLV, (long)scLGrp.scanLocation]);
    scLV = -1.0;
    NSScanner *scLExp = [NSScanner scannerWithString:@"3,14e2"];
    scLExp.locale = scLocDE;
    scOK = [scLExp scanDouble:&scLV];
    p("sc loc de exp", [NSString stringWithFormat:@"ok=%d val=%.2f loc=%ld", scOK, scLV, (long)scLExp.scanLocation]);
    scLV = -1.0;
    NSScanner *scLNeg = [NSScanner scannerWithString:@"-5,25"];
    scLNeg.locale = scLocDE;
    scOK = [scLNeg scanDouble:&scLV];
    p("sc loc de neg", [NSString stringWithFormat:@"ok=%d val=%.2f loc=%ld", scOK, scLV, (long)scLNeg.scanLocation]);
    scLV = -1.0;
    NSScanner *scLFr = [NSScanner scannerWithString:@"3,14"];
    scLFr.locale = [NSLocale localeWithLocaleIdentifier:@"fr_FR"];
    scOK = [scLFr scanDouble:&scLV];
    p("sc loc fr comma", [NSString stringWithFormat:@"ok=%d val=%.2f loc=%ld", scOK, scLV, (long)scLFr.scanLocation]);
    scLV = -1.0;
    NSScanner *scLEnd = [NSScanner scannerWithString:@"3,14"];
    scLEnd.locale = scLocEN;
    scOK = [scLEnd scanDouble:&scLV];
    p("sc loc en comma", [NSString stringWithFormat:@"ok=%d val=%.2f loc=%ld", scOK, scLV, (long)scLEnd.scanLocation]);
    scLV = -1.0;
    NSScanner *scLGrpE = [NSScanner scannerWithString:@"1,234.56"];
    scLGrpE.locale = scLocEN;
    scOK = [scLGrpE scanDouble:&scLV];
    p("sc loc en grouped", [NSString stringWithFormat:@"ok=%d val=%.2f loc=%ld", scOK, scLV, (long)scLGrpE.scanLocation]);
    scLV = -1.0;
    NSScanner *scLDef = [NSScanner scannerWithString:@"3,14"];
    scOK = [scLDef scanDouble:&scLV];
    p("sc loc none comma", [NSString stringWithFormat:@"ok=%d val=%.2f loc=%ld", scOK, scLV, (long)scLDef.scanLocation]);
    float scLF = -1.0f;
    NSScanner *scLFF = [NSScanner scannerWithString:@"3,14"];
    scLFF.locale = scLocDE;
    scOK = [scLFF scanFloat:&scLF];
    p("sc loc de float", [NSString stringWithFormat:@"ok=%d val=%.2f", scOK, (double)scLF]);
    NSScanner *scLHex = [NSScanner scannerWithString:@"0x1.8p1"];
    scLHex.locale = scLocDE;
    scOK = [scLHex scanHexDouble:&scLV];
    p("sc loc hex de ok", [NSString stringWithFormat:@"ok=%d val=%.2f loc=%ld", scOK, scLV, (long)scLHex.scanLocation]);
    scLV = -1.0;
    NSScanner *scLHexB = [NSScanner scannerWithString:@"3.14"];
    scLHexB.locale = scLocDE;
    scOK = [scLHexB scanHexDouble:&scLV];
    p("sc loc hex dec bad", [NSString stringWithFormat:@"ok=%d val=%.2f loc=%ld", scOK, scLV, (long)scLHexB.scanLocation]);
    int scLI = -1;
    NSScanner *scLInt = [NSScanner scannerWithString:@"3,14"];
    scLInt.locale = scLocDE;
    scOK = [scLInt scanInt:&scLI];
    p("sc loc de int", [NSString stringWithFormat:@"ok=%d val=%d loc=%ld", scOK, scLI, (long)scLInt.scanLocation]);
    NSScanner *scLized = [NSScanner localizedScannerWithString:@"3,14"];
    scLV = -1.0;
    scOK = [scLized scanDouble:&scLV];
    p("sc localized def", [NSString stringWithFormat:@"ok=%d val=%.2f loc=%ld", scOK, scLV, (long)scLized.scanLocation]);

    /* ---------- NSNumberFormatter ---------- */
    NSNumberFormatter *nnfF = [[NSNumberFormatter alloc] init];
    p("nnf default style", [NSString stringWithFormat:@"%ld", (long)nnfF.numberStyle]);
    nnfF.numberStyle = NSNumberFormatterDecimalStyle;
    nnfF.locale = [NSLocale localeWithLocaleIdentifier:@"en_US"];
    p("nnf en dec 1234.5", [nnfF stringFromNumber:@1234.5]);
    nnfF.locale = [NSLocale localeWithLocaleIdentifier:@"de_DE"];
    p("nnf de dec 1234.5", [nnfF stringFromNumber:@1234.5]);
    p("nnf de dec neg", [nnfF stringFromNumber:@(-1234.5)]);
    nnfF.numberStyle = NSNumberFormatterPercentStyle;
    p("nnf de pct 0.25", [nnfF stringFromNumber:@0.25]);
    nnfF.locale = [NSLocale localeWithLocaleIdentifier:@"en_US"];
    p("nnf en pct 0.25", [nnfF stringFromNumber:@0.25]);
    nnfF.numberStyle = NSNumberFormatterScientificStyle;
    p("nnf en sci 1234.5", [nnfF stringFromNumber:@1234.5]);
    nnfF.numberStyle = NSNumberFormatterSpellOutStyle;
    p("nnf en spell 42", [nnfF stringFromNumber:@42]);
    nnfF.numberStyle = NSNumberFormatterCurrencyStyle;
    nnfF.locale = [NSLocale localeWithLocaleIdentifier:@"de_DE"];
    p("nnf de cur 1234.5", [nnfF stringFromNumber:@1234.5]);
    nnfF.locale = [NSLocale localeWithLocaleIdentifier:@"en_US"];
    p("nnf en cur 1234.5", [nnfF stringFromNumber:@1234.5]);

    NSNumberFormatter *nnfP = [[NSNumberFormatter alloc] init];
    nnfP.numberStyle = NSNumberFormatterDecimalStyle;
    nnfP.locale = [NSLocale localeWithLocaleIdentifier:@"de_DE"];
    p("nnf de parse 1.234,5", [nnfP stringFromNumber:[nnfP numberFromString:@"1.234,5"]]);
    nnfP.locale = [NSLocale localeWithLocaleIdentifier:@"en_US"];
    p("nnf en parse 1,234.5", [nnfP stringFromNumber:[nnfP numberFromString:@"1,234.5"]]);
    p("nnf en parse bad", [nnfP numberFromString:@"abc"] ? @"non-nil" : @"nil");
    nnfP.numberStyle = NSNumberFormatterPercentStyle;
    p("nnf en pct parse 25%", [[nnfP numberFromString:@"25%"] stringValue]);
    nnfP.locale = [NSLocale localeWithLocaleIdentifier:@"de_DE"];
    p("nnf de pct parse 25 nb", [nnfP numberFromString:@"25\u00A0%"] ? @"non-nil" : @"nil");

    NSNumberFormatter *nnfS = [[NSNumberFormatter alloc] init];
    nnfS.locale = [NSLocale localeWithLocaleIdentifier:@"en_US"];
    nnfS.format = @"###,###.##";
    p("nnf custom fmt 12345.6", [nnfS stringFromNumber:@12345.6]);
    nnfS.numberStyle = NSNumberFormatterScientificStyle;
    p("nnf style chg output", [nnfS stringFromNumber:@12345.6]);

    NSNumberFormatter *nnfD = [[NSNumberFormatter alloc] init];
    nnfD.locale = [NSLocale localeWithLocaleIdentifier:@"en_US"];
    nnfD.numberStyle = NSNumberFormatterDecimalStyle;
    nnfD.minimumFractionDigits = 2;
    p("nnf minfrac2 7.1", [nnfD stringFromNumber:@7.1]);
    nnfD.maximumFractionDigits = 3;
    p("nnf maxfrac3 7.1234", [nnfD stringFromNumber:@7.1234]);
    nnfD.usesGroupingSeparator = YES;
    nnfD.groupingSize = 2;
    p("nnf group2 12345.6", [nnfD stringFromNumber:@12345.6]);

    NSNumberFormatter *nnfG = [[NSNumberFormatter alloc] init];
    nnfG.numberStyle = NSNumberFormatterDecimalStyle;
    nnfG.locale = [NSLocale localeWithLocaleIdentifier:@"en_US"];
    id nnfObj = nil;
    NSError *nnfErr = nil;
    BOOL nnfOK = [nnfG getObjectValue:&nnfObj forString:@"123.45" range:NULL error:&nnfErr];
    p("nnf getObject good", [NSString stringWithFormat:@"ok=%d val=%@ err=%@", nnfOK, nnfObj, nnfErr ? nnfErr.domain : @"nil"]);
    nnfObj = nil; nnfErr = nil;
    nnfOK = [nnfG getObjectValue:&nnfObj forString:@"zzz" range:NULL error:&nnfErr];
    p("nnf getObject bad", [NSString stringWithFormat:@"ok=%d obj=%@ dom=%@ code=%ld", nnfOK, nnfObj ? @"x" : @"nil", nnfErr.domain, (long)nnfErr.code]);
    p("nnf getObject bad desc", nnfErr.localizedDescription);

    NSNumberFormatter *nnn = [[NSNumberFormatter alloc] init];
    nnn.locale = [NSLocale localeWithLocaleIdentifier:@"en_US"];
    nnn.numberStyle = NSNumberFormatterDecimalStyle;
    p("nnf alloc dec 3.5", [nnn stringFromNumber:@3.5]);

    /* ---------- NSError ---------- */
    NSError *errA = [NSError errorWithDomain:@"TestDomain" code:42 userInfo:nil];
    p("pr basic domain", errA.domain);
    p("pr basic code", [NSString stringWithFormat:@"%ld", (long)errA.code]);
    NSError *errNeg = [NSError errorWithDomain:@"TestDomain" code:-1004 userInfo:nil];
    p("pr negative code", [NSString stringWithFormat:@"%ld", (long)errNeg.code]);
    NSDictionary *richInfo = @{NSLocalizedDescriptionKey: @"Boom happened",
                               NSLocalizedFailureReasonErrorKey: @"the widget broke",
                               NSLocalizedRecoverySuggestionErrorKey: @"replace the widget",
                               @"ExtraKey": @"kept value"};
    NSError *errRich = [NSError errorWithDomain:@"TestDomain" code:17 userInfo:richInfo];
    p("pr localizedDescription present", errRich.localizedDescription);
    p("pr localizedDescription fallback", errA.localizedDescription);
    p("pr description nil-userinfo", [errA description]);
    p("pr userInfo count", [NSString stringWithFormat:@"%lu", (unsigned long)[errRich.userInfo count]]);
    p("pr userInfo extra key", [errRich.userInfo objectForKey:@"ExtraKey"]);
    p("pr failureReason lookup", errRich.localizedFailureReason);
    p("pr recoverySuggestion lookup", errRich.localizedRecoverySuggestion);
    NSError *errInit = [[NSError alloc] initWithDomain:@"TestDomain" code:42 userInfo:nil];
    p("pr init matches basic", [NSString stringWithFormat:@"%d", [errInit isEqual:errA]]);
    p("pr copy identity", [NSString stringWithFormat:@"%d", [errA copy] == errA]);
    p("pr isEqual same", [NSString stringWithFormat:@"%d", [errA isEqual:errA]]);
    NSError *errB = [NSError errorWithDomain:@"TestDomain" code:42 userInfo:nil];
    p("pr isEqual congruent", [NSString stringWithFormat:@"%d", [errA isEqual:errB]]);
    NSError *errC = [NSError errorWithDomain:@"TestDomain" code:43 userInfo:nil];
    p("pr isEqual diff-code", [NSString stringWithFormat:@"%d", [errA isEqual:errC]]);
    NSError *errD = [NSError errorWithDomain:@"OtherDomain" code:42 userInfo:nil];
    p("pr isEqual diff-domain", [NSString stringWithFormat:@"%d", [errA isEqual:errD]]);
    p("pr hash congruent", [NSString stringWithFormat:@"%d", [errA hash] == [errB hash]]);
    NSMutableDictionary *mutInfo = [NSMutableDictionary dictionaryWithCapacity:1];
    [mutInfo setObject:@"mutable" forKey:@"K"];
    NSError *errSnap = [NSError errorWithDomain:@"TestDomain" code:1 userInfo:mutInfo];
    [mutInfo setObject:@"changed" forKey:@"K"];
    p("pr userInfo snapshot", [errSnap.userInfo objectForKey:@"K"]);

    /* ---------- NSNull ---------- */
    p("nz null identity", [NSString stringWithFormat:@"%d", [NSNull null] == [NSNull null]]);
    p("nz null is kCFNull", [NSString stringWithFormat:@"%d", [NSNull null] == (__bridge id)kCFNull]);
    p("nz description", [[NSNull null] description]);
    p("nz copy identity", [NSString stringWithFormat:@"%d", [[NSNull null] copy] == [NSNull null]]);
    p("nz isEqual self", [NSString stringWithFormat:@"%d", [[NSNull null] isEqual:[NSNull null]]]);
    p("nz isEqual string", [NSString stringWithFormat:@"%d", [[NSNull null] isEqual:@"not null"]]);
    p("nz hash congruent", [NSString stringWithFormat:@"%d", [[NSNull null] hash] == [[NSNull null] hash]]);

    /* ---------- NSValue ---------- */
    int cvInt = 5;
    NSValue *cvI = [NSValue valueWithBytes:&cvInt objCType:@encode(int)];
    int cvOut = 0;
    [cvI getValue:&cvOut];
    p("cv int roundtrip", [NSString stringWithFormat:@"%d", cvOut]);
    cvOut = 0;
    [cvI getValue:&cvOut size:sizeof(int)];
    p("cv int getValue:size: full", [NSString stringWithFormat:@"%d", cvOut]);
    p("cv int objCType", [NSString stringWithUTF8String:[cvI objCType]]);
    p("cv int description", [cvI description]);
    BOOL cvBool = YES;
    NSValue *cvB = [NSValue valueWithBytes:&cvBool objCType:@encode(BOOL)];
    BOOL cvBoolOut = NO;
    [cvB getValue:&cvBoolOut];
    p("cv bool roundtrip", [NSString stringWithFormat:@"%d", cvBoolOut]);

    NSRange cvRange = NSMakeRange(3, 7);
    NSValue *cvR = [NSValue valueWithRange:cvRange];
    p("cv range objCType", [NSString stringWithUTF8String:[cvR objCType]]);
    NSRange cvRangeOut = [cvR rangeValue];
    p("cv range roundtrip", [NSString stringWithFormat:@"%ld,%ld", (long)cvRangeOut.location, (long)cvRangeOut.length]);
    NSValue *cvP = [NSValue valueWithPoint:NSMakePoint(2.5, 4.0)];
    NSPoint cvPointOut = [cvP pointValue];
    p("cv point roundtrip", [NSString stringWithFormat:@"%1.1f,%1.1f", cvPointOut.x, cvPointOut.y]);
    NSValue *cvS = [NSValue valueWithSize:NSMakeSize(10.0, 20.0)];
    NSSize cvSizeOut = [cvS sizeValue];
    p("cv size roundtrip", [NSString stringWithFormat:@"%1.1f,%1.1f", cvSizeOut.width, cvSizeOut.height]);
    NSValue *cvRC = [NSValue valueWithRect:NSMakeRect(1.0, 2.0, 3.0, 4.0)];
    NSRect cvRectOut = [cvRC rectValue];
    p("cv rect roundtrip", [NSString stringWithFormat:@"%1.1f,%1.1f,%1.1f,%1.1f", cvRectOut.origin.x, cvRectOut.origin.y, cvRectOut.size.width, cvRectOut.size.height]);

    const void *cvPtr = (const void *)0x1234;
    NSValue *cvPt = [NSValue valueWithPointer:cvPtr];
    p("cv pointer roundtrip", [NSString stringWithFormat:@"%d", [cvPt pointerValue] == cvPtr]);
    NSString *cvObj = @"qux";
    NSValue *cvN = [NSValue valueWithNonretainedObject:cvObj];
    p("cv nonretained roundtrip", [NSString stringWithFormat:@"%d", [cvN nonretainedObjectValue] == cvObj]);

    NSValue *cvI2 = [NSValue valueWithBytes:&cvInt objCType:@encode(int)];
    p("cv isEqual same-content", [NSString stringWithFormat:@"%d", [cvI isEqual:cvI2]]);
    int cvInt3 = 6;
    NSValue *cvI3 = [NSValue valueWithBytes:&cvInt3 objCType:@encode(int)];
    p("cv isEqual diff-bytes", [NSString stringWithFormat:@"%d", [cvI isEqual:cvI3]]);
    char cvChar = 5;
    NSValue *cvC = [NSValue valueWithBytes:&cvChar objCType:@encode(char)];
    p("cv isEqual diff-type", [NSString stringWithFormat:@"%d", [cvI isEqual:cvC]]);
    p("cv isEqual nonvalue", [NSString stringWithFormat:@"%d", [cvI isEqual:@"not a value"]]);
    p("cv hash congruent", [NSString stringWithFormat:@"%d", [cvI hash] == [cvI2 hash]]);
    p("cv hash differs-bytes", [NSString stringWithFormat:@"%d", [cvI hash] != [cvI3 hash]]);
    p("cv isEqualToValue same", [NSString stringWithFormat:@"%d", [cvI isEqualToValue:cvI2]]);
    p("cv copy identity", [NSString stringWithFormat:@"%d", [cvI copy] == cvI]);

    /* ---------- NSMapTable (legacy C API) ---------- */
    NSMapTable *nsT = NSCreateMapTable(NSObjectMapKeyCallBacks,
                                       NSObjectMapValueCallBacks, 0);
    p("ns create count", [NSString stringWithFormat:@"%lu", (unsigned long)NSCountMapTable(nsT)]);
    NSMapInsert(nsT, (__bridge const void *)@"a", (__bridge const void *)@"A");
    NSMapInsert(nsT, (__bridge const void *)@"b", (__bridge const void *)@"B");
    NSMapInsert(nsT, (__bridge const void *)@"c", (__bridge const void *)@"C");
    p("ns count after 3 inserts", [NSString stringWithFormat:@"%lu", (unsigned long)NSCountMapTable(nsT)]);
    p("ns get existing", [NSString stringWithFormat:@"%d", (__bridge id)NSMapGet(nsT, (__bridge const void *)@"b") == @"B"]);
    p("ns get absent", [NSString stringWithFormat:@"%d", NSMapGet(nsT, (__bridge const void *)@"zz") == NULL]);
    void *nsMKey = NULL;
    void *nsMValue = NULL;
    BOOL nsMember = NSMapMember(nsT, (__bridge const void *)@"a", &nsMKey, &nsMValue);
    p("ns member hit", [NSString stringWithFormat:@"%d", nsMember]);
    p("ns member value", [NSString stringWithFormat:@"%d", (__bridge id)nsMValue == @"A"]);
    p("ns member origkey", [NSString stringWithFormat:@"%d", nsMKey == (__bridge const void *)@"a"]);
    p("ns member absent", [NSString stringWithFormat:@"%d", NSMapMember(nsT, (__bridge const void *)@"zz", NULL, NULL)]);
    p("ns insertIfAbsent new", [NSString stringWithFormat:@"%d", NSMapInsertIfAbsent(nsT, (__bridge const void *)@"d", (__bridge const void *)@"D") == NULL]);
    p("ns insertIfAbsent exists", [NSString stringWithFormat:@"%d", NSMapInsertIfAbsent(nsT, (__bridge const void *)@"d", (__bridge const void *)@"X") != NULL]);
    p("ns insertIfAbsent kept value", [NSString stringWithFormat:@"%d", (__bridge id)NSMapGet(nsT, (__bridge const void *)@"d") == @"D"]);
    NSString *nsEqualsB = [NSString stringWithFormat:@"%@", @"b"];
    p("ns get by content-equal key", [NSString stringWithFormat:@"%d", (__bridge id)NSMapGet(nsT, (__bridge const void *)nsEqualsB) == @"B"]);
    NSMapRemove(nsT, (__bridge const void *)@"b");
    p("ns count after remove", [NSString stringWithFormat:@"%lu", (unsigned long)NSCountMapTable(nsT)]);
    p("ns get removed", [NSString stringWithFormat:@"%d", NSMapGet(nsT, (__bridge const void *)@"b") == NULL]);
    NSMapInsert(nsT, (__bridge const void *)@"b", (__bridge const void *)@"B2");
    p("ns reinsert get", [NSString stringWithFormat:@"%d", (__bridge id)NSMapGet(nsT, (__bridge const void *)@"b") == @"B2"]);
    NSMapTable *nsT2 = NSCopyMapTableWithZone(nsT, NULL);
    p("ns copy compare", [NSString stringWithFormat:@"%d", NSCompareMapTables(nsT, nsT2)]);
    NSMapRemove(nsT2, (__bridge const void *)@"c");
    p("ns compare after diverge", [NSString stringWithFormat:@"%d", NSCompareMapTables(nsT, nsT2)]);
    NSArray *nsKeys = NSAllMapTableKeys(nsT);
    p("ns allKeys count", [NSString stringWithFormat:@"%lu", (unsigned long)[nsKeys count]]);
    p("ns allKeys contents", [NSString stringWithFormat:@"%d", [nsKeys containsObject:@"a"] && [nsKeys containsObject:@"b"] && [nsKeys containsObject:@"c"] && [nsKeys containsObject:@"d"] && ![nsKeys containsObject:@"zz"]]);
    NSArray *nsVals = NSAllMapTableValues(nsT);
    p("ns allValues contents", [NSString stringWithFormat:@"%d", [nsVals containsObject:@"A"] && [nsVals containsObject:@"B2"] && [nsVals containsObject:@"C"] && [nsVals containsObject:@"D"]]);
    NSMapEnumerator nsEnum = NSEnumerateMapTable(nsT);
    void *nsK = NULL;
    void *nsV = NULL;
    NSUInteger nsPairs = 0;
    unsigned char nsAllNonNull = 1;
    while (NSNextMapEnumeratorPair(&nsEnum, &nsK, &nsV)) {
        nsPairs++;
        if (nsK == NULL || nsV == NULL) {
            nsAllNonNull = 0;
        }
    }
    p("ns enumerate pairs", [NSString stringWithFormat:@"%lu", (unsigned long)nsPairs]);
    p("ns enumerate nonnull", [NSString stringWithFormat:@"%d", nsAllNonNull]);
    NSResetMapTable(nsT);
    p("ns count after reset", [NSString stringWithFormat:@"%lu", (unsigned long)NSCountMapTable(nsT)]);
    NSMapInsert(nsT, (__bridge const void *)@"x", (__bridge const void *)@"X");
    p("ns insert after reset", [NSString stringWithFormat:@"%d", NSCountMapTable(nsT) == 1 && (__bridge id)NSMapGet(nsT, (__bridge const void *)@"x") == @"X"]);
    NSFreeMapTable(nsT);
    NSMapTable *nsNullT = NSCreateMapTable(NSNonRetainedObjectMapKeyCallBacks,
                                           NSNonRetainedObjectMapValueCallBacks, 0);
    NSMapInsert(nsNullT, (__bridge const void *)@"a", (__bridge const void *)@"A");
    p("ns null get absent", [NSString stringWithFormat:@"%d", NSMapGet(nsNullT, NULL) == NULL]);
    unsigned char nsNullInsertRejected = 0;
    @try {
        NSMapInsert(nsNullT, NULL, (__bridge const void *)@"bad");
    } @catch (NSException *e) {
        nsNullInsertRejected = 1;
    }
    p("ns null insert rejects", [NSString stringWithFormat:@"%d", nsNullInsertRejected]);
    unsigned char nsNullRemoveRejected = 0;
    @try {
        NSMapRemove(nsNullT, NULL);
    } @catch (NSException *e) {
        nsNullRemoveRejected = 1;
    }
    p("ns null remove rejects", [NSString stringWithFormat:@"%d", nsNullRemoveRejected]);
    NSFreeMapTable(nsNullT);
    NSMapTable *nsIntT = NSCreateMapTable(NSIntegerMapKeyCallBacks,
                                          NSIntegerMapValueCallBacks, 0);
    NSMapInsert(nsIntT, (const void *)7, (const void *)8);
    p("ns integer key get", [NSString stringWithFormat:@"%d", NSMapGet(nsIntT, (const void *)7) == (const void *)8]);
    NSFreeMapTable(nsIntT);

    /* ---------- NSDecimal ---------- */
    NSDecimal dm0 = dmv(0, 0, 0);
    NSDecimal dmOne = dmv(1, 0, 0);
    NSDecimal dmTwo = dmv(2, 0, 0);
    NSDecimal dmFive = dmv(5, 0, 0);
    NSDecimal dmFifteen = dmv(15, 0, 0);
    NSDecimal dmPoint5 = dmv(5, -1, 0);
    NSDecimal dmNegPoint5 = dmv(5, -1, 1);
    NSDecimal dm1375 = dmv(1375, -3, 0);
    NSDecimal dmNeg1375 = dmv(1375, -3, 1);
    NSDecimal dm12345 = dmv(12345, 0, 0);
    NSDecimal dm12345d = dmv(12345, -2, 0);
    NSDecimal dmHundred = dmv(100, 0, 0);
    NSDecimal dmNan = dmv(0, 0, 1);
    NSDecimal dmThird = dmv(3, 0, 0);
    NSDecimal dmSeventh = dmv(7, 0, 0);
    NSDecimal dmBigExp = dmv(1, 100, 0);
    NSDecimal dmNegExp = dmv(5, -100, 0);
    NSDecimal dmTiny = dmv(1, -6, 0);

    p("dm str zero", NSDecimalString(&dm0, nil));
    p("dm str one", NSDecimalString(&dmOne, nil));
    p("dm str 100", NSDecimalString(&dmHundred, nil));
    p("dm str 12345", NSDecimalString(&dm12345, nil));
    p("dm str 0.5", NSDecimalString(&dmPoint5, nil));
    p("dm str -0.5", NSDecimalString(&dmNegPoint5, nil));
    p("dm str 1.375", NSDecimalString(&dm1375, nil));
    p("dm str 123.45", NSDecimalString(&dm12345d, nil));
    p("dm str nan", NSDecimalString(&dmNan, nil));

    p("dm cmp 1 vs 2", [NSString stringWithFormat:@"%ld", (long)NSDecimalCompare(&dmOne, &dmTwo)]);
    p("dm cmp 2 vs 2", [NSString stringWithFormat:@"%ld", (long)NSDecimalCompare(&dmTwo, &dmTwo)]);
    p("dm cmp 5 vs 2", [NSString stringWithFormat:@"%ld", (long)NSDecimalCompare(&dmFive, &dmTwo)]);
    p("dm cmp -0.5 vs 0.5", [NSString stringWithFormat:@"%ld", (long)NSDecimalCompare(&dmNegPoint5, &dmPoint5)]);
    p("dm cmp nan vs 1", [NSString stringWithFormat:@"%ld", (long)NSDecimalCompare(&dmNan, &dmOne)]);
    p("dm cmp 1 vs nan", [NSString stringWithFormat:@"%ld", (long)NSDecimalCompare(&dmOne, &dmNan)]);

    NSDecimal dmRes = dmv(0, 0, 0);
    p("dm add 0.5+0.5", dmfmt(&dmRes, NSDecimalAdd(&dmRes, &dmPoint5, &dmPoint5, NSRoundPlain)));
    p("dm sub 1-0.5", dmfmt(&dmRes, NSDecimalSubtract(&dmRes, &dmOne, &dmPoint5, NSRoundPlain)));
    p("dm sub 0.5-(-0.5)", dmfmt(&dmRes, NSDecimalSubtract(&dmRes, &dmPoint5, &dmNegPoint5, NSRoundPlain)));
    p("dm add 1e127+1e-6", dmfmt(&dmRes, NSDecimalAdd(&dmRes, &dmBigExp, &dmTiny, NSRoundPlain)));
    p("dm add nan", dmfmt(&dmRes, NSDecimalAdd(&dmRes, &dmNan, &dmOne, NSRoundPlain)));
    p("dm mul 15*2", dmfmt(&dmRes, NSDecimalMultiply(&dmRes, &dmFifteen, &dmTwo, NSRoundPlain)));
    p("dm mul 0.5*-0.5", dmfmt(&dmRes, NSDecimalMultiply(&dmRes, &dmPoint5, &dmNegPoint5, NSRoundPlain)));
    p("dm div 7/3", dmfmt(&dmRes, NSDecimalDivide(&dmRes, &dmSeventh, &dmThird, NSRoundPlain)));
    p("dm div 1/3 down", dmfmt(&dmRes, NSDecimalDivide(&dmRes, &dmOne, &dmThird, NSRoundDown)));
    p("dm div 1/2", dmfmt(&dmRes, NSDecimalDivide(&dmRes, &dmOne, &dmTwo, NSRoundPlain)));
    p("dm div 1/0", dmfmt(&dmRes, NSDecimalDivide(&dmRes, &dmOne, &dm0, NSRoundPlain)));
    p("dm div 0/3", dmfmt(&dmRes, NSDecimalDivide(&dmRes, &dm0, &dmThird, NSRoundPlain)));

    NSDecimal dmR = dmv(0, 0, 0);
    p("dm round 1.375 plain@0", dmround(&dmR, &dm1375, 0, NSRoundPlain));
    p("dm round 1.375 plain@2", dmround(&dmR, &dm1375, 2, NSRoundPlain));
    p("dm round 1.375 plain@-1", dmround(&dmR, &dm1375, -1, NSRoundPlain));
    p("dm round nan", dmround(&dmR, &dmNan, 0, NSRoundPlain));
    NSDecimal dm15 = dmv(15, -1, 0);
    NSDecimal dm25 = dmv(25, -1, 0);
    NSDecimal dmNeg15 = dmv(15, -1, 1);
    NSDecimal dmNeg25 = dmv(25, -1, 1);
    p("dm round 1.5 plain", dmround(&dmR, &dm15, 0, NSRoundPlain));
    p("dm round 1.5 down", dmround(&dmR, &dm15, 0, NSRoundDown));
    p("dm round 1.5 up", dmround(&dmR, &dm15, 0, NSRoundUp));
    p("dm round 1.5 bankers", dmround(&dmR, &dm15, 0, NSRoundBankers));
    p("dm round 2.5 plain", dmround(&dmR, &dm25, 0, NSRoundPlain));
    p("dm round 2.5 bankers", dmround(&dmR, &dm25, 0, NSRoundBankers));
    p("dm round -1.5 plain", dmround(&dmR, &dmNeg15, 0, NSRoundPlain));
    p("dm round -1.5 down", dmround(&dmR, &dmNeg15, 0, NSRoundDown));
    p("dm round -1.5 up", dmround(&dmR, &dmNeg15, 0, NSRoundUp));
    p("dm round -1.5 bankers", dmround(&dmR, &dmNeg15, 0, NSRoundBankers));
    p("dm round -2.5 bankers", dmround(&dmR, &dmNeg25, 0, NSRoundBankers));

    NSDecimal dmA = dmv(10, 0, 0);
    NSDecimal dmB2 = dmv(5, -1, 0);
    NSCalculationError dmNormErr = NSDecimalNormalize(&dmA, &dmB2, NSRoundPlain);
    p("dm normalize 10,0.5", [NSString stringWithFormat:@"%@|%@ err=%ld",
        NSDecimalString(&dmA, nil), NSDecimalString(&dmB2, nil), (long)dmNormErr]);
    p("dm power 2^0", dmfmt(&dmRes, NSDecimalPower(&dmRes, &dmTwo, 0, NSRoundPlain)));
    p("dm power 2^10", dmfmt(&dmRes, NSDecimalPower(&dmRes, &dmTwo, 10, NSRoundPlain)));
    p("dm power 0^0", dmfmt(&dmRes, NSDecimalPower(&dmRes, &dm0, 0, NSRoundPlain)));
    p("dm power 1.5^2", dmfmt(&dmRes, NSDecimalPower(&dmRes, &dm15, 2, NSRoundPlain)));
    p("dm mul10 0.5*1e3", dmfmt(&dmRes, NSDecimalMultiplyByPowerOf10(&dmRes, &dmPoint5, 3, NSRoundPlain)));
    p("dm mul10 1.375*1e-2", dmfmt(&dmRes, NSDecimalMultiplyByPowerOf10(&dmRes, &dm1375, -2, NSRoundPlain)));
    p("dm mul10 overflow", dmfmt(&dmRes, NSDecimalMultiplyByPowerOf10(&dmRes, &dmBigExp, 30, NSRoundPlain)));
    p("dm mul10 underflow", dmfmt(&dmRes, NSDecimalMultiplyByPowerOf10(&dmRes, &dmNegExp, -100, NSRoundPlain)));

    p("dm isNaN zero", [NSString stringWithFormat:@"%d", NSDecimalIsNotANumber(&dm0)]);
    p("dm isNaN nan", [NSString stringWithFormat:@"%d", NSDecimalIsNotANumber(&dmNan)]);
    NSDecimal dmCopy = dmv(0, 0, 0);
    NSDecimalCopy(&dmCopy, &dm1375);
    p("dm copy", NSDecimalString(&dmCopy, nil));
    NSDecimal dmWide = dmv(0, 0, 0);
    dmWide._mantissa[0] = 7;
    dmWide._length = 8;
    dmWide._isCompact = 0;
    p("dm wide len", [NSString stringWithFormat:@"%u", dmWide._length]);
    NSDecimalCompact(&dmWide);
    p("dm compact len", [NSString stringWithFormat:@"%u", dmWide._length]);
    p("dm compact str", NSDecimalString(&dmWide, nil));
    p("dm compact sign", [NSString stringWithFormat:@"%u", dmWide._isNegative]);

    NSDictionary *dmLdot = [NSDictionary dictionaryWithObjects:(id[]){@".", @""}
                                                       forKeys:(id[]){@"NSDecimalSeparator", @"NSGroupingSeparator"} count:2];
    NSDictionary *dmLcomma = [NSDictionary dictionaryWithObjects:(id[]){@",", @" "}
                                                         forKeys:(id[]){@"NSDecimalSeparator", @"NSGroupingSeparator"} count:2];
    p("dm loc 12345 dot", NSDecimalString(&dm12345, dmLdot));
    p("dm loc 123.45 dot", NSDecimalString(&dm12345d, dmLdot));
    p("dm loc 12345 comma", NSDecimalString(&dm12345, dmLcomma));
    p("dm loc 123.45 comma", NSDecimalString(&dm12345d, dmLcomma));
    p("dm loc 0.5 comma", NSDecimalString(&dmPoint5, dmLcomma));
    NSDecimal dmBigGroup = dmv(1234, 3, 0);
    p("dm loc 1234000 comma", NSDecimalString(&dmBigGroup, dmLcomma));
    NSDecimal dmNeg12345 = dmv(12345, 0, 1);
    p("dm loc -12345 comma", NSDecimalString(&dmNeg12345, dmLcomma));

    NSDecimalNumber *dnZero = [NSDecimalNumber zero];
    NSDecimalNumber *dnOne = [NSDecimalNumber one];
    NSDecimalNumber *dnNan = [NSDecimalNumber notANumber];
    NSDecimalNumber *dnMin = [NSDecimalNumber minimumDecimalNumber];
    NSDecimalNumber *dnMax = [NSDecimalNumber maximumDecimalNumber];
    p("dn zero", [dnZero stringValue]);
    p("dn one", [dnOne stringValue]);
    p("dn nan", [dnNan stringValue]);
    p("dn minimum", [dnMin stringValue]);
    p("dn maximum", [dnMax stringValue]);
    p("dn str 123.45", [[NSDecimalNumber decimalNumberWithString:@"123.45"] stringValue]);
    p("dn str -0.001", [[NSDecimalNumber decimalNumberWithString:@"-0.001"] stringValue]);
    p("dn str 1.5e3", [[NSDecimalNumber decimalNumberWithString:@"1.5e3"] stringValue]);
    p("dn str 0007", [[NSDecimalNumber decimalNumberWithString:@"0007"] stringValue]);
    p("dn str 0", [[NSDecimalNumber decimalNumberWithString:@"0"] stringValue]);
    p("dn str 1e100", [[NSDecimalNumber decimalNumberWithString:@"1e100"] stringValue]);
    p("dn m 12345e-2", [[NSDecimalNumber decimalNumberWithMantissa:12345 exponent:-2 isNegative:NO] stringValue]);
    p("dn m 0e5 neg", [[NSDecimalNumber decimalNumberWithMantissa:0 exponent:5 isNegative:YES] stringValue]);
    p("dn m -7", [[NSDecimalNumber decimalNumberWithMantissa:7 exponent:0 isNegative:YES] stringValue]);
    NSDecimal dnRaw; memset(&dnRaw, 0, sizeof(dnRaw));
    dnRaw._mantissa[0] = 625; dnRaw._length = 1; dnRaw._exponent = -3; dnRaw._isCompact = 1;
    p("dn decimal 625e-3", [[NSDecimalNumber decimalNumberWithDecimal:dnRaw] stringValue]);

    NSDecimalNumber *dnHalf = [NSDecimalNumber decimalNumberWithString:@"0.5"];
    NSDecimalNumber *dnThird = [NSDecimalNumber decimalNumberWithString:@"1"];
    p("dn add 0.5+1", [[dnHalf decimalNumberByAdding:dnThird] stringValue]);
    p("dn sub 0.5-1", [[dnHalf decimalNumberBySubtracting:dnThird] stringValue]);
    p("dn mul 0.5*1", [[dnHalf decimalNumberByMultiplyingBy:dnThird] stringValue]);
    p("dn div 0.5/1", [[dnHalf decimalNumberByDividingBy:dnThird] stringValue]);
    p("dn div 2/3", [[[NSDecimalNumber decimalNumberWithString:@"2"] decimalNumberByDividingBy:[NSDecimalNumber decimalNumberWithString:@"3"]] stringValue]);
    p("dn pow 2^10", [[[NSDecimalNumber decimalNumberWithString:@"2"] decimalNumberByRaisingToPower:10] stringValue]);
    p("dn mul10 0.5*1e3", [[[NSDecimalNumber decimalNumberWithString:@"0.5"] decimalNumberByMultiplyingByPowerOf10:3] stringValue]);

    NSDecimalNumberHandler *dnBankers2 = [[NSDecimalNumberHandler alloc] initWithRoundingMode:NSRoundBankers scale:2 raiseOnExactness:YES raiseOnOverflow:YES raiseOnUnderflow:YES raiseOnDivideByZero:YES];
    p("dn round 1.005 bnk2", [[[NSDecimalNumber decimalNumberWithString:@"1.005"] decimalNumberByRoundingAccordingToBehavior:dnBankers2] stringValue]);
    p("dn round 2.005 bnk2", [[[NSDecimalNumber decimalNumberWithString:@"2.005"] decimalNumberByRoundingAccordingToBehavior:dnBankers2] stringValue]);
    NSDecimalNumberHandler *dnPlain0 = [[NSDecimalNumberHandler alloc] initWithRoundingMode:NSRoundPlain scale:0 raiseOnExactness:YES raiseOnOverflow:YES raiseOnUnderflow:YES raiseOnDivideByZero:YES];
    p("dn round 2.5 plain0", [[[NSDecimalNumber decimalNumberWithString:@"2.5"] decimalNumberByRoundingAccordingToBehavior:dnPlain0] stringValue]);
    p("dn round 3.5 plain0", [[[NSDecimalNumber decimalNumberWithString:@"3.5"] decimalNumberByRoundingAccordingToBehavior:dnPlain0] stringValue]);
    NSDecimalNumberHandler *dnDown1 = [[NSDecimalNumberHandler alloc] initWithRoundingMode:NSRoundDown scale:1 raiseOnExactness:YES raiseOnOverflow:YES raiseOnUnderflow:YES raiseOnDivideByZero:YES];
    p("dn round 1.29 down1", [[[NSDecimalNumber decimalNumberWithString:@"1.29"] decimalNumberByRoundingAccordingToBehavior:dnDown1] stringValue]);
    p("dn round -1.29 down1", [[[NSDecimalNumber decimalNumberWithString:@"-1.29"] decimalNumberByRoundingAccordingToBehavior:dnDown1] stringValue]);
    NSDecimalNumberHandler *dnUp1 = [[NSDecimalNumberHandler alloc] initWithRoundingMode:NSRoundUp scale:1 raiseOnExactness:YES raiseOnOverflow:YES raiseOnUnderflow:YES raiseOnDivideByZero:YES];
    p("dn round 1.29 up1", [[[NSDecimalNumber decimalNumberWithString:@"1.29"] decimalNumberByRoundingAccordingToBehavior:dnUp1] stringValue]);
    p("dn round -1.29 up1", [[[NSDecimalNumber decimalNumberWithString:@"-1.29"] decimalNumberByRoundingAccordingToBehavior:dnUp1] stringValue]);

    NSDecimalNumber *dnX = nil;
    @try { dnX = [[NSDecimalNumber decimalNumberWithString:@"1"] decimalNumberByMultiplyingByPowerOf10:-32768]; p("dn mul10 deep under", [dnX stringValue]); }
    @catch (NSException *e) { p("dn mul10 deep under", [@"EX " stringByAppendingString:[e name]]); }
    @try { dnX = [[NSDecimalNumber decimalNumberWithString:@"1"] decimalNumberByMultiplyingByPowerOf10:32767]; p("dn mul10 deep over", [dnX stringValue]); }
    @catch (NSException *e) { p("dn mul10 deep over", [@"EX " stringByAppendingString:[e name]]); }
    @try { dnX = [[NSDecimalNumber decimalNumberWithString:@"1"] decimalNumberByDividingBy:[NSDecimalNumber zero]]; p("dn div 1/0", [dnX stringValue]); }
    @catch (NSException *e) { p("dn div 1/0", [@"EX " stringByAppendingString:[e name]]); }
    @try { dnX = [[NSDecimalNumber decimalNumberWithString:@"1"] decimalNumberByMultiplyingBy:[NSDecimalNumber notANumber]]; p("dn mul 1*nan", [dnX stringValue]); }
    @catch (NSException *e) { p("dn mul 1*nan", [@"EX " stringByAppendingString:[e name]]); }

    NSDecimalNumber *dnA = [NSDecimalNumber decimalNumberWithString:@"3"];
    NSDecimalNumber *dnB = [NSDecimalNumber decimalNumberWithString:@"4"];
    NSDecimalNumber *dnC = [NSDecimalNumber decimalNumberWithString:@"3.0"];
    p("dn cmp 3 vs 4", [NSString stringWithFormat:@"%ld", (long)[dnA compare:dnB]]);
    p("dn cmp 4 vs 3", [NSString stringWithFormat:@"%ld", (long)[dnB compare:dnA]]);
    p("dn cmp 3 vs 3.0", [NSString stringWithFormat:@"%ld", (long)[dnA compare:dnC]]);
    p("dn cmp 3 vs nsnum 3", [NSString stringWithFormat:@"%ld", (long)[dnA compare:@3]]);
    p("dn double 3.25", [NSString stringWithFormat:@"%g", [[NSDecimalNumber decimalNumberWithString:@"3.25"] doubleValue]]);
    p("dn objCType", [NSString stringWithUTF8String:[dnA objCType]]);
    p("dn desc 123.45", [[NSDecimalNumber decimalNumberWithString:@"123.45"] description]);
    p("dn desc-loc comma", [[NSDecimalNumber decimalNumberWithString:@"123.45"] descriptionWithLocale:@{@"NSDecimalSeparator" : @","}]);
    p("dn default round", [NSString stringWithFormat:@"%ld", (long)[(NSDecimalNumberHandler *)[NSDecimalNumber defaultBehavior] roundingMode]]);
    p("dn default scale", [NSString stringWithFormat:@"%d", (int)[(NSDecimalNumberHandler *)[NSDecimalNumber defaultBehavior] scale]]);
    p("dn class default round", [NSString stringWithFormat:@"%ld", (long)[[NSDecimalNumberHandler defaultDecimalNumberHandler] roundingMode]]);
    p("dn class default scale", [NSString stringWithFormat:@"%d", (int)[[NSDecimalNumberHandler defaultDecimalNumberHandler] scale]]);
    NSDecimalNumberHandler *dnH = [[NSDecimalNumberHandler alloc] initWithRoundingMode:NSRoundUp scale:3 raiseOnExactness:YES raiseOnOverflow:YES raiseOnUnderflow:YES raiseOnDivideByZero:YES];
    p("dn handler round", [NSString stringWithFormat:@"%ld", (long)[dnH roundingMode]]);
    p("dn handler scale", [NSString stringWithFormat:@"%d", (int)[dnH scale]]);
    NSDecimalNumberHandler *dnQuiet = [[NSDecimalNumberHandler alloc] initWithRoundingMode:NSRoundPlain scale:NSDecimalNoScale raiseOnExactness:NO raiseOnOverflow:NO raiseOnUnderflow:NO raiseOnDivideByZero:NO];
    p("dn div 1/0 quiet", [[[NSDecimalNumber decimalNumberWithString:@"1"] decimalNumberByDividingBy:[NSDecimalNumber zero] withBehavior:dnQuiet] stringValue]);
    p("dn mul 1*nan quiet", [[[NSDecimalNumber decimalNumberWithString:@"1"] decimalNumberByMultiplyingBy:[NSDecimalNumber notANumber] withBehavior:dnQuiet] stringValue]);
    p("dn mul10 over quiet", [[[NSDecimalNumber decimalNumberWithString:@"1"] decimalNumberByMultiplyingByPowerOf10:40000 withBehavior:dnQuiet] stringValue]);
    p("dn mul10 under quiet", [[[NSDecimalNumber decimalNumberWithString:@"1"] decimalNumberByMultiplyingByPowerOf10:-40000 withBehavior:dnQuiet] stringValue]);
    NSDecimalNumberHandler *dnScale4 = [NSDecimalNumberHandler decimalNumberHandlerWithRoundingMode:NSRoundPlain scale:4 raiseOnExactness:NO raiseOnOverflow:NO raiseOnUnderflow:NO raiseOnDivideByZero:NO];
    p("dn div 1/3 scale4", [[[NSDecimalNumber decimalNumberWithString:@"1"] decimalNumberByDividingBy:[NSDecimalNumber decimalNumberWithString:@"3"] withBehavior:dnScale4] stringValue]);
    p("dn pow 2^200 quiet", [[[NSDecimalNumber decimalNumberWithString:@"2"] decimalNumberByRaisingToPower:200 withBehavior:dnQuiet] stringValue]);

    /* ---------- nn: NSNumber ---------- */
    p("nn char 'a'", nnInfo([NSNumber numberWithChar:'a']));
    p("nn uchar 200", nnInfo([NSNumber numberWithUnsignedChar:200]));
    p("nn short -5", nnInfo([NSNumber numberWithShort:-5]));
    p("nn ushort 70000", nnInfo([NSNumber numberWithUnsignedShort:70000]));
    p("nn int 42", nnInfo([NSNumber numberWithInt:42]));
    p("nn int -42", nnInfo([NSNumber numberWithInt:-42]));
    p("nn uint 4294967295", nnInfo([NSNumber numberWithUnsignedInt:4294967295U]));
    p("nn long 7", nnInfo([NSNumber numberWithLong:7]));
    p("nn ulong 7", nnInfo([NSNumber numberWithUnsignedLong:7]));
    p("nn llong min", nnInfo([NSNumber numberWithLongLong:LLONG_MIN]));
    p("nn llong max", nnInfo([NSNumber numberWithLongLong:LLONG_MAX]));
    /* Values past INT64_MAX are not probed: NSNumber here is CF-backed, and
     * CFNumber has only signed storage, so Apple's unsigned-'Q' NSNumber (which
     * Foundation fabricates on top of CF) has no port-side equivalent. In-range
     * unsigned construction is covered above (nn ulong 7, nn uinteger 5, ...),
     * as is the wrapped signed read-back (nn ullong llong). */
    p("nn float 3.25", nnInfo([NSNumber numberWithFloat:3.25f]));
    p("nn float 0.5", nnInfo([NSNumber numberWithFloat:0.5f]));
    p("nn float 16777216", nnInfo([NSNumber numberWithFloat:16777216.0f]));
    p("nn double 3.25", nnInfo([NSNumber numberWithDouble:3.25]));
    p("nn double 0.1", nnInfo([NSNumber numberWithDouble:0.1]));
    p("nn double 1/3", nnInfo([NSNumber numberWithDouble:1.0 / 3.0]));
    p("nn double 2^53", nnInfo([NSNumber numberWithDouble:9007199254740992.0]));
    p("nn double 1e-7", nnInfo([NSNumber numberWithDouble:1e-7]));
    p("nn double 1e100", nnInfo([NSNumber numberWithDouble:1e100]));
    p("nn double 1e18+1", nnInfo([NSNumber numberWithDouble:1000000000000000100.0]));
    p("nn bool YES", nnInfo([NSNumber numberWithBool:YES]));
    p("nn bool NO", nnInfo([NSNumber numberWithBool:NO]));
    p("nn integer 5", nnInfo([NSNumber numberWithInteger:5]));
    p("nn uinteger 5", nnInfo([NSNumber numberWithUnsignedInteger:5]));
    p("nn nan", nnInfo([NSNumber numberWithDouble:NAN]));
    p("nn inf", nnInfo([NSNumber numberWithDouble:INFINITY]));
    p("nn -inf", nnInfo([NSNumber numberWithDouble:-INFINITY]));

    p("nn int42 double", [NSString stringWithFormat:@"%g", [[NSNumber numberWithInt:42] doubleValue]]);
    p("nn int42 float", [NSString stringWithFormat:@"%g", [[NSNumber numberWithInt:42] floatValue]]);
    p("nn dbl3.25 int", [NSString stringWithFormat:@"%d", [[NSNumber numberWithDouble:3.25] intValue]]);
    p("nn dbl3.25 llong", [NSString stringWithFormat:@"%lld", [[NSNumber numberWithDouble:3.25] longLongValue]]);
    p("nn dbl3.25 bool", [NSString stringWithFormat:@"%d", [[NSNumber numberWithDouble:3.25] boolValue]]);
    p("nn dbl0 bool", [NSString stringWithFormat:@"%d", [[NSNumber numberWithDouble:0.0] boolValue]]);
    p("nn int0 bool", [NSString stringWithFormat:@"%d", [[NSNumber numberWithInt:0] boolValue]]);
    p("nn YES int", [NSString stringWithFormat:@"%d", [[NSNumber numberWithBool:YES] intValue]]);
    p("nn YES dbl", [NSString stringWithFormat:@"%g", [[NSNumber numberWithBool:YES] doubleValue]]);
    p("nn ullong llong", [NSString stringWithFormat:@"%lld", [[NSNumber numberWithUnsignedLongLong:ULLONG_MAX] longLongValue]]);

    p("nn cmp 3 vs 4", [NSString stringWithFormat:@"%ld", (long)[@3 compare:@4]]);
    p("nn cmp 4 vs 3", [NSString stringWithFormat:@"%ld", (long)[@4 compare:@3]]);
    p("nn cmp 3 vs 3.0", [NSString stringWithFormat:@"%ld", (long)[@3 compare:@3.0]]);
    p("nn cmp 0.5 vs 0.5f", [NSString stringWithFormat:@"%ld", (long)[[NSNumber numberWithDouble:0.5] compare:[NSNumber numberWithFloat:0.5f]]]);
    p("nn eq int3 dbl3.0", [NSString stringWithFormat:@"%d", [@3 isEqual:@3.0]]);
    p("nn eq YES @1", [NSString stringWithFormat:@"%d", [@YES isEqual:@1]]);
    p("nn eq YES NO", [NSString stringWithFormat:@"%d", [@YES isEqual:@NO]]);
    p("nn eq nsnum str", [NSString stringWithFormat:@"%d", [@3 isEqual:@"3"]]);
    p("nn iseq 4 vs 4.0", [NSString stringWithFormat:@"%d", [@4 isEqualToNumber:@4.0]]);
    p("nn iseq 4 vs 5", [NSString stringWithFormat:@"%d", [@4 isEqualToNumber:@5]]);
    p("nn cmp ullmax vs ullmax", [NSString stringWithFormat:@"%ld", (long)[[NSNumber numberWithUnsignedLongLong:ULLONG_MAX] compare:[NSNumber numberWithUnsignedLongLong:ULLONG_MAX]]]);
    p("nn copy identity", [NSString stringWithFormat:@"%d", [@42 copy] == @42]);
    p("nn alloc init", nnInfo([[NSNumber alloc] init]));
    p("nn alloc initInt 7", nnInfo([[NSNumber alloc] initWithInt:7]));
    p("nn alloc initDbl 2.5", nnInfo([[NSNumber alloc] initWithDouble:2.5]));
    p("nn desc-loc", [[NSNumber numberWithInt:42] descriptionWithLocale:@{@"NSDecimalSeparator" : @","}]);

    /* ---- NSError (extend the pr section above: constants, accessor corners,
     * class identity, POSIX message, hash value, recovery plumbing) ---- */
    p("ne cocoa domain", [NSString stringWithFormat:@"%@", NSCocoaErrorDomain]);
    p("ne posix domain", [NSString stringWithFormat:@"%@", NSPOSIXErrorDomain]);
    p("ne osstatus domain", [NSString stringWithFormat:@"%@", NSOSStatusErrorDomain]);
    p("ne mach domain", [NSString stringWithFormat:@"%@", NSMachErrorDomain]);
    p("ne key options", [NSString stringWithFormat:@"%@", NSLocalizedRecoveryOptionsErrorKey]);
    p("ne key attempter", [NSString stringWithFormat:@"%@", NSRecoveryAttempterErrorKey]);
    p("ne key anchor", [NSString stringWithFormat:@"%@", NSHelpAnchorErrorKey]);
    p("ne key underlying", [NSString stringWithFormat:@"%@", NSUnderlyingErrorKey]);

    NSError *neRaw = [NSError errorWithDomain:NSCocoaErrorDomain code:42 userInfo:nil];
    p("ne raw class", [NSString stringWithFormat:@"%s", object_getClassName(neRaw)]);
    p("ne raw failure", [neRaw localizedFailureReason] == nil ? @"nil" : @"non-nil");
    /* Not gated: the hash VALUE differs (Apple's derives from its NSString
     * hash; the port's is code^len<<8 until NSString overrides -hash). The
     * invariants hash-congruence and hash-diff are probed below. */

    NSError *neDict = [NSError errorWithDomain:@"com.example" code:7 userInfo:@{
        NSLocalizedDescriptionKey : @"Boom",
        NSLocalizedFailureReasonErrorKey : @"reason",
        NSLocalizedRecoverySuggestionErrorKey : @"suggestion",
        NSLocalizedRecoveryOptionsErrorKey : @[ @"OK", @"Cancel" ],
        NSRecoveryAttempterErrorKey : @"attempter",
        NSHelpAnchorErrorKey : @"help",
        @"ExtraKey" : @[ @1, @"two" ],
    }];
    p("ne dict options", [NSString stringWithFormat:@"%@", [neDict localizedRecoveryOptions]]);
    p("ne dict attempter", [NSString stringWithFormat:@"%@", [neDict recoveryAttempter]]);
    p("ne dict anchor", [neDict helpAnchor]);
    /* Not gated: Apple's UserInfo= rendering iterates the dictionary in CF
     * bucket order (not sorted), which is not byte-stable across processes;
     * only the single-key form below can be pinned. */

    NSError *neUnderlying = [NSError errorWithDomain:@"under.example" code:1 userInfo:nil];
    NSError *neParent = [NSError errorWithDomain:@"parent.example" code:2
                                        userInfo:@{NSUnderlyingErrorKey : neUnderlying}];
    p("ne underlying", [neParent.userInfo[NSUnderlyingErrorKey] description]);
    /* Not gated: Apple prefixes nested object values in UserInfo with a live
     * "0x%p" pointer, so a multi-error -description is unstable across runs. */

    NSError *neNumDesc = [NSError errorWithDomain:NSCocoaErrorDomain code:1
                                         userInfo:@{NSLocalizedDescriptionKey : @42}];
    p("ne numdesc", [NSString stringWithFormat:@"%@", [neNumDesc localizedDescription]]);

    NSError *nePosix = [NSError errorWithDomain:NSPOSIXErrorDomain code:2 userInfo:nil];
    p("ne posix desc", [nePosix localizedDescription]);

    p("ne onedesc", [NSError errorWithDomain:@"single.example" code:6
                                    userInfo:@{NSLocalizedDescriptionKey : @"One"}].description);

    p("ne eq diffUser", [[NSError errorWithDomain:NSCocoaErrorDomain code:42 userInfo:@{@"a" : @1}] isEqual:neRaw] ? @"1" : @"0");
    p("ne eq nsnum", [neRaw isEqual:@42] ? @"1" : @"0");
    p("ne eq nil", [neRaw isEqual:nil] ? @"1" : @"0");
    p("ne eq underlying-vs-raw", [neUnderlying isEqual:neParent] ? @"1" : @"0");
    p("ne hash diff", [[NSError errorWithDomain:NSCocoaErrorDomain code:1 userInfo:nil] hash] != [neRaw hash] ? @"1" : @"0");
    p("ne copy diffobj", [neDict copy] != neDict ? @"1" : @"0");
    p("ne copy equal", [[neDict copy] isEqual:neDict] ? @"1" : @"0");
    p("ne copy desc", [[[neDict copy] description] isEqualToString:[neDict description]] ? @"1" : @"0");

    NSMutableDictionary *neMut = [NSMutableDictionary dictionary];
    [neMut setObject:@"A" forKey:@"k"];
    NSError *neCopied = [NSError errorWithDomain:NSCocoaErrorDomain code:5 userInfo:neMut];
    [neMut setObject:@"B" forKey:@"k"];
    p("ne user copy", [neCopied.userInfo objectForKey:@"k"]);
    p("ne user class", [NSString stringWithFormat:@"%s", object_getClassName(neCopied.userInfo)]);

    p("ne emptyuser desc", [NSError errorWithDomain:@"empty.example" code:3 userInfo:@{}].description);
    NSError *neNilSeq = [NSError errorWithDomain:@"nilseq.example" code:4 userInfo:nil];
    p("ne nilseq userInfo", [neNilSeq userInfo] != nil ? @"non-nil" : @"nil");
    p("ne nilseq desc", [neNilSeq localizedDescription]);

    /* ---- NSException ---- */
    p("ex cname generic", NSGenericException);
    p("ex cname range", NSRangeException);
    p("ex cname invalarg", NSInvalidArgumentException);
    p("ex cname internal", NSInternalInconsistencyException);
    p("ex cname malloc", NSMallocException);
    p("ex cname notavail", NSObjectNotAvailableException);
    p("ex cname destinv", NSDestinationInvalidException);
    p("ex cname invarch", NSInvalidArchiveOperationException);
    p("ex cname invunarch", NSInvalidUnarchiveOperationException);

    NSDictionary *exUI = @{@"key" : @"val"};
    NSException *exE = [NSException exceptionWithName:NSRangeException
                                               reason:@"index 5 beyond bounds"
                                             userInfo:exUI];
    p("ex name", [exE name]);
    p("ex reason", [exE reason]);
    p("ex userinfo val", [exE.userInfo objectForKey:@"key"]);
    p("ex userinfo same", [exE userInfo] == exUI ? @"1" : @"0");
    p("ex desc", [exE description]);

    NSException *exNil = [NSException exceptionWithName:NSInternalInconsistencyException
                                                 reason:@"nil thing"
                                               userInfo:nil];
    p("ex nil userinfo", [exNil userInfo] != nil ? @"non-nil" : @"nil");
    p("ex nil desc", [exNil description]);

    @try {
        [NSException raise:NSInvalidArgumentException format:@"bad arg %d and %@", 42, @"foo"];
    } @catch (NSException *e) {
        p("ex raise name", [NSString stringWithFormat:@"%@", [e name]]);
        p("ex raise reason", [e reason]);
        p("ex raise desc", [e description]);
        p("ex raise uinfo", [e userInfo] != nil ? @"non-nil" : @"nil");
        p("ex raise stack addrs", [[e callStackReturnAddresses] count] > 0 ? @"1" : @"0");
        p("ex raise stack syms", [[e callStackSymbols] count] > 0 ? @"1" : @"0");
    }

    p("ex callstack addrs", [[exE callStackReturnAddresses] count] > 0 ? @"1" : @"0");
    p("ex callstack syms", [[exE callStackSymbols] count] > 0 ? @"1" : @"0");

    NSSetUncaughtExceptionHandler(exHandler);
    p("ex handler set/get", NSGetUncaughtExceptionHandler() == exHandler ? @"1" : @"0");
    NSSetUncaughtExceptionHandler(NULL);
    p("ex handler reset/get", NSGetUncaughtExceptionHandler() == NULL ? @"1" : @"0");

    p("ex isEqual self", [exE isEqual:exE] ? @"1" : @"0");
    p("ex isEqual samecontent", [exE isEqual:[NSException exceptionWithName:NSRangeException
                                                                    reason:@"index 5 beyond bounds"
                                                                  userInfo:exUI]] ? @"1" : @"0");
    p("ex isEqual diffUser", [exE isEqual:[NSException exceptionWithName:NSRangeException
                                                                 reason:@"index 5 beyond bounds"
                                                               userInfo:@{@"other" : @2}]] ? @"1" : @"0");
    p("ex hash equal", [exE hash] == [[NSException exceptionWithName:NSRangeException
                                                              reason:@"index 5 beyond bounds"
                                                            userInfo:exUI] hash] ? @"1" : @"0");
    p("ex copy identity", [exE copy] != exE ? @"1" : @"0");
    p("ex copy desc equal", [[[exE copy] description] isEqualToString:[exE description]] ? @"1" : @"0");

    NSMutableDictionary *exMut = [NSMutableDictionary dictionary];
    [exMut setObject:@"v1" forKey:@"k"];
    NSException *exSnap = [NSException exceptionWithName:NSGenericException reason:@"r" userInfo:exMut];
    [exMut setObject:@"v2" forKey:@"k"];
    p("ex userinfo snap", [exSnap.userInfo objectForKey:@"k"]);

    /* ---- NSCharacterSet (thin CFCharacterSet bridge) ---- */
    NSCharacterSet *csWs = [NSCharacterSet whitespaceCharacterSet];
    p("cs ws sp", csMember(csWs, ' '));
    p("cs ws tab", csMember(csWs, '\t'));
    p("cs ws nl", csMember(csWs, '\n'));
    p("cs ws cr", csMember(csWs, '\r'));
    p("cs ws vtab", csMember(csWs, '\v'));
    p("cs ws nbsp", csMember(csWs, 0x00a0));
    p("cs ws zb", csMember(csWs, 0x200b));
    p("cs ws ls2028", csMember(csWs, 0x2028));
    p("cs ws ps2029", csMember(csWs, 0x2029));

    NSCharacterSet *csWsnl = [NSCharacterSet whitespaceAndNewlineCharacterSet];
    p("cs wsnl sp", csMember(csWsnl, ' '));
    p("cs wsnl nl", csMember(csWsnl, '\n'));
    p("cs wsnl cr", csMember(csWsnl, '\r'));

    NSCharacterSet *csAlnum = [NSCharacterSet alphanumericCharacterSet];
    p("cs alnum a", csMember(csAlnum, 'a'));
    p("cs alnum A", csMember(csAlnum, 'A'));
    p("cs alnum 5", csMember(csAlnum, '5'));
    p("cs alnum !", csMember(csAlnum, '!'));
    p("cs alnum sp", csMember(csAlnum, ' '));

    NSCharacterSet *csDigit = [NSCharacterSet decimalDigitCharacterSet];
    p("cs digit 0", csMember(csDigit, '0'));
    p("cs digit 9", csMember(csDigit, '9'));
    p("cs digit a", csMember(csDigit, 'a'));
    p("cs digit arabic0", csMember(csDigit, 0x0660));

    NSCharacterSet *csLetter = [NSCharacterSet letterCharacterSet];
    p("cs letter a", csMember(csLetter, 'a'));
    p("cs letter A", csMember(csLetter, 'A'));
    p("cs letter 1", csMember(csLetter, '1'));
    p("cs letter eacute", csMember(csLetter, 0x00e9));
    p("cs letter sz", csMember(csLetter, 0x00df));

    NSCharacterSet *csLower = [NSCharacterSet lowercaseLetterCharacterSet];
    p("cs lower a", csMember(csLower, 'a'));
    p("cs lower A", csMember(csLower, 'A'));
    p("cs lower 1", csMember(csLower, '1'));
    p("cs lower eacute", csMember(csLower, 0x00e9));

    NSCharacterSet *csUpper = [NSCharacterSet uppercaseLetterCharacterSet];
    p("cs upper a", csMember(csUpper, 'a'));
    p("cs upper A", csMember(csUpper, 'A'));
    p("cs upper 1", csMember(csUpper, '1'));
    p("cs upper eacute", csMember(csUpper, 0x00e9));

    NSCharacterSet *csPunct = [NSCharacterSet punctuationCharacterSet];
    p("cs punct comma", csMember(csPunct, ','));
    p("cs punct dot", csMember(csPunct, '.'));
    p("cs punct bang", csMember(csPunct, '!'));
    p("cs punct sp", csMember(csPunct, ' '));
    p("cs punct a", csMember(csPunct, 'a'));

    NSCharacterSet *csCtrl = [NSCharacterSet controlCharacterSet];
    p("cs ctrl tab", csMember(csCtrl, '\t'));
    p("cs ctrl nl", csMember(csCtrl, '\n'));
    p("cs ctrl cr", csMember(csCtrl, '\r'));
    p("cs ctrl sp", csMember(csCtrl, ' '));
    p("cs ctrl a", csMember(csCtrl, 'a'));

    NSCharacterSet *csNl = [NSCharacterSet newlineCharacterSet];
    p("cs nl nl", csMember(csNl, '\n'));
    p("cs nl cr", csMember(csNl, '\r'));
    p("cs nl ls2028", csMember(csNl, 0x2028));
    p("cs nl ps2029", csMember(csNl, 0x2029));
    p("cs nl sp", csMember(csNl, ' '));

    NSCharacterSet *csStr = [NSCharacterSet characterSetWithCharactersInString:@"ab"];
    p("cs str a", csMember(csStr, 'a'));
    p("cs str b", csMember(csStr, 'b'));
    p("cs str c", csMember(csStr, 'c'));

    NSCharacterSet *csRange = [NSCharacterSet characterSetWithRange:NSMakeRange('A', 26)];
    p("cs range A", csMember(csRange, 'A'));
    p("cs range Z", csMember(csRange, 'Z'));
    p("cs range bracket", csMember(csRange, '['));
    p("cs range a", csMember(csRange, 'a'));

    NSCharacterSet *csInv = [csWs invertedSet];
    p("cs inv sp", csMember(csInv, ' '));
    p("cs inv a", csMember(csInv, 'a'));
    p("cs inv nl", csMember(csInv, '\n'));

    p("cs ws class", [NSString stringWithFormat:@"%s", object_getClassName(csWs)]);
    p("cs range class", [NSString stringWithFormat:@"%s", object_getClassName(csRange)]);
    p("cs copy identity", [csWs copy] != csWs ? @"1" : @"0");
    p("cs eq same", [csWs isEqual:csWs] ? @"1" : @"0");
    p("cs eq fresh ws", [csWs isEqual:[NSCharacterSet whitespaceCharacterSet]] ? @"1" : @"0");

    NSMutableCharacterSet *mcs = [NSMutableCharacterSet characterSetWithRange:NSMakeRange('A', 26)];
    p("cs m class", [NSString stringWithFormat:@"%s", object_getClassName(mcs)]);
    p("cs m A", csMember(mcs, 'A'));
    p("cs m a", csMember(mcs, 'a'));
    [mcs addCharactersInString:@"xyz"];
    p("cs m addstr x", csMember(mcs, 'x'));
    [mcs addCharactersInRange:NSMakeRange('0', 10)];
    p("cs m addrange 5", csMember(mcs, '5'));
    [mcs removeCharactersInRange:NSMakeRange('A', 26)];
    p("cs m rmrange A", csMember(mcs, 'A'));
    [mcs removeCharactersInString:@"xyz"];
    p("cs m rmstr x", csMember(mcs, 'x'));
    [mcs invert];
    p("cs m invert A", csMember(mcs, 'A'));
    p("cs m invert 5", csMember(mcs, '5'));
    p("cs m invert sp", csMember(mcs, ' '));
    NSCharacterSet *mcsCopy = [mcs copy];
    p("cs m copy A", csMember(mcsCopy, 'A'));

    /* ---- NSString: class factories + pinned contract on the CF bridge ---- */
    unichar stChars[2] = { 'H', 'i' };
    p("st withchars", [NSString stringWithCharacters:stChars length:2]);
    p("st withutf8", [NSString stringWithUTF8String:"caf\xC3\xA9"]);
    p("st withformat obj", [NSString stringWithFormat:@"%@-%@", @"a", @42]);

    const char *stUtf8 = [@"café" UTF8String];
    p("st utf8 bytes", [NSString stringWithFormat:@"%zu", strlen(stUtf8)]);
    p("st utf8 roundtrip", [[NSString stringWithUTF8String:stUtf8] isEqualToString:@"café"] ? @"1" : @"0");

    NSData *stData = [@"AB" dataUsingEncoding:NSUTF8StringEncoding];
    p("st data len", [NSString stringWithFormat:@"%lu", (unsigned long)[stData length]]);
    const unsigned char *stDataBytes = [stData bytes];
    p("st data b0", [NSString stringWithFormat:@"%02x", stDataBytes[0]]);
    p("st data b1", [NSString stringWithFormat:@"%02x", stDataBytes[1]]);

    p("st init bytes ok", [[[NSString alloc] initWithBytes:"Hi" length:2
                                                 encoding:NSUTF8StringEncoding] isEqualToString:@"Hi"] ? @"1" : @"0");
    const unsigned char stBad[2] = { 0xC3, 0x28 };
    p("st init bytes bad", [[[NSString alloc] initWithBytes:stBad length:2
                                                   encoding:NSUTF8StringEncoding] length] > 0 ? @"non-nil" : @"nil");

    p("st eq nil", [@"abc" isEqualToString:nil] ? @"1" : @"0");
    p("st prefix empty", [@"abc" hasPrefix:@""] ? @"1" : @"0");
    p("st suffix empty", [@"abc" hasSuffix:@""] ? @"1" : @"0");

    long stCi = [@"Hello" caseInsensitiveCompare:@"hello"];
    p("st caseIns", [NSString stringWithFormat:@"%ld", stCi]);
    long stCmp = [@"ABC" compare:@"abc"];
    p("st compare", [NSString stringWithFormat:@"%ld", stCmp]);
    long stCmpLit = [@"ABC" compare:@"abc" options:NSLiteralSearch];
    p("st compare literal", [NSString stringWithFormat:@"%ld", stCmpLit]);
    long stCmpCI = [@"ABC" compare:@"abc" options:NSCaseInsensitiveSearch];
    p("st compare CI", [NSString stringWithFormat:@"%ld", stCmpCI]);

    p("st lowercase I", [@"I É" lowercaseString]);
    p("st uppercase eacute", [@"é" uppercaseString]);
    p("st uppercase sz", [@"ß" uppercaseString]);
    p("st lowercase sz", [@"ß" lowercaseString]);

    NSArray *stParts = [@"a,b,," componentsSeparatedByString:@","];
    p("st parts count", [NSString stringWithFormat:@"%lu", (unsigned long)[stParts count]]);
    p("st parts join", joinWith(stParts, @"|"));
    p("st parts emptysep", joinWith([@"ab" componentsSeparatedByString:@""], @"|"));

    @try {
        [@"abc" substringFromIndex:9];
    } @catch (id e) {
        p("st subFrom range", [NSString stringWithFormat:@"%@", [e name]]);
    }
    @try {
        [@"abc" substringToIndex:9];
    } @catch (id e) {
        p("st subTo range", [NSString stringWithFormat:@"%@", [e name]]);
    }
    @try {
        [@"abc" stringByReplacingCharactersInRange:NSMakeRange(1, 9) withString:@"x"];
    } @catch (id e) {
        p("st repl range", [NSString stringWithFormat:@"%@", [e name]]);
    }
    @try {
        [@"abc" hasPrefix:nil];
    } @catch (id e) {
        p("st hasPrefix nil", [NSString stringWithFormat:@"%@", [e name]]);
    }
    @try {
        [@"a,b" componentsSeparatedByString:nil];
    } @catch (id e) {
        p("st comps sep nil", [NSString stringWithFormat:@"%@", [e name]]);
    }

    p("st percent add", [@"a b&c/é" stringByAddingPercentEscapesUsingEncoding:NSUTF8StringEncoding]);
    p("st percent rep", [@"a%20b%2Fc%C3%A9" stringByReplacingPercentEscapesUsingEncoding:NSUTF8StringEncoding]);
    p("st percent rep bad", [@"%zz" stringByReplacingPercentEscapesUsingEncoding:NSUTF8StringEncoding]);

    NSMutableString *mst = [NSMutableString stringWithCapacity:0];
    p("st m cap0", [mst length] == 0 ? @"0" : @"?");
    [mst appendString:@"aXbXc"];
    NSUInteger stReplCount = [mst replaceOccurrencesOfString:@"X" withString:@"-"
                                                     options:0 range:NSMakeRange(0, [mst length])];
    p("st m replace count", [NSString stringWithFormat:@"%lu = %@",
                             (unsigned long)stReplCount, mst]);
    @try {
        NSMutableString *mst2 = [NSMutableString string];
        [mst2 insertString:@"X" atIndex:99];
    } @catch (id e) {
        p("st m insert range", [NSString stringWithFormat:@"%@", [e name]]);
    }

    /* ---------- NSArray contract bundle (CFArray bridge) ---------- */
    NSArray *ae = [NSArray array];
    p("ar factory empty", ae.count == 0 ? @"0" : @"?");
    p("ar empty eq empty", [ae isEqualToArray:[NSArray array]] ? @"1" : @"0");
    p("ar empty eq nonempty", [ae isEqualToArray:a] ? @"1" : @"0");
    NSArray *aq = [NSArray arrayWithObjects:(id[]){@"p", @"q", @"r"} count:3];
    p("ar withObjects", plainJoin(aq, @"|"));
    NSArray *acopy = [NSArray arrayWithArray:a];
    p("ar withArray eq", [acopy isEqualToArray:a] ? @"1" : @"0");
    /* NOT ungated: `arrayWithArray` object identity flips in this env — the
     * port's _CFRuntimeBridgeClasses constructor makes Apple's own bridged
     * +arrayWithArray: hand back the identical instance, so == differs from a
     * plain Apple process though no port code is involved. Equality above pins
     * the contract; mutable-copy identity and copy identity probes exercise the
     * port paths. */
    p("ar alloc init", [[[NSArray alloc] init] count] == 0 ? @"0" : @"?");
    p("ar isEqual nil", [a isEqual:nil] ? @"1" : @"0");
    p("ar isEqual string", [a isEqual:@"z,a,m"] ? @"1" : @"0");
    p("ar isEqual copy", [acopy isEqual:a] ? @"1" : @"0");
    p("ar hash equal", [a hash] == [acopy hash] ? @"1" : @"0");
    p("ar copy identity", [a copy] == a ? @"1" : @"0");
    p("ar mutableCopy identity", [a mutableCopy] == a ? @"0" : @"1");
    p("ar mutableCopy eq", [[a mutableCopy] isEqualToArray:a] ? @"1" : @"0");
    p("ar subscript", a[1]);
    @try {
        [a objectAtIndex:9];
    } @catch (id e) {
        p("ar objectAt bounds", [NSString stringWithFormat:@"%@", [e name]]);
    }
    @try {
        id x = a[9];
        (void)x;
    } @catch (id e) {
        p("ar subscript bounds", [NSString stringWithFormat:@"%@", [e name]]);
    }
    p("ar contains nil", [a containsObject:nil] ? @"1" : @"0");
    NSMutableArray *am = [NSMutableArray arrayWithCapacity:2];
    p("ar m cap count", [am count] == 0 ? @"0" : @"?");
    p("ar m alloc init", [[[NSMutableArray alloc] init] count] == 0 ? @"0" : @"?");
    [am addObjectsFromArray:a];
    p("ar m addFromArray", plainJoin(am, @","));
    @try {
        [am addObject:nil];
    } @catch (id e) {
        p("ar m add nil", [NSString stringWithFormat:@"%@", [e name]]);
    }

    /* ---------- NSSet / NSMutableSet / NSCountedSet contract bundle ---------- */
    NSSet *sbase = [NSSet setWithObjects:@"x", @"y", @"m", nil];
    p("set alloc init", [[[NSSet alloc] init] count] == 0 ? @"0" : @"?");
    p("set object dedup", [[NSSet setWithObject:@"x"] containsObject:@"x"] ? @"1" : @"0");
    p("set withSet eq", [[NSSet setWithSet:sbase] isEqualToSet:sbase] ? @"1" : @"0");
    NSArray *setArr = [NSArray arrayWithObjects:(id[]){@"a", @"a", @"b"} count:3];
    NSSet *setFromArr = [[NSSet alloc] initWithArray:setArr];
    p("set fromArray", [NSString stringWithFormat:@"%lu|%@", (unsigned long)[setFromArr count], sortedObjects(setFromArr)]);
    p("set anyObject present", [sbase anyObject] != nil ? @"1" : @"0");
    p("set allObjects count", [NSString stringWithFormat:@"%lu", (unsigned long)[[sbase allObjects] count]]);
    p("set allObjects sorted", [sbase allObjects] == nil ? @"?" : sortedJoin([sbase allObjects]));
    NSSet *setY = [NSSet setWithObjects:@"y", @"z", nil];
    p("set intersects y", [sbase intersectsSet:setY] ? @"1" : @"0");
    p("set intersects no", [sbase intersectsSet:[NSSet setWithObject:@"q"]] ? @"1" : @"0");
    p("set intersects empty", [sbase intersectsSet:[NSSet set]] ? @"1" : @"0");
    p("set isEqual content", [[[NSSet alloc] initWithSet:sbase] isEqualToSet:sbase] ? @"1" : @"0");
    p("set isEqual nil", [sbase isEqualToSet:nil] ? @"1" : @"0");
    p("set isEqual diffCount", [sbase isEqualToSet:setY] ? @"1" : @"0");
    p("set hash equal", [sbase hash] == [[[NSSet alloc] initWithSet:sbase] hash] ? @"1" : @"0");
    p("set copy identity", [sbase copy] == sbase ? @"1" : @"0");
    p("set mutableCopy identity", [sbase mutableCopy] == sbase ? @"0" : @"1");
    p("set mutableCopy eq", [[sbase mutableCopy] isEqualToSet:sbase] ? @"1" : @"0");
    p("set copyItems eq", [[[NSSet alloc] initWithSet:sbase copyItems:YES] isEqualToSet:sbase] ? @"1" : @"0");
    p("set addFromSet", sortedObjects([sbase setByAddingObjectsFromSet:[NSSet setWithObject:@"a"]]));
    p("set addFromArray", sortedObjects([sbase setByAddingObjectsFromArray:[NSArray arrayWithObjects:(id[]){@"a", @"z"} count:2]]));
    p("set member nil", [sbase member:nil] == nil ? @"nil" : @"?");
    p("set contains nil", [sbase containsObject:nil] ? @"1" : @"0");

    NSMutableSet *ms_n = [[NSMutableSet alloc] initWithCapacity:4];
    p("ms cap count", [ms_n count] == 0 ? @"0" : @"?");
    [ms_n addObject:@"k"];
    [ms_n addObject:@"k"];
    p("ms add dup unique", [ms_n count] == 1 ? @"1" : @"0");
    [ms_n addObjectsFromArray:[NSArray arrayWithObjects:(id[]){@"b", @"a", @"b"} count:3]];
    p("ms addFromArray", [NSString stringWithFormat:@"%lu|%@", (unsigned long)[ms_n count], sortedObjects(ms_n)]);
    [ms_n removeObject:@"k"];
    p("ms remove", sortedObjects(ms_n));
    [ms_n removeObject:@"zz"];
    p("ms remove missing", sortedObjects(ms_n));
    NSMutableSet *ms_i = [[NSMutableSet alloc] initWithSet:ms_n];
    [ms_i addObject:@"c"];
    [ms_i intersectSet:[NSSet setWithObjects:@"b", @"c", @"d", nil]];
    p("ms intersect", sortedObjects(ms_i));
    NSMutableSet *ms_m = [[NSMutableSet alloc] initWithSet:[NSSet setWithObjects:@"b", @"c", nil]];
    [ms_m minusSet:[NSSet setWithObject:@"b"]];
    p("ms minus", sortedObjects(ms_m));
    NSMutableSet *ms_u = [[NSMutableSet alloc] initWithSet:[NSSet setWithObject:@"r"]];
    [ms_u unionSet:[NSSet setWithObject:@"s"]];
    p("ms union", sortedObjects(ms_u));
    [ms_u setSet:[NSSet setWithObject:@"t"]];
    p("ms setSet", sortedObjects(ms_u));
    [ms_u removeAllObjects];
    p("ms removeAll", [ms_u count] == 0 ? @"0" : @"?");
    @try {
        NSMutableSet *ms_nil = [[NSMutableSet alloc] initWithCapacity:1];
        [ms_nil addObject:nil];
    } @catch (id e) {
        p("ms add nil", [NSString stringWithFormat:@"%@", [e name]]);
    }

    NSCountedSet *cn = [[NSCountedSet alloc] initWithCapacity:2];
    p("cn cap", [cn count] == 0 ? @"0" : @"?");
    [cn addObject:@"a"];
    [cn addObject:@"a"];
    [cn addObject:@"b"];
    p("cn counts", [NSString stringWithFormat:@"%lu|ca%lu|cb%lu",
                    (unsigned long)[cn count],
                    (unsigned long)[cn countForObject:@"a"],
                    (unsigned long)[cn countForObject:@"b"]]);
    p("cn missing", [cn countForObject:@"z"] == 0 ? @"0" : @"?");
    p("cn member a", [cn member:@"a"]);
    p("cn contains", [cn containsObject:@"b"] ? @"1" : @"0");
    p("cn contains missing", [cn containsObject:@"z"] ? @"1" : @"0");
    [cn removeObject:@"a"];
    [cn removeObject:@"a"];
    p("cn rem dec", [NSString stringWithFormat:@"%lu|ca%lu|cb%lu",
                     (unsigned long)[cn count],
                     (unsigned long)[cn countForObject:@"a"],
                     (unsigned long)[cn countForObject:@"b"]]);
    [cn removeObject:@"zz"];
    p("cn rem missing", [NSString stringWithFormat:@"%lu|cb%lu",
                         (unsigned long)[cn count],
                         (unsigned long)[cn countForObject:@"b"]]);
    [cn removeAllObjects];
    p("cn removeAll", [cn count] == 0 ? @"0" : @"?");
    NSCountedSet *cnArr = [[NSCountedSet alloc] initWithArray:[NSArray arrayWithObjects:(id[]){@"x", @"x", @"y"} count:3]];
    p("cn fromArr", [NSString stringWithFormat:@"%lu|cx%lu|cy%lu",
                     (unsigned long)[cnArr count],
                     (unsigned long)[cnArr countForObject:@"x"],
                     (unsigned long)[cnArr countForObject:@"y"]]);
    p("cn fromArr sorted", sortedObjects(cnArr));
    NSEnumerator *cnEn = [cnArr objectEnumerator];
    NSUInteger cnWalk = 0;
    while ([cnEn nextObject] != nil) cnWalk++;
    p("cn enumerator", [NSString stringWithFormat:@"%lu", (unsigned long)cnWalk]);
    NSCountedSet *cnSet = [[NSCountedSet alloc] initWithSet:sbase];
    p("cn fromSet sorted", sortedObjects(cnSet));
    p("cn fromSet count", [cnSet count] == 3 ? @"3" : @"?");

    /* ---------- NSDictionary contract bundle (CFDictionary bridge + plist) ---------- */
    NSDictionary *dd0 = [NSDictionary dictionaryWithObjects:(id[]){@"2", @"1", @"3"}
                                                    forKeys:(id[]){@"a", @"b", @"c"} count:3];
    p("dd alloc init", [[[NSDictionary alloc] init] count] == 0 ? @"0" : @"?");
    p("dd count", [NSString stringWithFormat:@"%lu", (unsigned long)[dd0 count]]);
    p("dd isEqual content", [dd0 isEqualToDictionary:[NSDictionary dictionaryWithObjects:(id[]){@"2", @"9", @"3"}
                                                                                 forKeys:(id[]){@"a", @"b", @"c"} count:3]] ? @"1" : @"0");
    p("dd isEqual diff", [dd0 isEqualToDictionary:[NSDictionary dictionaryWithObjects:(id[]){@"2", @"9", @"3"}
                                                                             forKeys:(id[]){@"a", @"b", @"c"} count:3]] ? @"0" : @"1");
    p("dd hash equal", [dd0 hash] == [[NSDictionary dictionaryWithObjects:(id[]){@"2", @"1", @"3"}
                                                                  forKeys:(id[]){@"a", @"b", @"c"} count:3] hash] ? @"1" : @"0");
    p("dd copy identity", [dd0 copy] == dd0 ? @"1" : @"0");
    p("dd mutableCopy identity", [dd0 mutableCopy] == dd0 ? @"0" : @"1");
    p("dd mutableCopy eq", [[dd0 mutableCopy] isEqualToDictionary:dd0] ? @"1" : @"0");
    p("dd allKeys sorted", sortedKeys(dd0));
    p("dd objectForKeyedSubscript", dd0[@"a"]);
    p("dd missing", [dd0 objectForKey:@"z"] == nil ? @"nil" : @"?");
    p("dd objectForKey nil", [dd0 objectForKey:nil] == nil ? @"nil" : @"?");
    NSMutableArray *ddPairs = [NSMutableArray array];
    [dd0 enumerateKeysAndObjectsUsingBlock:^(id key, id obj, BOOL *stop) {
        [ddPairs addObject:[NSString stringWithFormat:@"%@=%@", key, obj]];
    }];
    p("dd enumerate sorted", sortedJoin(ddPairs));
    p("dd isEqual nil", [dd0 isEqualToDictionary:nil] ? @"1" : @"0");

    const char *tmpd = getenv("TMPDIR");
    NSString *plistPath = [NSString stringWithFormat:@"%s/port_behavior_ddict.plist",
                           tmpd ? tmpd : "/tmp"];
    FILE *pf = fopen(plistPath.UTF8String, "wb");
    fputs("<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n"
          "<!DOCTYPE plist PUBLIC \"-//Apple//DTD PLIST 1.0//EN\" "
          "\"http://www.apple.com/DTDs/PropertyList-1.0.dtd\">\n"
          "<plist version=\"1.0\">\n<dict>\n"
          "<key>name</key><string>probe</string>\n"
          "<key>num</key><integer>7</integer>\n"
          "</dict>\n</plist>\n", pf);
    fclose(pf);
    NSDictionary *dFile = [NSDictionary dictionaryWithContentsOfFile:plistPath];
    if (dFile != nil) {
        p("dd fromFile count", [NSString stringWithFormat:@"%lu", (unsigned long)[dFile count]]);
        p("dd fromFile name", dFile[@"name"]);
        p("dd fromFile num", [NSString stringWithFormat:@"%@", dFile[@"num"]]);
    } else {
        p("dd fromFile count", @"nil");
        p("dd fromFile name", @"nil");
        p("dd fromFile num", @"nil");
    }
    NSURL *plistURL = [NSURL fileURLWithPath:plistPath];
    NSError *plistErr = nil;
    NSDictionary *dURL = [NSDictionary dictionaryWithContentsOfURL:plistURL error:&plistErr];
    if (dURL != nil) {
        p("dd fromURL count", [NSString stringWithFormat:@"%lu", (unsigned long)[dURL count]]);
        p("dd fromURL num", [NSString stringWithFormat:@"%@", dURL[@"num"]]);
        p("dd fromURL err nil", plistErr == nil ? @"1" : @"0");
    } else {
        p("dd fromURL count", @"nil");
        p("dd fromURL err nil", plistErr == nil ? @"1" : @"0");
    }
    p("dd fromFile bad path", [NSDictionary dictionaryWithContentsOfFile:@"/nonexistent/pb.plist"] == nil ? @"nil" : @"?");

    NSMutableDictionary *mdd = [NSMutableDictionary dictionaryWithCapacity:4];
    p("md2 cap count", [mdd count] == 0 ? @"0" : @"?");
    p("md2 alloc init", [[[NSMutableDictionary alloc] init] count] == 0 ? @"0" : @"?");
    [mdd setObject:@"v1" forKey:@"k1"];
    p("md2 set1 count", [mdd count] == 1 ? @"1" : @"?");
    [mdd setObject:@"v2" forKey:@"k2"];
    [mdd setObject:@"v2b" forKey:@"k2"];
    p("md2 replace", [NSString stringWithFormat:@"%lu|%@", (unsigned long)[mdd count], mdd[@"k2"]]);
    mdd[@"k3"] = @"v3";
    p("md2 subscript set", mdd[@"k3"]);
    [mdd removeObjectForKey:@"k1"];
    p("md2 remove count", [NSString stringWithFormat:@"%lu", (unsigned long)[mdd count]]);
    [mdd removeObjectForKey:@"nope"];
    p("md2 remove missing", [mdd count] == 2 ? @"2" : @"?");
    @try {
        [mdd setObject:@"x" forKey:nil];
    } @catch (id e) {
        p("md2 set nil key", [NSString stringWithFormat:@"%@", [e name]]);
    }
    @try {
        [mdd setObject:nil forKey:@"kk"];
    } @catch (id e) {
        p("md2 set nil val", [NSString stringWithFormat:@"%@", [e name]]);
    }

    /* ---------- NSData contract bundle (CFData bridge, NSCFData isa) ---------- */
    p("da alloc init len", [[[NSData alloc] init] length] == 0 ? @"0" : @"?");
    p("da data empty len", [[NSData data] length] == 0 ? @"0" : @"?");
    p("da withBytes eq", memcmp(data.bytes, bytes, 8) == 0 ? @"1" : @"0");
    p("da fromData copy eq", [data isEqualToData:[NSData dataWithData:data]] ? @"1" : @"0");
    p("da fromData nil", [NSData dataWithData:nil] == nil ? @"nil" : @"?");
    unsigned char *dnb = (unsigned char *)malloc(3);
    dnb[0] = 0xde; dnb[1] = 0xad; dnb[2] = 0xbe;
    NSData *dnoCopy = [NSData dataWithBytesNoCopy:dnb length:3 freeWhenDone:NO];
    p("da noCopy len", [NSString stringWithFormat:@"%lu", (unsigned long)[dnoCopy length]]);
    const unsigned char *dnbp = (const unsigned char *)dnoCopy.bytes;
    p("da noCopy b1", [NSString stringWithFormat:@"%02x", dnbp[1]]);
    unsigned char gb[8];
    [data getBytes:gb length:8];
    p("da getBytes full", memcmp(gb, bytes, 8) == 0 ? @"1" : @"0");
    unsigned char gr[3];
    [data getBytes:gr range:NSMakeRange(2, 3)];
    p("da getBytes range", memcmp(gr, bytes + 2, 3) == 0 ? @"1" : @"0");
    p("da isEqual nil", [data isEqualToData:nil] ? @"1" : @"0");
    p("da copy identity", [data copy] == data ? @"1" : @"0");
    p("da copy isEqual", [data isEqualToData:[data copy]] ? @"1" : @"0");
    p("da empty subdata", [[data subdataWithRange:NSMakeRange(0, 0)] length] == 0 ? @"0" : @"?");
    NSData *daTail = [data subdataWithRange:NSMakeRange(6, 2)];
    const unsigned char *dtp = (const unsigned char *)daTail.bytes;
    p("da subdata tail", [NSString stringWithFormat:@"%02x|%02x", dtp[0], dtp[1]]);

    p("da m alloc init len", [[[NSMutableData alloc] init] length] == 0 ? @"0" : @"?");
    p("da m cap len", [[NSMutableData dataWithCapacity:4] length] == 0 ? @"0" : @"?");
    NSMutableData *mz = [NSMutableData dataWithLength:5];
    const unsigned char *mzp = (const unsigned char *)mz.bytes;
    p("da m dataWithLength", [NSString stringWithFormat:@"%lu|%02x|%02x",
                              (unsigned long)[mz length], mzp[0], mzp[4]]);
    NSMutableData *mdw = [NSMutableData dataWithBytes:bytes length:3];
    const unsigned char *mdwp = (const unsigned char *)mdw.bytes;
    p("da m dataWithBytes", [NSString stringWithFormat:@"%lu|%02x",
                             (unsigned long)[mdw length], mdwp[2]]);
    p("da m dataWithData nil", [NSMutableData dataWithData:nil] == nil ? @"nil" : @"?");

    NSMutableData *mdta = [NSMutableData data];
    [mdta appendBytes:bytes length:4];
    p("da m appendBytes", [NSString stringWithFormat:@"%lu|%02x|%02x",
                           (unsigned long)[mdta length],
                           ((const unsigned char *)mdta.bytes)[0],
                           ((const unsigned char *)mdta.bytes)[3]]);
    [mdta setLength:2];
    p("da m setLength shrink", [NSString stringWithFormat:@"%lu", (unsigned long)[mdta length]]);
    [mdta setLength:6];
    const unsigned char *mdp1 = (const unsigned char *)mdta.bytes;
    p("da m setLength grow", [NSString stringWithFormat:@"%lu|%02x|%02x",
                              (unsigned long)[mdta length], mdp1[0], mdp1[5]]);
    unsigned char repB[2] = {0xaa, 0xbb};
    [mdta replaceBytesInRange:NSMakeRange(1, 2) withBytes:repB];
    const unsigned char *mdp2 = (const unsigned char *)mdta.bytes;
    p("da m replace", [NSString stringWithFormat:@"%02x|%02x|%02x", mdp2[0], mdp2[1], mdp2[2]]);
    [mdta resetBytesInRange:NSMakeRange(0, 3)];
    const unsigned char *mdp3 = (const unsigned char *)mdta.bytes;
    p("da m reset", [NSString stringWithFormat:@"%02x|%02x|%02x", mdp3[0], mdp3[1], mdp3[2]]);
    [mdta setData:[NSData dataWithBytes:bytes length:2]];
    p("da m setData", [NSString stringWithFormat:@"%lu|%02x|%02x",
                       (unsigned long)[mdta length],
                       ((const unsigned char *)mdta.bytes)[0],
                       ((const unsigned char *)mdta.bytes)[1]]);
    [mdta appendData:nil];
    p("da m appendData nil", [NSString stringWithFormat:@"%lu", (unsigned long)[mdta length]]);
    [mdta appendData:[NSData dataWithBytes:bytes + 2 length:2]];
    const unsigned char *mdp4 = (const unsigned char *)mdta.bytes;
    p("da m appendData", [NSString stringWithFormat:@"%lu|%02x|%02x",
                          (unsigned long)[mdta length], mdp4[2], mdp4[3]]);
    NSMutableData *mm = [NSMutableData dataWithLength:3];
    ((unsigned char *)mm.mutableBytes)[1] = 0xee;
    [mm appendData:data];
    const unsigned char *mmp = (const unsigned char *)mm.bytes;
    p("da m mutableBytes", [NSString stringWithFormat:@"%lu|%02x|%02x",
                            (unsigned long)[mm length], mmp[1], mmp[3]]);

    /* ---------- NSDateComponents (port-implemented, not bridged) ---------- */
    NSDateComponents *dci = [[NSDateComponents alloc] init];
    p("dc init year undef", dci.year == NSDateComponentUndefined ? @"undef" : @"?");
    p("dc init week undef", [dci week] == NSDateComponentUndefined ? @"undef" : @"?");
    p("dc init cal nil", dci.calendar == nil ? @"nil" : @"?");
    p("dc init leapMonth", dci.isLeapMonth ? @"1" : @"0");
    p("dc init repeatedDay", dci.isRepeatedDay ? @"1" : @"0");
    dci.era = 1; dci.year = 2024; dci.month = 3; dci.day = 15;
    dci.hour = 10; dci.minute = 30; dci.second = 45; dci.nanosecond = 500;
    dci.weekday = 6; dci.weekdayOrdinal = 3; dci.quarter = 2;
    dci.weekOfMonth = 2; dci.weekOfYear = 10; dci.yearForWeekOfYear = 2024;
    dci.dayOfYear = 75;
    p("dc set era", [NSString stringWithFormat:@"%ld", (long)dci.era]);
    p("dc set year", [NSString stringWithFormat:@"%ld", (long)dci.year]);
    p("dc set month", [NSString stringWithFormat:@"%ld", (long)dci.month]);
    p("dc set day", [NSString stringWithFormat:@"%ld", (long)dci.day]);
    p("dc set hour", [NSString stringWithFormat:@"%ld", (long)dci.hour]);
    p("dc set minute", [NSString stringWithFormat:@"%ld", (long)dci.minute]);
    p("dc set second", [NSString stringWithFormat:@"%ld", (long)dci.second]);
    p("dc set nanosecond", [NSString stringWithFormat:@"%ld", (long)dci.nanosecond]);
    p("dc set weekday", [NSString stringWithFormat:@"%ld", (long)dci.weekday]);
    p("dc set weekdayOrdinal", [NSString stringWithFormat:@"%ld", (long)dci.weekdayOrdinal]);
    p("dc set quarter", [NSString stringWithFormat:@"%ld", (long)dci.quarter]);
    p("dc set weekOfMonth", [NSString stringWithFormat:@"%ld", (long)dci.weekOfMonth]);
    p("dc set weekOfYear", [NSString stringWithFormat:@"%ld", (long)dci.weekOfYear]);
    p("dc set yearForWeekOfYear", [NSString stringWithFormat:@"%ld", (long)dci.yearForWeekOfYear]);
    p("dc set dayOfYear", [NSString stringWithFormat:@"%ld", (long)dci.dayOfYear]);
    p("dc set week", [NSString stringWithFormat:@"%ld", (long)[dci week]]);
    p("dc set leapMonth", [NSString stringWithFormat:@"%ld", (long)dci.isLeapMonth]);
    p("dc valueFor year", [NSString stringWithFormat:@"%ld", (long)[dci valueForComponent:NSCalendarUnitYear]]);
    p("dc valueFor nanosecond", [NSString stringWithFormat:@"%ld", (long)[dci valueForComponent:NSCalendarUnitNanosecond]]);
    [dci setValue:2030 forComponent:NSCalendarUnitYear];
    p("dc setValue year", [NSString stringWithFormat:@"%ld", (long)dci.year]);
    p("dc valueFor setValue", [NSString stringWithFormat:@"%ld", (long)[dci valueForComponent:NSCalendarUnitDay]]);
    NSDateComponents *dcp1 = [dci copy];
    p("dc copy identity", dcp1 != dci ? @"1" : @"0");
    p("dc copy year", [NSString stringWithFormat:@"%ld", (long)dcp1.year]);
    p("dc copy day", [NSString stringWithFormat:@"%ld", (long)dcp1.day]);
    p("dc copy week", [NSString stringWithFormat:@"%ld", (long)[dcp1 week]]);
    p("dc isValid full no cal", dci.isValidDate ? @"1" : @"0");
    NSCalendar *cgr = [NSCalendar calendarWithIdentifier:NSCalendarIdentifierGregorian];
    NSDateComponents *dcv = [[NSDateComponents alloc] init];
    dcv.year = 2024; dcv.month = 2; dcv.day = 29;
    p("dc valid feb29 gr", [dcv isValidDateInCalendar:cgr] ? @"1" : @"0");
    dcv.month = 2; dcv.day = 30;
    p("dc valid feb30 gr", [dcv isValidDateInCalendar:cgr] ? @"1" : @"0");
    dcv.month = 13; dcv.day = 1;
    p("dc valid month13 gr", [dcv isValidDateInCalendar:cgr] ? @"1" : @"0");
    dcv.year = 2024; dcv.month = 4; dcv.day = 31;
    p("dc valid apr31 gr", [dcv isValidDateInCalendar:cgr] ? @"1" : @"0");
    catchProbe("dc valid nil cal", ^{ return [dcv isValidDateInCalendar:nil] ? @"1" : @"0"; });
    p("dc date nil cal", [[[[NSDateComponents alloc] init] date] description] == nil ? @"nil" : @"?");
    NSDateComponents *dcw = [[NSDateComponents alloc] init];
    dcw.calendar = cgr; dcw.year = 2024; dcw.month = 2; dcw.day = 29;
    p("dc isValid set cal", dcw.isValidDate ? @"1" : @"0");
    p("dc date with cal", [[dcw date] description] == nil ? @"nil" : [[dcw date] description]);

    /* ---------- NSDate contract bundle (CFDate bridge) ---------- */
    NSDate *td1 = [[NSDate alloc] initWithTimeIntervalSinceReferenceDate:1000.0];
    p("td init rfd 1000", [NSString stringWithFormat:@"%.9f", td1.timeIntervalSinceReferenceDate]);
    p("td init rfd eq factory", [[NSDate dateWithTimeIntervalSinceReferenceDate:1000.0] isEqualToDate:td1] ? @"1" : @"0");
    p("td init 1970 ref", [NSString stringWithFormat:@"%.9f", [[[NSDate alloc] initWithTimeIntervalSince1970:978307200.0] timeIntervalSinceReferenceDate]]);
    p("td init 1970 zero", [NSString stringWithFormat:@"%.9f|%.9f",
                            [[[NSDate alloc] initWithTimeIntervalSince1970:0.0] timeIntervalSince1970],
                            [[[NSDate alloc] initWithTimeIntervalSince1970:0.0] timeIntervalSinceReferenceDate]]);
    p("td dateBy adding eq", [[d1 dateByAddingTimeInterval:60.0] isEqualToDate:[NSDate dateWithTimeIntervalSince1970:1234567950.0]] ? @"1" : @"0");
    p("td isEqual same obj", [d1 isEqual:d1] ? @"1" : @"0");
    p("td isEqual equal value", [[NSDate dateWithTimeIntervalSince1970:1234567890.0] isEqual:d1] ? @"1" : @"0");
    p("td isEqual nil", [d1 isEqual:nil] ? @"1" : @"0");
    p("td isEqual string", [d1 isEqual:@"x"] ? @"1" : @"0");
    p("td isEqualToDate nil", [d1 isEqualToDate:nil] ? @"1" : @"0");
    p("td hash equal", [[NSDate dateWithTimeIntervalSince1970:1234567890.0] hash] == d1.hash ? @"1" : @"0");
    p("td compare same", [NSString stringWithFormat:@"%ld", (long)[d1 compare:d1]]);
    catchProbe("td compare nil", ^{ return [NSString stringWithFormat:@"%ld", (long)[d1 compare:nil]]; });
    p("td copy identity", [d1 copy] == d1 ? @"1" : @"0");
    p("td sentinel diff", [NSString stringWithFormat:@"%.9f", [[NSDate distantFuture] timeIntervalSinceDate:[NSDate distantPast]]]);
    p("td distantFuture eq", [[NSDate distantFuture] isEqualToDate:[NSDate distantFuture]] ? @"1" : @"0");
    p("td distantPast eq", [[NSDate distantPast] isEqualToDate:[NSDate distantPast]] ? @"1" : @"0");
    p("td desc locale", [d1 descriptionWithLocale:nil]);
    p("td earlier equal", ([d1 earlierDate:d1] == d1) ? @"1" : @"0");
    p("td later equal", ([d1 laterDate:d1] == d1) ? @"1" : @"0");

    NSTimeZone *tzNY = [NSTimeZone timeZoneWithName:@"America/New_York"];
    NSTimeZone *tzParis = [NSTimeZone timeZoneWithName:@"Europe/Paris"];
    NSTimeZone *tzTokyo = [NSTimeZone timeZoneWithName:@"Asia/Tokyo"];
    NSTimeZone *tzKolkata = [NSTimeZone timeZoneWithName:@"Asia/Kolkata"];
    p("tz NY gmt winter", [NSString stringWithFormat:@"%ld", (long)[tzNY secondsFromGMTForDate:d1]]);
    p("tz Paris gmt winter", [NSString stringWithFormat:@"%ld", (long)[tzParis secondsFromGMTForDate:d1]]);
    p("tz Tokyo gmt", [NSString stringWithFormat:@"%ld", (long)[tzTokyo secondsFromGMTForDate:d1]]);
    p("tz Kolkata gmt", [NSString stringWithFormat:@"%ld", (long)[tzKolkata secondsFromGMTForDate:d1]]);
    p("tz Tokyo now gmt", [NSString stringWithFormat:@"%ld", (long)[tzTokyo secondsFromGMT]]);
    p("tz NY abbr winter", [tzNY abbreviationForDate:d1]);
    p("tz Paris abbr winter", [tzParis abbreviationForDate:d1]);
    p("tz NY dst winter", [tzNY isDaylightSavingTimeForDate:d1] ? @"1" : @"0");
    NSDate *dSummer = [d1 dateByAddingTimeInterval:150.0 * 86400.0];
    p("tz NY dst summer", [tzNY isDaylightSavingTimeForDate:dSummer] ? @"1" : @"0");
    p("tz Tokyo dst summer", [tzTokyo isDaylightSavingTimeForDate:dSummer] ? @"1" : @"0");
    p("tz NY dstoff summer", [NSString stringWithFormat:@"%.0f", [tzNY daylightSavingTimeOffsetForDate:dSummer]]);
    p("tz NY dstoff winter", [NSString stringWithFormat:@"%.0f", [tzNY daylightSavingTimeOffsetForDate:d1]]);
    p("tz NY next dst", [NSString stringWithFormat:@"%.0f", [[tzNY nextDaylightSavingTimeTransitionAfterDate:d1] timeIntervalSince1970]]);
    p("tz NY next std", [NSString stringWithFormat:@"%.0f", [[tzNY nextDaylightSavingTimeTransitionAfterDate:dSummer] timeIntervalSince1970]]);
    p("tz Tokyo next dst", [tzTokyo nextDaylightSavingTimeTransitionAfterDate:d1] == nil ? @"1" : @"0");
    NSTimeZone *tzGMT530 = [NSTimeZone timeZoneForSecondsFromGMT:19800];
    p("tz gmt530 name", tzGMT530.name);
    p("tz gmt530 offset", [NSString stringWithFormat:@"%ld", (long)[tzGMT530 secondsFromGMTForDate:d1]]);
    NSTimeZone *tzGMT = [NSTimeZone timeZoneForSecondsFromGMT:0];
    p("tz gmt name", tzGMT.name);
    p("tz gmt offset", [NSString stringWithFormat:@"%ld", (long)[tzGMT secondsFromGMTForDate:d1]]);
    p("tz known count", [NSTimeZone knownTimeZoneNames].count > 50 ? @"1" : @"0");
    p("tz known ny", [[NSTimeZone knownTimeZoneNames] containsObject:@"America/New_York"] ? @"1" : @"0");
    p("tz known tokyo", [[NSTimeZone knownTimeZoneNames] containsObject:@"Asia/Tokyo"] ? @"1" : @"0");
    p("tz abbrdict est", [NSTimeZone abbreviationDictionary][@"EST"]);
    p("tz abbrdict pst", [NSTimeZone abbreviationDictionary][@"PST"]);
    p("tz abbrdict utc", [NSTimeZone abbreviationDictionary][@"UTC"]);
    p("tz abbr est", [NSTimeZone timeZoneWithAbbreviation:@"EST"].name);
    p("tz abbr bad", [NSTimeZone timeZoneWithAbbreviation:@"QQQ"] == nil ? @"1" : @"0");
    p("tz isEqual ny", [tzNY isEqual:[NSTimeZone timeZoneWithName:@"America/New_York"]] ? @"1" : @"0");
    p("tz isEqual paris", [tzNY isEqual:tzParis] ? @"1" : @"0");
    p("tz hash ny", [tzNY hash] == [[NSTimeZone timeZoneWithName:@"America/New_York"] hash] ? @"1" : @"0");
    p("tz badname", [NSTimeZone timeZoneWithName:@"NoSuch/Zone"] == nil ? @"1" : @"0");
    p("tz data len", tzNY.data.length > 0 ? @"1" : @"0");
    p("tz local len", [NSTimeZone localTimeZone].name.length > 0 ? @"1" : @"0");
    p("tz system len", [NSTimeZone systemTimeZone].name.length > 0 ? @"1" : @"0");
    p("tz default sys", [[NSTimeZone defaultTimeZone] isEqual:[NSTimeZone systemTimeZone]] ? @"1" : @"0");
    [NSTimeZone setDefaultTimeZone:tzNY];
    p("tz default set", [[NSTimeZone defaultTimeZone].name isEqualToString:@"America/New_York"] ? @"1" : @"0");
    [NSTimeZone resetSystemTimeZone];
    p("tz default reset", [[NSTimeZone defaultTimeZone].name isEqualToString:@"America/New_York"] ? @"1" : @"0");
    catchProbe("tz setdefault nil", ^id{
        [NSTimeZone setDefaultTimeZone:nil];
        return @"no raise";
    });

    printf("PORT_BEHAVIOR_END\n");
    return 0;
}