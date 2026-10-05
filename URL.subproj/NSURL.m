/*
 * Copyright (C) 2026, Samuel Zormeister.
 *
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */

#import <Foundation/NSURL.h>
#import <Foundation/NSArray.h>
#import <Foundation/NSData.h>
#import <Foundation/NSDictionary.h>
#import <Foundation/NSException.h>
#import <Foundation/NSNumber.h>
#import <Foundation/NSString.h>
#include <CoreFoundation/CFURL.h>
#include <CoreFoundation/ForFoundationOnly.h>
#include <limits.h>
#include <objc/runtime.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>

NSString *const NSURLNameKey = @"NSURLNameKey";
NSString *const NSURLLocalizedNameKey = @"NSURLLocalizedNameKey";
NSString *const NSURLIsRegularFileKey = @"NSURLIsRegularFileKey";
NSString *const NSURLIsDirectoryKey = @"NSURLIsDirectoryKey";
NSString *const NSURLIsSymbolicLinkKey = @"NSURLIsSymbolicLinkKey";
NSString *const NSURLIsVolumeKey = @"NSURLIsVolumeKey";
NSString *const NSURLIsPackageKey = @"NSURLIsPackageKey";
NSString *const NSURLIsSystemImmutableKey = @"NSURLIsSystemImmutableKey";
NSString *const NSURLIsUserImmutableKey = @"NSURLIsUserImmutableKey";
NSString *const NSURLIsHiddenKey = @"NSURLIsHiddenKey";
NSString *const NSURLExtensionKey = @"NSURLExtensionKey";
NSString *const NSURLPathKey = @"NSURLPathKey";
NSString *const NSURLCanonicalPathKey = @"NSURLCanonicalPathKey";
NSString *const NSURLFileSizeKey = @"NSURLFileSizeKey";
NSString *const NSURLFileAllocatedSizeKey = @"NSURLFileAllocatedSizeKey";
NSString *const NSURLTotalFileSizeKey = @"NSURLTotalFileSizeKey";
NSString *const NSURLTotalFileAllocatedSizeKey = @"NSURLTotalFileAllocatedSizeKey";
NSString *const NSURLIsReadableKey = @"NSURLIsReadableKey";
NSString *const NSURLIsWritableKey = @"NSURLIsWritableKey";
NSString *const NSURLIsExecutableKey = @"NSURLIsExecutableKey";
NSString *const NSURLFileSecurityKey = @"NSURLFileSecurityKey";
NSString *const NSURLIsExcludedFromBackupKey = @"NSURLIsExcludedFromBackupKey";
/* Apple's private spelling of -path; the public name is NSURLPathKey. */
NSString *const NSURLPathKeyPrivate = @"_NSURLPathKey";

/* Every NSURL instance is a CFURL whose isa is bridged to NSURL (see the
 * constructor at the bottom of this file), so all of these receivers are
 * really CFURLRef.  Casting self is therefore the intended access path. */

/* Adopt a +1 CFURL as an ARC-managed NSURL, or nil if the CF call produced
 * nothing.  Ownership annotations belong on the cast, not the declarator. */
static inline NSURL *_Nullable NSURLTransferCFURL(CFURLRef _Nullable url) {
    return CFBridgingRelease(url);
}

static inline CFURLRef _Nullable NSURLGetCFURL(NSURL *url) {
    return (__bridge CFURLRef)url;
}

/* Apple's -URLWithString: percent-encodes as it parses; CFURL on its own
 * rejects a string containing a space or any other character outside the
 * allowed set.  This is the character table Apple leaves alone:
 *
 *   !#$&'()*+,-./0123456789:;=?@ABCDEFGHIJKLMNOPQRSTUVWXYZ_abcdefghijklmnopqrstuvwxyz~
 *
 * Everything else -- including space, control characters, non-ASCII, and
 * the delimiters " < > [ \ ] ^ ` { | } -- is encoded as its UTF-8 bytes in
 * %XX form.  An existing valid "%XX" escape is preserved rather than
 * re-encoded, which is why "a%20b" survives but "a%2zb" becomes "a%252zb".
 */
static BOOL NSURLStringCharacterIsAllowed(unichar c) {
    if ((c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') ||
        (c >= '0' && c <= '9')) {
        return YES;
    }
    switch (c) {
        case '!': case '#': case '$': case '&': case '\'': case '(':
        case ')': case '*': case '+': case ',': case '-': case '.':
        case '/': case ':': case ';': case '=': case '?': case '@':
        case '_': case '~':
            return YES;
        default:
            return NO;
    }
}

static int NSURLHexDigitValue(unichar c) {
    if (c >= '0' && c <= '9') { return c - '0'; }
    if (c >= 'a' && c <= 'f') { return c - 'a' + 10; }
    if (c >= 'A' && c <= 'F') { return c - 'A' + 10; }
    return -1;
}

/* Apple keeps "[" and "]" literal only when they bracket an IPv6 literal
 * in the authority component; anywhere else they are encoded.  A malformed
 * bracket in the authority makes the whole URL invalid, which is why
 * "http://[" and "http://[]x/" are nil while "http://[::1]/" is not.
 *
 * Returns the range of the authority component (the text between the
 * "//" of the scheme and the next "/", "?", or "#"), or NSNotFound when the
 * string has no authority. */
static NSRange NSURLAuthorityRange(NSString *string) {
    NSUInteger length = string.length;
    NSUInteger start = NSNotFound;

    NSRange schemeSep = [string rangeOfString:@"://"];
    if (schemeSep.location != NSNotFound) {
        start = schemeSep.location + schemeSep.length;
    } else if (length >= 2 &&
               [string characterAtIndex:0] == '/' &&
               [string characterAtIndex:1] == '/') {
        start = 2;
    } else {
        return NSMakeRange(NSNotFound, 0);
    }

    NSUInteger end = length;
    for (NSUInteger i = start; i < length; i++) {
        unichar c = [string characterAtIndex:i];
        if (c == '/' || c == '?' || c == '#') {
            end = i;
            break;
        }
    }
    return NSMakeRange(start, end - start);
}

/* Index of the last occurrence of `c` in `s` at or after `from`, or NSNotFound.
 * The port's NSString has no ranged search, so scan directly. */
static NSUInteger NSURLLastIndexOfCharacter(NSString *s,
                                           unichar c,
                                           NSUInteger from) {
    NSUInteger length = s.length;
    for (NSUInteger i = length; i > from; i--) {
        if ([s characterAtIndex:i - 1] == c) {
            return i - 1;
        }
    }
    return NSNotFound;
}

/* Index of the first occurrence of `c` in `s` at or after `from`, or NSNotFound. */
static NSUInteger NSURLIndexOfCharacter(NSString *s, unichar c, NSUInteger from) {
    NSUInteger length = s.length;
    for (NSUInteger i = from; i < length; i++) {
        if ([s characterAtIndex:i] == c) {
            return i;
        }
    }
    return NSNotFound;
}

/* Validate the bracket structure of an authority component.  An IPv6 literal
 * host is "[" ... "]" and must span the whole host, so trailing junk after
 * the closing bracket, an unterminated bracket, or a stray closing bracket
 * are all rejected. */
static BOOL NSURLAuthorityBracketsAreValid(NSString *authority) {
    NSUInteger length = authority.length;
    NSUInteger firstOpen = NSURLIndexOfCharacter(authority, '[', 0);
    NSUInteger firstClose = NSURLIndexOfCharacter(authority, ']', 0);
    BOOL hasOpen = (firstOpen != NSNotFound);
    BOOL hasClose = (firstClose != NSNotFound);

    if (!hasOpen && !hasClose) {
        return YES;
    }
    if (hasOpen != hasClose) {
        return NO;
    }

    /* The host is the authority minus any userinfo; a bracketed host must
     * begin at its first '[' and end at its last ']'. */
    NSUInteger hostStart = 0;
    NSUInteger at = NSURLLastIndexOfCharacter(authority, '@', 0);
    if (at != NSNotFound) {
        hostStart = at + 1;
    }

    NSUInteger hostOpen = NSURLIndexOfCharacter(authority, '[', hostStart);
    if (hostOpen != NSNotFound && hostOpen != hostStart) {
        return NO;
    }
    if (hostOpen != NSNotFound &&
        NSURLIndexOfCharacter(authority, '[', hostOpen + 1) != NSNotFound) {
        /* A second '[' means a nested literal such as "//[a[b]/". */
        return NO;
    }

    NSUInteger hostClose = NSURLLastIndexOfCharacter(authority, ']', hostStart);
    if (hostClose == NSNotFound) {
        return NO;
    }
    if (hostOpen != NSNotFound &&
        NSURLLastIndexOfCharacter(authority, ']', hostOpen + 1) != hostClose) {
        /* A ']' before the host literal closed, e.g. "//[a]b]/". */
        return NO;
    }

    /* Everything after the closing bracket must be empty or ":port", and a
     * second '[' there means the host was never closed properly. */
    NSUInteger tailStart = hostClose + 1;
    if (tailStart < length) {
        if ([authority characterAtIndex:tailStart] != ':') {
            return NO;
        }
        if (NSURLIndexOfCharacter(authority, '[', tailStart) != NSNotFound) {
            return NO;
        }
    }
    return YES;
}

/* Validate the authority component the way CFURL does.  Unlike the path,
 * query, and fragment -- where illegal characters get percent-encoded -- a
 * raw character that is not legal in an authority makes the whole URL nil,
 * and a bracketed host requires a numeric port. */
static BOOL NSURLAuthorityIsValid(NSString *authority) {
    if (!NSURLAuthorityBracketsAreValid(authority)) {
        return NO;
    }

    NSUInteger length = authority.length;

    /* Every raw character in the authority must already be legal, but a
     * well-formed "%XX" escape passes through untouched. */
    for (NSUInteger i = 0; i < length; i++) {
        unichar c = [authority characterAtIndex:i];
        if (c == '%' && i + 2 < length &&
            NSURLHexDigitValue([authority characterAtIndex:i + 1]) >= 0 &&
            NSURLHexDigitValue([authority characterAtIndex:i + 2]) >= 0) {
            i += 2;
            continue;
        }
        if (c == '[' || c == ']') {
            continue;
        }
        if (!NSURLStringCharacterIsAllowed(c)) {
            return NO;
        }
    }

    /* Locate the host, then check that any ":port" suffix is numeric.  A
     * bracketed host's closing ']' is the delimiter; otherwise the first
     * ':' after the userinfo separates host from port. */
    NSUInteger hostStart = 0;
    NSUInteger at = NSURLLastIndexOfCharacter(authority, '@', 0);
    if (at != NSNotFound) {
        hostStart = at + 1;
    }

    NSUInteger portStart = NSNotFound;
    if (hostStart < length && [authority characterAtIndex:hostStart] == '[') {
        NSUInteger close = NSURLIndexOfCharacter(authority, ']', hostStart);
        if (close != NSNotFound && close + 1 < length) {
            portStart = close + 1;
        }
    } else {
        NSUInteger colon = NSURLIndexOfCharacter(authority, ':', hostStart);
        if (colon != NSNotFound) {
            portStart = colon;
        }
    }

    if (portStart != NSNotFound) {
        if (portStart >= length || [authority characterAtIndex:portStart] != ':') {
            return NO;
        }
        for (NSUInteger i = portStart + 1; i < length; i++) {
            unichar c = [authority characterAtIndex:i];
            if (c < '0' || c > '9') {
                return NO;
            }
        }
    }
    return YES;
}

/* RFC 3986 scheme: ALPHA *( ALPHA / DIGIT / "+" / "-" / "." ) */
static BOOL NSURLIsValidScheme(NSString *string, NSUInteger length) {
    if (length == 0) {
        return NO;
    }
    unichar first = [string characterAtIndex:0];
    if (!((first >= 'a' && first <= 'z') || (first >= 'A' && first <= 'Z'))) {
        return NO;
    }
    for (NSUInteger i = 1; i < length; i++) {
        unichar c = [string characterAtIndex:i];
        BOOL ok = (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') ||
                  (c >= '0' && c <= '9') || c == '+' || c == '-' || c == '.';
        if (!ok) {
            return NO;
        }
    }
    return YES;
}

/* Classify the leading "scheme:" of a string that has no authority.
 *
 * Returns 1 when a ':' is a scheme delimiter and must stay literal, 0 when
 * the leading segment is a relative path whose colons must be encoded, and
 * -1 when the leading segment cannot be a scheme and cannot be a path
 * either, which makes the URL invalid ("1:2", ".a:b", "a b:c").
 *
 * Only the first path segment can be a scheme: a ':' past the first '/',
 * '?' or '#' is unambiguously part of the path, query, or fragment. */
static int NSURLLeadingColonDisposition(NSString *string) {
    NSUInteger length = string.length;

    /* The scheme, if any, ends at the first '/', '?' or '#'. */
    NSUInteger segmentEnd = length;
    for (NSUInteger i = 0; i < length; i++) {
        unichar c = [string characterAtIndex:i];
        if (c == '/' || c == '?' || c == '#') {
            segmentEnd = i;
            break;
        }
    }
    if (segmentEnd == 0) {
        return 1;
    }

    NSUInteger colon = NSURLIndexOfCharacter(string, ':', 0);
    if (colon == NSNotFound || colon >= segmentEnd) {
        return 1;
    }
    if (colon == 0) {
        /* A leading ':' is an empty scheme, e.g. ":1]". */
        return 1;
    }
    if (NSURLIsValidScheme(string, colon)) {
        return 1;
    }
    NSUInteger bracket = NSURLIndexOfCharacter(string, '[', 0);
    if (bracket != NSNotFound && bracket < colon) {
        /* A bracket cannot begin a scheme, so this is a relative path. */
        return 0;
    }
    return -1;
}

/* Percent-encode a string the way Apple's -URLWithString: does, leaving
 * well-formed escapes and already-allowed characters untouched.
 * Returns nil when the string cannot form a valid URL. */
static NSString *_Nullable NSURLEncodeIllegalCharacters(NSString *string) {
    NSRange authority = NSURLAuthorityRange(string);
    NSString *authorityText = nil;
    if (authority.location != NSNotFound && authority.length > 0) {
        authorityText = [string substringWithRange:authority];
        if (!NSURLAuthorityIsValid(authorityText)) {
            return nil;
        }
    }

    /* With no authority, a leading segment that is neither a scheme nor a
     * path cannot be parsed at all. */
    int colonDisposition = authorityText != nil ? 1 : NSURLLeadingColonDisposition(string);
    if (colonDisposition < 0) {
        return nil;
    }

    NSUInteger length = string.length;
    NSUInteger firstSlash = NSURLIndexOfCharacter(string, '/', 0);
    NSMutableString *out = [NSMutableString stringWithCapacity:length];
    for (NSUInteger i = 0; i < length; i++) {
        unichar c = [string characterAtIndex:i];

        /* Brackets inside a valid IPv6 authority stay literal. */
        if ((c == '[' || c == ']') && authorityText != nil &&
            i >= authority.location && i < authority.location + authority.length) {
            [out appendFormat:@"%C", c];
            continue;
        }

        /* A "%" followed by two hex digits is already an escape: keep it. */
        if (c == '%' && i + 2 < length) {
            unichar h = [string characterAtIndex:i + 1];
            unichar l = [string characterAtIndex:i + 2];
            if (NSURLHexDigitValue(h) >= 0 && NSURLHexDigitValue(l) >= 0) {
                [out appendFormat:@"%C%C%C", c, h, l];
                i += 2;
                continue;
            }
        }

        /* In a relative first segment the colon is ambiguous with a scheme
         * delimiter, so Apple escapes it: "[::1]" -> "%5B%3A%3A1%5D".  A
         * colon past the first '/' is unambiguously part of the path. */
        if (c == ':' && colonDisposition == 0 && i < firstSlash) {
            [out appendString:@"%3A"];
            continue;
        }

        if (NSURLStringCharacterIsAllowed(c)) {
            [out appendFormat:@"%C", c];
            continue;
        }

        /* Encode the character's UTF-8 bytes as %XX.  A character outside
         * the BMP needs a surrogate pair, so encode the whole pair. */
        NSString *piece;
        if (c >= 0xD800 && c <= 0xDBFF && i + 1 < length) {
            unichar low = [string characterAtIndex:i + 1];
            if (low >= 0xDC00 && low <= 0xDFFF) {
                piece = [NSString stringWithCharacters:&c length:1];
                piece = [[piece stringByAppendingFormat:@"%C", low] copy];
                i++;
            } else {
                piece = [NSString stringWithCharacters:&c length:1];
            }
        } else {
            piece = [NSString stringWithCharacters:&c length:1];
        }

        const char *utf8 = piece.UTF8String;
        if (utf8 == NULL) {
            continue;
        }
        for (const char *b = utf8; *b != '\0'; b++) {
            [out appendFormat:@"%%%02X", (unsigned char)*b];
        }
    }
    return out;
}

/* CFURL component getters return borrowed CFStringRefs, so retain before
 * transferring to ARC. */
static NSString *_Nullable NSURLCopyComponent(CFStringRef _Nullable s) {
    if (s == NULL) {
        return nil;
    }
    return CFBridgingRelease(CFRetain(s));
}

/* ---------------------------------------------------------------- */
/* Creating URLs                                                     */
/* ---------------------------------------------------------------- */

@implementation NSURL

+ (nullable instancetype)URLWithString:(NSString *)string {
    if (string == nil) {
        return nil;
    }
    return [[self alloc] initWithString:string];
}

+ (nullable instancetype)URLWithString:(NSString *)string
                         relativeToURL:(nullable NSURL *)baseURL {
    if (string == nil) {
        return nil;
    }
    return [[self alloc] initWithString:string relativeToURL:baseURL];
}

+ (instancetype)fileURLWithPath:(NSString *)path {
    return [[self alloc] initFileURLWithPath:path];
}

+ (instancetype)fileURLWithPath:(NSString *)path
                    isDirectory:(BOOL)isDirectory {
    return [[self alloc] initFileURLWithPath:path isDirectory:isDirectory];
}

+ (instancetype)fileURLWithPath:(NSString *)path
                    isDirectory:(BOOL)isDirectory
                 relativeToURL:(nullable NSURL *)baseURL {
    return [[self alloc] initFileURLWithPath:path
                                relativeToURL:baseURL];
}

- (nullable instancetype)initWithString:(NSString *)string {
    /* Apple's -initWithString: funnels through the four-argument
     * -initWithString:relativeToURL:encodingInvalidCharacters:, and the
     * exception reason it raises names that selector.  Match the text so
     * callers matching on the reason keep working. */
    if (string == nil) {
        @throw [NSException exceptionWithName:NSInvalidArgumentException
                                       reason:@"nil string parameter"
                                     userInfo:nil];
    }
    /* Encode before handing the string to CFURL: CFURL itself rejects a
     * string containing a space, where Apple accepts and escapes it.  A
     * malformed bracket in the authority makes the URL nil. */
    NSString *encoded = NSURLEncodeIllegalCharacters(string);
    if (encoded == nil) {
        return nil;
    }
    return NSURLTransferCFURL(CFURLCreateWithString(kCFAllocatorDefault,
                                                    (__bridge CFStringRef)encoded,
                                                    NULL));
}

- (nullable instancetype)initWithString:(NSString *)string
                           relativeToURL:(nullable NSURL *)baseURL {
    if (string == nil) {
        @throw [NSException exceptionWithName:NSInvalidArgumentException
                                       reason:@"nil string parameter"
                                     userInfo:nil];
    }
    /* A relative string plus a base URL is the one case CFURL can build
     * directly; CFURLCreateWithString has no base parameter. */
    NSString *encoded = NSURLEncodeIllegalCharacters(string);
    if (encoded == nil) {
        return nil;
    }
    return NSURLTransferCFURL(CFURLCreateWithString(kCFAllocatorDefault,
                                                    (__bridge CFStringRef)encoded,
                                                    NSURLGetCFURL(baseURL)));
}

- (instancetype)initFileURLWithPath:(NSString *)path {
    /* Apple infers "is a directory" from a trailing slash here: this is the
     * initializer that has no isDirectory: argument, and it must preserve
     * "file:///base/dir/" so that relative URLs resolve against the
     * directory rather than its parent. */
    BOOL isDirectory = [path hasSuffix:@"/"] ? YES : NO;
    return NSURLTransferCFURL(CFURLCreateWithFileSystemPath(kCFAllocatorDefault,
                                                            (__bridge CFStringRef)path,
                                                            kCFURLPOSIXPathStyle,
                                                            isDirectory ? true : false));
}

- (instancetype)initFileURLWithPath:(NSString *)path
                        isDirectory:(BOOL)isDirectory {
    return NSURLTransferCFURL(CFURLCreateWithFileSystemPath(kCFAllocatorDefault,
                                                            (__bridge CFStringRef)path,
                                                            kCFURLPOSIXPathStyle,
                                                            isDirectory ? true : false));
}

- (nullable instancetype)initFileURLWithPath:(NSString *)path
                                relativeToURL:(nullable NSURL *)baseURL {
    if (path == nil) {
        @throw [NSException exceptionWithName:NSInvalidArgumentException
                                       reason:@"nil string parameter"
                                     userInfo:nil];
    }
    /* A nil base is legal: Apple returns an absolute URL. */
    return NSURLTransferCFURL(CFURLCreateWithFileSystemPathRelativeToBase(
        kCFAllocatorDefault,
        (__bridge CFStringRef)path,
        kCFURLPOSIXPathStyle,
        false,
        NSURLGetCFURL(baseURL)));
}

/* ---------------------------------------------------------------- */
/* Reading the components                                            */
/* ---------------------------------------------------------------- */

- (NSString *)absoluteString {
    CFStringRef s = CFURLGetString(NSURLGetCFURL(self));
    return CFBridgingRelease(CFRetain(s));
}

- (NSString *)relativeString {
    /* CFURLGetString already yields the string the URL was built from, so a
     * URL created relative to a base reports that relative string and an
     * absolute URL reports its absolute string -- which is exactly what
     * Apple returns for -relativeString in both cases. */
    return self.absoluteString;
}

- (nullable NSURL *)baseURL {
    /* CFURLGetBaseURL returns a borrowed reference, so retain before
     * handing it to the ARC transfer helper. */
    CFURLRef base = CFURLGetBaseURL(NSURLGetCFURL(self));
    if (base == NULL) {
        return nil;
    }
    return NSURLTransferCFURL(CFRetain(base));
}

- (NSURL *)absoluteURL {
    return NSURLTransferCFURL(CFURLCopyAbsoluteURL(NSURLGetCFURL(self)));
}

- (nullable NSString *)scheme {
    return NSURLCopyComponent(CFURLCopyScheme(NSURLGetCFURL(self)));
}

- (nullable NSString *)user {
    return NSURLCopyComponent(CFURLCopyUserName(NSURLGetCFURL(self)));
}

- (nullable NSString *)password {
    return NSURLCopyComponent(CFURLCopyPassword(NSURLGetCFURL(self)));
}

- (nullable NSString *)host {
    return NSURLCopyComponent(CFURLCopyHostName(NSURLGetCFURL(self)));
}

- (nullable NSNumber *)port {
    SInt32 port = CFURLGetPortNumber(NSURLGetCFURL(self));
    if (port < 0) {
        return nil;
    }
    return @(port);
}

- (nullable NSString *)path {
    return NSURLCopyComponent(CFURLCopyFileSystemPath(NSURLGetCFURL(self),
                                                      kCFURLPOSIXPathStyle));
}

- (nullable NSString *)relativePath {
    /* Apple reports the strict (still-encoded) path relative to the base;
     * when there is no base it coincides with -path. */
    Boolean isAbsolute = false;
    CFStringRef s = CFURLCopyStrictPath(NSURLGetCFURL(self), &isAbsolute);
    return NSURLCopyComponent(s);
}

- (NSString *)pathExtension {
    return NSURLCopyComponent(CFURLCopyPathExtension(NSURLGetCFURL(self))) ?: @"";
}

- (NSString *)lastPathComponent {
    return NSURLCopyComponent(CFURLCopyLastPathComponent(NSURLGetCFURL(self))) ?: @"";
}

- (nullable NSString *)query {
    return NSURLCopyComponent(CFURLCopyQueryString(NSURLGetCFURL(self), NULL));
}

- (nullable NSString *)fragment {
    return NSURLCopyComponent(CFURLCopyFragment(NSURLGetCFURL(self), NULL));
}

- (nullable NSString *)parameterString {
    return NSURLCopyComponent(CFURLCopyParameterString(NSURLGetCFURL(self), NULL));
}

- (nullable NSString *)resourceSpecifier {
    return NSURLCopyComponent(CFURLCopyResourceSpecifier(NSURLGetCFURL(self)));
}

- (NSArray *)pathComponents {
    /* Apple splits -path on "/", so a file URL has a leading empty
     * component for the leading slash; an http URL with no path yields a
     * single empty component. */
    NSString *path = self.path;
    if (path == nil) {
        return @[];
    }
    return [path componentsSeparatedByString:@"/"];
}

- (BOOL)isFileURL {
    NSString *scheme = self.scheme;
    if (scheme == nil) {
        return NO;
    }
    return [scheme isEqualToString:@"file"];
}

- (BOOL)hasDirectoryPath {
    return CFURLHasDirectoryPath(NSURLGetCFURL(self)) ? YES : NO;
}

/* ---------------------------------------------------------------- */
/* Deriving URLs by editing the path                                 */
/* ---------------------------------------------------------------- */

- (NSURL *)URLByAppendingPathComponent:(NSString *)pathComponent {
    return [self URLByAppendingPathComponent:pathComponent isDirectory:NO];
}

- (NSURL *)URLByAppendingPathComponent:(NSString *)pathComponent
                           isDirectory:(BOOL)isDirectory {
    return NSURLTransferCFURL(CFURLCreateCopyAppendingPathComponent(
        kCFAllocatorDefault,
        NSURLGetCFURL(self),
        (__bridge CFStringRef)pathComponent,
        isDirectory ? true : false));
}

- (NSURL *)URLByAppendingPathExtension:(NSString *)pathExtension {
    return NSURLTransferCFURL(CFURLCreateCopyAppendingPathExtension(
        kCFAllocatorDefault,
        NSURLGetCFURL(self),
        (__bridge CFStringRef)pathExtension));
}

- (NSURL *)URLByDeletingLastPathComponent {
    return NSURLTransferCFURL(CFURLCreateCopyDeletingLastPathComponent(
        kCFAllocatorDefault, NSURLGetCFURL(self)));
}

- (NSURL *)URLByDeletingPathExtension {
    return NSURLTransferCFURL(CFURLCreateCopyDeletingPathExtension(
        kCFAllocatorDefault, NSURLGetCFURL(self)));
}

/* Collapse "." and "x/.." segments in a POSIX path.  "/.." keeps a trailing
 * ".." because there is nothing above the root to cancel it -- matching
 * Apple, whose -URLByStandardizingPath leaves "/a/b" alone and turns
 * "/a/x/../y" into "/a/y". */
static NSString *_Nullable NSURLStandardizePathString(NSString *path, BOOL *outIsDirectory) {
    NSUInteger length = path.length;
    if (length == 0) {
        return nil;
    }
    BOOL isDirectory = [path hasSuffix:@"/"];
    NSMutableArray<NSString *> *out = [NSMutableArray array];

    for (NSString *component in [path componentsSeparatedByString:@"/"]) {
        if (component.length == 0 || [component isEqualToString:@"."]) {
            continue;
        }
        if ([component isEqualToString:@".."]) {
            NSString *last = out.lastObject;
            /* Only unwind a real name; a trailing ".." or the root stays. */
            if (last != nil && ![last isEqualToString:@".."]) {
                [out removeLastObject];
                continue;
            }
        }
        [out addObject:component];
    }

    NSMutableString *result = [NSMutableString string];
    for (NSString *component in out) {
        [result appendString:@"/"];
        [result appendString:component];
    }
    if (result.length == 0) {
        [result appendString:@"/"];
    } else if (isDirectory) {
        [result appendString:@"/"];
    }
    if (outIsDirectory != NULL) {
        *outIsDirectory = isDirectory;
    }
    return result;
}

- (NSURL *)URLByStandardizingPath {
    /* Apple only rewrites file URLs; an http URL is returned unchanged. */
    if (!self.isFileURL) {
        return self;
    }
    NSString *path = self.path;
    if (path == nil) {
        return self;
    }
    BOOL isDirectory = NO;
    NSString *standardized = NSURLStandardizePathString(path, &isDirectory);
    if (standardized == nil) {
        return self;
    }
    NSURL *result = [[NSURL alloc] initFileURLWithPath:standardized
                                          isDirectory:isDirectory];
    /* Preserve any query/fragment the original carried. */
    NSString *query = self.query;
    if (query != nil) {
        NSString *fragment = self.fragment;
        NSString *absolute = result.absoluteString;
        if (fragment != nil) {
            absolute = [absolute stringByAppendingFormat:@"?%@#%@", query, fragment];
        } else {
            absolute = [absolute stringByAppendingFormat:@"?%@", query];
        }
        return [NSURL URLWithString:absolute];
    }
    return result;
}

/* Convert a path string to a NUL-terminated UTF-8 C string using
 * malloc'd storage.  The port does not yet carry NSString's
 * -fileSystemRepresentation, so go through CFString directly.  Returns
 * NULL if the string cannot be represented as UTF-8. */
static char *NSURLCreateFileSystemRepresentation(NSString *path) {
    CFStringRef cfPath = (__bridge CFStringRef)path;
    CFIndex maxLength = CFStringGetMaximumSizeForEncoding(CFStringGetLength(cfPath),
                                                          kCFStringEncodingUTF8) + 1;
    char *buffer = malloc((size_t)maxLength);
    if (buffer == NULL) {
        return NULL;
    }
    if (!CFStringGetCString(cfPath, buffer, maxLength, kCFStringEncodingUTF8)) {
        free(buffer);
        return NULL;
    }
    return buffer;
}

- (NSURL *)URLByResolvingSymlinksInPath {
    if (!self.isFileURL) {
        return self;
    }
    NSString *path = self.path;
    if (path == nil) {
        return self;
    }
    char *cPath = NSURLCreateFileSystemRepresentation(path);
    if (cPath == NULL) {
        return self;
    }
    char resolved[PATH_MAX];
    if (realpath(cPath, resolved) == NULL) {
        free(cPath);
        return self;
    }
    free(cPath);
    BOOL isDirectory = [path hasSuffix:@"/"];
    return [[NSURL alloc] initFileURLWithPath:[NSString stringWithUTF8String:resolved]
                                  isDirectory:isDirectory];
}

/* ---------------------------------------------------------------- */
/* Representations                                                  */
/* ---------------------------------------------------------------- */

/* Associated-object key holding the malloc'd UTF-8 buffer handed out by
 * -fileSystemRepresentation.  Apple returns a pointer the caller must not
 * free and that stays valid for the URL's lifetime, so the buffer is
 * cached on the URL and released when the URL is deallocated rather than
 * leaked per call. */
static const void *NSURLFileSystemRepresentationKey = &NSURLFileSystemRepresentationKey;

- (nullable const char *)fileSystemRepresentation {
    NSData *cached = objc_getAssociatedObject(self, NSURLFileSystemRepresentationKey);
    if (cached != nil) {
        return cached.bytes;
    }

    NSString *path = self.path;
    if (path == nil) {
        return NULL;
    }
    char *buffer = NSURLCreateFileSystemRepresentation(path);
    if (buffer == NULL) {
        return NULL;
    }
    /* Hand the bytes to an NSData so ARC owns the storage: the pointer we
     * return stays valid for the URL's lifetime, as Apple promises, and is
     * freed exactly once when the URL is deallocated. */
    NSData *storage = [NSData dataWithBytes:buffer
                                    length:strlen(buffer) + 1];
    free(buffer);
    if (storage == nil) {
        return NULL;
    }
    objc_setAssociatedObject(self,
                             NSURLFileSystemRepresentationKey,
                             storage,
                             OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    return storage.bytes;
}

- (BOOL)getFileSystemRepresentation:(char *)buffer
                         maxLength:(NSUInteger)maxBufferLength {
    const char *rep = self.fileSystemRepresentation;
    if (rep == NULL) {
        return NO;
    }
    size_t needed = strlen(rep) + 1;
    if (buffer == NULL || maxBufferLength < needed) {
        return NO;
    }
    memcpy(buffer, rep, needed);
    return YES;
}

- (NSData *)dataRepresentation {
    CFURLRef url = NSURLGetCFURL(self);
    CFIndex needed = CFURLGetBytes(url, NULL, 0);
    if (needed < 0) {
        return nil;
    }
    UInt8 stackBuffer[256];
    UInt8 *bytes = (needed <= (CFIndex)sizeof(stackBuffer))
        ? stackBuffer
        : malloc((size_t)needed);
    if (bytes == NULL) {
        return nil;
    }
    CFIndex written = CFURLGetBytes(url, bytes, needed);
    if (written < 0) {
        if (bytes != stackBuffer) {
            free(bytes);
        }
        return nil;
    }
    NSData *data = [NSData dataWithBytes:bytes length:(NSUInteger)written];
    if (bytes != stackBuffer) {
        free(bytes);
    }
    return data;
}

/* ---------------------------------------------------------------- */
/* Resource values                                                   */
/* ---------------------------------------------------------------- */

/* Map a Foundation resource key onto the CFURL/CFURLFileProperties key of
 * the same name.  Apple shares one string per key, and the names line up
 * ("NSURLIsDirectoryKey" is both).  NSURLPathKey is spelled "_NSURLPathKey"
 * in CF; NSURLPathKeyPrivate holds that spelling. */
static NSString *_Nullable NSURLCFPropertyKeyForKey(NSString *key) {
    if ([key isEqualToString:NSURLPathKey]) {
        return NSURLPathKeyPrivate;
    }
    return key;
}

- (BOOL)getResourceValue:(out id _Nullable * _Nonnull)value
                  forKey:(NSString *)key
                   error:(out NSError ** _Nullable)error {
    if (value != NULL) {
        *value = nil;
    }
    if (key == nil) {
        return NO;
    }

    /* Only the keys that map onto a CFURL property are answered; volume and
     * package keys need filesystem calls CFURL does not make. */
    NSString *propertyKey = NSURLCFPropertyKeyForKey(key);
    CFTypeRef property = NULL;
    if (!CFURLCopyResourcePropertyForKey(NSURLGetCFURL(self),
                                         (__bridge CFStringRef)propertyKey,
                                         &property,
                                         NULL)) {
        return NO;
    }
    if (property == NULL) {
        /* The key is valid but the resource has no such value. */
        return NO;
    }
    if (value != NULL) {
        *value = CFBridgingRelease(property);
    } else {
        CFRelease(property);
    }
    return YES;
}

- (nullable NSDictionary *)resourceValuesForKeys:(NSArray *)keys
                                           error:(out NSError ** _Nullable)error {
    /* CFURL answers the whole set in one call and reports the keys it could
     * not resolve by simply omitting them, which is what Apple documents. */
    NSMutableArray *cfKeys = [NSMutableArray arrayWithCapacity:keys.count];
    for (NSString *key in keys) {
        [cfKeys addObject:NSURLCFPropertyKeyForKey(key)];
    }
    CFDictionaryRef properties = CFURLCopyResourcePropertiesForKeys(
        NSURLGetCFURL(self),
        (__bridge CFArrayRef)cfKeys,
        NULL);
    if (properties == NULL) {
        return nil;
    }
    NSDictionary *result = CFBridgingRelease(properties);

    /* Hand the caller back Apple's spelling for any key we had to rewrite
     * (NSURLPathKey is stored as _NSURLPathKey). */
    if (![result isEqualToDictionary:(NSDictionary *)keys] &&
        [keys containsObject:NSURLPathKey] && result[NSURLPathKeyPrivate] != nil) {
        NSMutableDictionary *renamed = [result mutableCopy];
        renamed[NSURLPathKey] = result[NSURLPathKeyPrivate];
        [renamed removeObjectForKey:NSURLPathKeyPrivate];
        return renamed;
    }
    return result;
}

- (BOOL)checkResourceIsReachableAndReturnError:(out NSError ** _Nullable)error {
    /* Reachable means "the URL resolves to something on this system"; for a
     * file URL that is a stat of the path. */
    if (!self.isFileURL) {
        return YES;
    }
    const char *cPath = self.fileSystemRepresentation;
    if (cPath == NULL) {
        return NO;
    }
    struct stat st;
    if (stat(cPath, &st) != 0) {
        return NO;
    }
    return YES;
}

- (nullable NSURL *)fileReferenceURL {
    /* Apple's file reference URLs encode the volume id and file id as
     * "file:///.file/id=<volume>.<inode>".  Building it needs the file id
     * APIs, which this port does not carry yet; report "unsupported" the
     * same way an unavailable resource value is reported. */
    return nil;
}

/* ---------------------------------------------------------------- */
/* Security scope                                                   */
/* ---------------------------------------------------------------- */

- (BOOL)startAccessingSecurityScopedResource {
    return YES;
}

- (void)stopAccessingSecurityScopedResource {
}

/* ---------------------------------------------------------------- */
/* Bookmarks                                                        */
/* ---------------------------------------------------------------- */

/* A bookmark is stored as the URL's absolute string prefixed by a magic
 * header, so -URLByResolvingBookmarkData: can tell our blobs apart from
 * anything else and can reject foreign data instead of guessing. */
static const char NSURLBookmarkMagic[] = "PDURLBK1";

- (nullable NSData *)bookmarkDataWithOptions:(NSURLBookmarkCreationOptions)options
                     includingResourceValuesForKeys:(nullable NSArray *)keys
                                      relativeToURL:(nullable NSURL *)relativeToURL
                                              error:(out NSError ** _Nullable)error {
    NSString *absolute = self.absoluteURL.absoluteString;
    NSMutableData *data = [NSMutableData data];
    [data appendBytes:NSURLBookmarkMagic length:sizeof(NSURLBookmarkMagic) - 1];
    [data appendBytes:absolute.UTF8String length:absolute.length];
    return data;
}

+ (nullable NSURL *)URLByResolvingBookmarkData:(NSData *)data
                                        options:(NSURLBookmarkResolutionOptions)options
                          relativeToURL:(nullable NSURL *)relativeToURL
                                  bookmarkDataIsStale:(nullable BOOL *)isStale
                                            error:(out NSError ** _Nullable)error {
    if (isStale != NULL) {
        *isStale = NO;
    }
    NSUInteger magicLength = sizeof(NSURLBookmarkMagic) - 1;
    if (data.length <= magicLength ||
        memcmp(data.bytes, NSURLBookmarkMagic, magicLength) != 0) {
        return nil;
    }
    NSString *absolute = [[NSString alloc] initWithBytes:(const char *)data.bytes + magicLength
                                                  length:data.length - magicLength
                                                encoding:NSUTF8StringEncoding];
    if (absolute == nil) {
        return nil;
    }
    return [NSURL URLWithString:absolute relativeToURL:relativeToURL];
}

@end

#if DEPLOYMENT_RUNTIME_OBJC
__attribute__((constructor))
static void __NSCFURLBridgeInit(void) {
    _CFRuntimeBridgeClasses(CFURLGetTypeID(), "NSURL");
}
#endif