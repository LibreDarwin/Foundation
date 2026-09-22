#import <Foundation/Foundation.h>
#include <stdio.h>
#include <stdlib.h>

#pragma clang diagnostic ignored "-Wobjc-literal-conversion"

static void p(const char *label, NSString *value) {
    printf("%-42s | %s\n", label, value ? value.UTF8String : "(null)");
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

int main(void) {
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

    printf("PORT_BEHAVIOR_END\n");
    return 0;
}