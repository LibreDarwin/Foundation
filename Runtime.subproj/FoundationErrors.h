/*
 * Copyright (C) 2026, Samuel Zormeister.
 *
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */

#ifndef FoundationErrors_h
#define FoundationErrors_h

#import <Foundation/NSObjCRuntime.h>

/* NSCocoaErrorDomain codes.  Only the archiving and property list ranges are
 * filled in so far; the file, formatting, and validation ranges belong here
 * too and keep the numbers Apple gave them.  The property list codes are what
 * NSJSONSerialization reports for malformed data and invalid objects. */
enum {
    NSCoderReadCorruptError = 4864,
    NSCoderValueNotFoundError = 4865,
    NSCoderInvalidValueError = 4866,
    NSCoderErrorMinimum = 4864,
    NSCoderReadIncompatibleArchiveError = 4865,
    NSCoderReadIncompatiblePointerError = 4866,
    NSCoderReadInvalidArrayLengthError = 4867,
    NSCoderReadUnknownTypeError = 4868,
    NSCoderWriteInsufficientMemoryError = 4869,
    NSCoderErrorMaximum = 4991,
};

enum {
    NSPropertyListReadCorruptError = 3840,
    NSPropertyListReadUnknownVersionError = 3841,
    NSPropertyListReadStreamError = 3842,
    NSPropertyListWriteStreamError = 3851,
    NSPropertyListWriteInvalidError = 3852,
    NSPropertyListWriteUnknownVersionError = 3853,
};

/* Formatting error range (NSCocoaErrorDomain). */
enum {
    NSFormattingError = 2048,
};

#endif /* FoundationErrors_h */
