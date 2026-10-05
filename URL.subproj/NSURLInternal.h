/*
 * Copyright (C) 2026, LibreDarwin.
 *
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */

/* Not in the umbrella: this is the cross-subproject view of the CFURL that
 * an NSURL owns.  NSURL is an owning wrapper rather than toll-free with
 * CFURL (see the comment above NSURLBacking in NSURL.m), so callers that
 * need a CFURLRef must unwrap instead of casting. */

#ifndef NSURLInternal_h
#define NSURLInternal_h

#import <Foundation/NSURL.h>
#include <CoreFoundation/CFURL.h>

/* The CFURL an NSURL owns, or NULL if the receiver is nil or was not made
 * by this port.  Borrowed: the NSURL keeps ownership. */
CFURLRef _Nullable NSURLBackingCFURL(NSURL *_Nullable url);

#endif /* NSURLInternal_h */