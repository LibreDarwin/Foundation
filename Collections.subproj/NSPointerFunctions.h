/*
 * Copyright (C) 2026, PureDarwin Project.
 *
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 *
 * This header mirrors Apple's NSPointerFunctions.h byte-for-byte.
 */

#import <Foundation/NSObject.h>

#if !defined(__FOUNDATION_NSPOINTERFUNCTIONS__)
#define __FOUNDATION_NSPOINTERFUNCTIONS__ 1

NS_HEADER_AUDIT_BEGIN(nullability, sendability)

/*

  NSPointerFunctions

  This object defines callout functions appropriate for managing a pointer reference held somewhere else.

  Used by NSHashTable, NSMapTable, and NSPointerArray, this object defines the acquision and retention behavior for the pointers provided to these collection objects.

   The functions are separated into two clusters - those that define "personality", such as object or cString, and those that describe memory management issues such as a memory deallocation function.  Common personalities and memory manager selections are provided as enumerations, and further customization is provided by methods such that the composition of the actual list of functions is done opaquely such that they can be extended in the future.

  The pointer collections copy NSPointerFunctions objects on input and output, and so NSPointerFunctions is not usefully subclassed.

*/


typedef NS_OPTIONS(NSUInteger, NSPointerFunctionsOptions) {
    // Memory options are mutually exclusive

    // default is strong
    NSPointerFunctionsStrongMemory = (0UL << 0),       // use strong write-barrier to backing store; use GC memory on copyIn
    NSPointerFunctionsZeroingWeakMemory = (1UL << 0),  // deprecated; uses GC weak read and write barriers, and dangling pointer behavior otherwise
    NSPointerFunctionsOpaqueMemory = (2UL << 0),       // use specialized malloc and free
    NSPointerFunctionsMallocMemory = (3UL << 0),       // use malloc and free
    NSPointerFunctionsMachVirtualMemory = (4UL << 0),  // use Mach virtual memory protection and copying
    NSPointerFunctionsWeakMemory = (5UL << 0),         // use weak read and write barriers appropriate for ARC

    // Personalities are mutually exclusive
    // default is object.  As a special case, 'strong' memory used for Objects will do retain/release under non-GC
    NSPointerFunctionsObjectPersonality = (0UL << 8),         // use -hash and -isEqual, object description
    NSPointerFunctionsOpaquePersonality = (1UL << 8),         // use shifted pointer hash and direct equality
    NSPointerFunctionsObjectPointerPersonality = (2UL << 8),  // use shifted pointer hash and direct equality, object description
    NSPointerFunctionsCStringPersonality = (3UL << 8),        // use a string hash and strcmp, description assumes UTF-8 contents; recommended for UTF-8 (or ASCII, which is a subset) only cstrings
    NSPointerFunctionsStructPersonality = (4UL << 8),         // use a memory hash and memcmp (using size function you must set)
    NSPointerFunctionsIntegerPersonality = (5UL << 8),        // use unshifted value as hash & equality

    NSPointerFunctionsCopyIn = (1UL << 16),          // the memory acquire function will be asked to allocate and copy items on input
};

API_AVAILABLE(macos(10.5), ios(6.0), watchos(2.0), tvos(9.0))
@interface NSPointerFunctions : NSObject <NSCopying>
// construction
- (instancetype)initWithOptions:(NSPointerFunctionsOptions)options NS_DESIGNATED_INITIALIZER;
+ (NSPointerFunctions *)pointerFunctionsWithOptions:(NSPointerFunctionsOptions)options;

// pointer personality functions
@property (nullable) NSUInteger (*hashFunction)(const void *item, NSUInteger (* _Nullable size)(const void *item));
@property (nullable) BOOL (*isEqualFunction)(const void *item1, const void *item2, NSUInteger (* _Nullable size)(const void *item));
@property (nullable) NSUInteger (*sizeFunction)(const void *item);
@property (nullable) NSString * _Nullable (*descriptionFunction)(const void *item);

// custom memory management
@property (nullable) void (*relinquishFunction)(const void *item, NSUInteger (* _Nullable size)(const void *item));
@property (nullable) void * _Nonnull (*acquireFunction)(const void *src, NSUInteger (* _Nullable size)(const void *item), BOOL shouldCopy);

// GC used to require that read and write barriers be used when pointers are from GC memory
@property BOOL usesStrongWriteBarrier API_DEPRECATED("Garbage collection no longer supported", macosx(10.5, 10.8), ios(2.0, 10.0), watchos(2.0, 3.0), tvos(9.0, 10.0));

@property BOOL usesWeakReadAndWriteBarriers API_DEPRECATED("Garbage collection no longer supported", macosx(10.5, 10.8), ios(2.0, 10.0), watchos(2.0, 3.0), tvos(9.0, 10.0));

@end

/*
   Cheat Sheet

   Long Integers (other than zero)   (NSPointerFunctionsOpaqueMemory | NSPointerFunctionsIntegerPersonality)
      useful for, well, anything that can be jammed into a long int

   Strongly held objects             (NSPointerFunctionsStrongMemory | NSPointerFunctionsObjectPersonality)
      used for retained objects under ARC and/or manual retain-release, or GC; uses isEqual: as necessary

   Zeroing weak object references    (NSPointerFunctionsZeroingWeakMemory   | NSPointerFunctionsObjectPersonality)
      used to hold references that won't keep the object alive.  Note that objects implementing custom retain-release must also implement allowsWeakReference and retainWeakReference (or are using GC instead)

   Unsafe unretained objects         (NSPointerFunctionsOpaqueMemory | NSPointerFunctionsObjectPersonality)
      used where zeroing weak is not possible and where, somehow, the objects are removed before being deallocated.

   C String where table keeps copy   (NSPointerFunctionsStrongMemory | NSPointerFunctionsCStringPersonality | NSPointerFunctionsCopyIn)
      used to capture a null-terminated string from a source with unknown lifetime.  Keeps string alive under GC.  Under ARC/RR, table will deallocate its copy when removed.  Generally, "C Strings" is a term for UTF8 strings as well.

   C String, owned elsewhere         (NSPointerFunctionsOpaqueMemory | NSPointerFunctionsCStringPersonality)
      used to hold C string pointers to storage not at all managed by the table.


   The NSPointerFunctionsObjectPersonality dictates using isEqual: for the equality test.  In some situations == should be used, such as when trying to build a cache of unique immutable "value" objects that implement isEqual:.  In those cases use NSPointerFunctionsObjectPointerPersonality instead.
*/

NS_HEADER_AUDIT_END(nullability, sendability)
#endif // defined __FOUNDATION_NSPOINTERFUNCTIONS__
