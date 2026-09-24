/*
 * Copyright (C) 2026, Samuel Zormeister.
 *
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */

#if !defined(__FOUNDATION_NSOBJCRUNTIME__)
#define __FOUNDATION_NSOBJCRUNTIME__ 1

#include <objc/NSObjCRuntime.h>
#include <stdarg.h>
#include <stdint.h>
#include <limits.h>

#ifndef NS_INLINE
    #define NS_INLINE static __inline__ __attribute__((always_inline))
#endif

#ifndef NS_RETURNS_INNER_POINTER
    #define NS_RETURNS_INNER_POINTER __attribute__((objc_returns_inner_pointer))
#endif

#ifndef NS_REQUIRES_SUPER
    #define NS_REQUIRES_SUPER __attribute__((objc_requires_super))
#endif

#ifndef NS_DESIGNATED_INITIALIZER
    #define NS_DESIGNATED_INITIALIZER __attribute__((objc_designated_initializer))
#endif

/* Ownership annotations: a +1 return from a method whose name does not begin
 * with alloc/new/copy, and the reverse. */
#ifndef NS_RETURNS_RETAINED
    #define NS_RETURNS_RETAINED __attribute__((ns_returns_retained))
#endif
#ifndef NS_RETURNS_NOT_RETAINED
    #define NS_RETURNS_NOT_RETAINED __attribute__((ns_returns_not_retained))
#endif
#ifndef NS_CONSUMED
    #define NS_CONSUMED __attribute__((ns_consumed))
#endif
#ifndef NS_CONSUMES_SELF
    #define NS_CONSUMES_SELF __attribute__((ns_consumes_self))
#endif

#ifndef NS_NOESCAPE
    #define NS_NOESCAPE __attribute__((noescape))
#endif

/* Format-attribute macros: NSString.text-style format checking. */
#ifndef NS_FORMAT_FUNCTION
    #define NS_FORMAT_FUNCTION(F, A) __attribute__((format(__NSString__, F, A)))
#endif
#ifndef NS_FORMAT_ARGUMENT
    #define NS_FORMAT_ARGUMENT(A) __attribute__((format_arg(A)))
#endif

/* Swift interop: what the Swift importer hides outright, and what it renames
 * with a leading underscore so an overlay can present it properly. */
#ifndef NS_SWIFT_UNAVAILABLE
    #define NS_SWIFT_UNAVAILABLE(_msg) __attribute__((availability(swift, unavailable, message=_msg)))
#endif

#ifndef NS_REFINED_FOR_SWIFT
    #define NS_REFINED_FOR_SWIFT __attribute__((swift_private))
#endif

/* Zone and retain-count plumbing that ARC does not let anyone call. */
#ifndef NS_AUTOMATED_REFCOUNT_UNAVAILABLE
    #if __has_feature(objc_arc)
        #define NS_AUTOMATED_REFCOUNT_UNAVAILABLE \
            __attribute__((unavailable("not available in automatic reference counting mode")))
    #else
        #define NS_AUTOMATED_REFCOUNT_UNAVAILABLE
    #endif
#endif

typedef struct _NSZone NSZone;

#ifndef __has_attribute
    #define __has_attribute(x) 0
#endif

#ifndef __has_builtin
    #define __has_builtin(x) 0
#endif

#ifndef __has_feature
    #define __has_feature(x) 0
#endif

/*
 * XX_ENUM & XX_OPTIONS macros, courtesy of CoreFoundation
 */
#include <CoreFoundation/CFAvailability.h>

/* The LibreDarwin CFAvailability.h drop predates several macros the SDK's
 * patched copy adds back (CF_CLOSED_ENUM, CF_STRING_ENUM and the _CF_TYPED_
 * family).  Define them here under guards so the file works against either
 * tree instead of relying on that patch. */
#ifndef CF_CLOSED_ENUM
    #ifndef __CF_CLOSED_ENUM_ATTRIBUTES
        #if __has_attribute(enum_extensibility)
            #define __CF_CLOSED_ENUM_ATTRIBUTES __attribute__((enum_extensibility(closed)))
        #else
            #define __CF_CLOSED_ENUM_ATTRIBUTES
        #endif
    #endif
    #if (__cplusplus && (__has_extension(cxx_strong_enums) || __has_feature(objc_fixed_enum))) || \
        (!__cplusplus && __has_feature(objc_fixed_enum))
        #define CF_CLOSED_ENUM(_type, _name) \
            enum __CF_CLOSED_ENUM_ATTRIBUTES _name : _type _name; enum _name : _type
    #else
        #define CF_CLOSED_ENUM(_type, _name) _type _name; enum
    #endif
#endif

#ifndef CF_STRING_ENUM
    #if __has_attribute(swift_wrapper)
        #define CF_STRING_ENUM              __attribute__((swift_wrapper(enum)))
        #define CF_EXTENSIBLE_STRING_ENUM   __attribute__((swift_wrapper(struct)))
    #else
        #define CF_STRING_ENUM
        #define CF_EXTENSIBLE_STRING_ENUM
    #endif
    #define CF_TYPED_ENUM               CF_STRING_ENUM
    #define CF_TYPED_EXTENSIBLE_ENUM    CF_EXTENSIBLE_STRING_ENUM
    #define _CF_TYPED_ENUM              CF_STRING_ENUM
    #define _CF_TYPED_EXTENSIBLE_ENUM   CF_EXTENSIBLE_STRING_ENUM
#endif

#define _NS_TYPED_ENUM              _CF_TYPED_ENUM
#define _NS_TYPED_EXTENSIBLE_ENUM   _CF_TYPED_EXTENSIBLE_ENUM

#define NS_ENUM(...)                CF_ENUM(__VA_ARGS__)
#define NS_OPTIONS(type, name)      CF_OPTIONS(type, name)
#define NS_CLOSED_ENUM(type, name)  CF_CLOSED_ENUM(type, name)
#define NS_TYPED_ENUM               _NS_TYPED_ENUM
#define NS_TYPED_EXTENSIBLE_ENUM    _NS_TYPED_EXTENSIBLE_ENUM
#define NS_STRING_ENUM              _NS_TYPED_ENUM
#define NS_EXTENSIBLE_STRING_ENUM   _NS_TYPED_EXTENSIBLE_ENUM

/*
 * Bridging a CoreFoundation type to an Objective-C class
 *
 * The Objective-C deployment of CoreFoundation keeps a table from CF type ID to
 * Objective-C class. The class registered against a type ID is the class that
 * instances of that type are given when they cross into Objective-C, and
 * CoreFoundation then goes on treating such an instance as a CF type rather than
 * dispatching Objective-C messages to it. It is how NSDate, NSDictionary,
 * NSCFString and the rest are CF objects with an Objective-C surface.
 *
 * CoreFoundation exports the entry point but declares it nowhere - not in the
 * SDK, not in the sources in this tree - so it is declared here, once, for the
 * initializers that call it. It is CoreFoundation's symbol and not Foundation's:
 * no FOUNDATION_EXPORT, no implementation here, and the callers gate their calls
 * on DEPLOYMENT_RUNTIME_OBJC, the deployment that has a class table at all.
 */
#include <CoreFoundation/CFBase.h>

extern void _CFRuntimeBridgeClasses(CFTypeID typeID, const char *className);



/*
 * While we're here...
 *
 * We really don't care about availability. If it's there it's there. If it isn't; well damn.
 */
#define NS_AVAILABLE(...)
#define NS_AVAILABLE_MAC(...)
#define NS_AVAILABLE_IOS(...)

#define NS_DEPRECATED(...)
#define NS_DEPRECATED_MAC(...)
#define NS_DEPRECATED_IOS(...)

#define NS_ENUM_AVAILABLE(...)
#define NS_ENUM_AVAILABLE_MAC(...)
#define NS_ENUM_AVAILABLE_IOS(...)

#define NS_ENUM_DEPRECATED(...)
#define NS_ENUM_DEPRECATED_MAC(...)
#define NS_ENUM_DEPRECATED_IOS(...)

#ifndef FOUNDATION_EXPORT
    #ifdef __cplusplus
        #define FOUNDATION_EXPORT extern "C"
    #else
        #define FOUNDATION_EXPORT extern
    #endif
#endif

/* NULLability audit regions.  Apple's headers bracket their interfaces
 * with NS_HEADER_AUDIT_BEGIN/END, which expand to assume_nonnull pragmas.
 * Ported headers that mirror Apple's shape use them, so provide them here. */
#ifndef NS_ASSUME_NONNULL_BEGIN
    #define NS_ASSUME_NONNULL_BEGIN _Pragma("clang assume_nonnull begin")
#endif
#ifndef NS_ASSUME_NONNULL_END
    #define NS_ASSUME_NONNULL_END _Pragma("clang assume_nonnull end")
#endif
#ifndef NS_HEADER_AUDIT_BEGIN
    #define NS_HEADER_AUDIT_BEGIN(...) NS_ASSUME_NONNULL_BEGIN
#endif
#ifndef NS_HEADER_AUDIT_END
    #define NS_HEADER_AUDIT_END(...) NS_ASSUME_NONNULL_END
#endif

/* API availability annotations, no-op'd to match the file's stance. */
#ifndef API_AVAILABLE
    #define API_AVAILABLE(...)
#endif
#ifndef API_DEPRECATED
    #define API_DEPRECATED(...)
#endif
#ifndef API_UNAVAILABLE
    #define API_UNAVAILABLE(...)
#endif

#ifndef FOUNDATION_EXTERN
    #define FOUNDATION_EXTERN FOUNDATION_EXPORT
#endif

typedef NS_CLOSED_ENUM(NSInteger, NSComparisonResult) {
    NSOrderedAscending = -1,
    NSOrderedSame = 0,
    NSOrderedDescending = 1,
};

typedef NSComparisonResult (^NSComparator)(id _Nonnull obj1, id _Nonnull obj2);

typedef NS_OPTIONS(NSUInteger, NSSortOptions) {
    NSSortConcurrent = (1UL << 0),
    NSSortStable = (1UL << 4),
};

typedef NS_OPTIONS(NSUInteger, NSEnumerationOptions) {
    NSEnumerationConcurrent = (1UL << 0),
    NSEnumerationReverse = (1UL << 1),
};

enum { NSNotFound = NSIntegerMax };

/* Apple's NSObjCRuntime.h defines these, and ported ObjC code relies on
 * getting them from Foundation rather than from a system header. */
#if !defined(MIN)
    #define MIN(A, B) __NSMinOrMax(A, B, <)
#endif
#if !defined(MAX)
    #define MAX(A, B) __NSMinOrMax(A, B, >)
#endif
#if !defined(ABS)
    #define ABS(A) ({ __typeof__(A) __a = (A); __a < 0 ? -__a : __a; })
#endif

#define __NSMinOrMax(A, B, OP) ({ \
    __typeof__(A) __a = (A); \
    __typeof__(B) __b = (B); \
    __a OP __b ? __a : __b; \
})

@class NSString;

void NSLog(NSString *format, ...) __attribute__((format(__NSString__, 1, 2)));
void NSLogv(NSString *format, va_list args) __attribute__((format(__NSString__, 1, 0)));

FOUNDATION_EXPORT NSString *NSStringFromSelector(SEL selector);
FOUNDATION_EXPORT SEL NSSelectorFromString(NSString *name);
FOUNDATION_EXPORT NSString *NSStringFromClass(Class aClass);
FOUNDATION_EXPORT Class NSClassFromString(NSString *name);
FOUNDATION_EXPORT NSString *NSStringFromProtocol(Protocol *protocol);
FOUNDATION_EXPORT Protocol *NSProtocolFromString(NSString *name);

FOUNDATION_EXPORT const char *NSGetSizeAndAlignment(const char *typePtr,
                                                    NSUInteger *sizep,
                                                    NSUInteger *alignp);

#endif /* ! __FOUNDATION_NSOBJCRUNTIME__ */
