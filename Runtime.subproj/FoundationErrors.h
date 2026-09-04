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

/* NSCocoaErrorDomain codes.  Only the archiving range is filled in so far;
 * the file, formatting, validation and property list ranges belong here too
 * and keep the numbers Apple gave them. */
enum {
    NSCoderReadCorruptError = 4864,
    NSCoderValueNotFoundError = 4865,
    NSCoderInvalidValueError = 4866,
    NSCoderErrorMinimum = 4864,
    NSCoderErrorMaximum = 4991,
};

#endif /* FoundationErrors_h */
