# LibreDarwin Foundation.framework

Open source reimplementation of Apple's **Foundation.framework**, written for
the LibreDarwin project's Darwin-based open source OS.

## What this is

The goal is a Foundation whose behavior is **byte-identical to Apple's**, so it
works both as a drop-in replacement for the Internal SDK's Foundation and as
the default Foundation for LibreDarwin's own Darwin-based OS. The framework is
built as a real `Foundation.framework` bundle (dylib + headers + Info.plist)
against the LibreDarwin Internal SDK, and may be built against Apple's macOS SDK
for development (`make RN=...`).

Implementation notes:

- **Language.** Objective-C, ARC by default. A short list of sources (`MRC_SOURCES`
  in `Common.mk`) is compiled with `-fno-objc-arc`.
- **Toll-free bridging.** Most collection, string, date, and locale classes are
  CF-toll-free or thin owning wrappers over CoreFoundation, exactly as Apple
  does. The vendored LibreDarwin CF headers live in `local/include/` (gitignored)
  and take precedence so the LibreDarwin CF tree wins. Because that tree is
  gitignored it has to be repopulated by hand on a fresh clone;
  `CFAttributedString.h` is required by `String.subproj/NSAttributedString.m` and
  is not otherwise present in it.
- **License.** Mozilla Public License 2.0 (see `LICENSE`). Ports carry their
  provenance in the file header copyright line — PureDarwin Project, Cocotron,
  ravynOS, LibreDarwin, or original authors.
- **Reverse engineering.** Apple's real Foundation binary and its disassembly are
  kept under `local/disasm/` (`Foundation.dylib`, `Foundation.full.disasm`,
  `Foundation.symbols.txt`, `fns/`) as the reference ground truth.

Reference port sources (see `local/Foundation.md`): Cocotron Foundation, ravynOS
Foundation, and PureDarwin PureFoundation.

## Building and verifying

Three build front-ends all read the shared `Common.mk`:

| command                          | what it does                                          |
|----------------------------------|-------------------------------------------------------|
| `make` / `make release`          | release build (`-O2`) + verify                        |
| `make debug`                     | `-O0 -g -DDEBUG` build + verify                       |
| `make build`                     | build the framework bundle without verification       |
| `make verify`                    | pairing sweep + behavior gate                         |
| `make xcodeproj`                 | regenerate `Foundation.xcodeproj` from the source tree|

Output lands in `build/<CONFIG>/Foundation.framework`. The umbrella header is
generated into `build/gen/Foundation/Foundation.h` from the subprojects' own
headers.

### Verification machinery (Tests/)

- **Behavior gate** (`make behavior-gate`). The port's own `.m` sources are
  compiled **into** a test executable (not linked against the built dylib, since
  the dylib's toll-free classes would be shadowed by Apple's CoreFoundation on the
  host) and linked only against Apple's CoreFoundation. The executable runs
  1,567 deterministic, timezone-agnostic probes (`Tests/port_behavior.m`), and
  its output is diffed byte-for-byte against Apple's real Foundation output,
  captured in `Tests/port_behavior.golden`. New probe coverage requires adding the
  touched sources to `GATE_SRCS` in `Common.mk` and re-capturing the Apple truth.
- **Pairing sweep** (`make pairing-sweep`, `Tests/pairing_sweep.py`). Every
  selector declared in any header (55 headers, 976 selectors) must be
  implemented somewhere in the `.m` sources; 20 hand-verified selectors the
  mechanical scanner can't match are allowlisted.

## What has been implemented

Grouped by subproject (`.m` is present and the declared surface is implemented;
"partial" marks minimal/vocabulary-only surfaces pinned with fewer probes):

**Collections** — NSArray/NSMutableArray, NSData, NSDictionary/NSMutableDictionary,
NSSet/NSCountedSet/NSMutableSet, NSOrderedSet/NSMutableOrderedSet,
NSIndexSet/NSMutableIndexSet (sorted range-array), NSEnumerator (+ private
array enumerator), NSHashTable, NSMapTable, NSPointerFunctions.

**String** — NSString/NSMutableString (factories, encodings, compare options,
bounds, percent), NSCFString, NSCharacterSet, NSScanner (locale-aware
scanDouble/scanFloat, faithful scanHexDouble/scanHexFloat).

**Date** — NSDate, NSDateComponents (full era/quarter/dayOfYear/nanosecond
surface), NSTimeZone (from-scratch TZif-backed), NSCalendar (identifiers,
symbols, decomposition/difference/addition/range, dateBySetting*, the full
nextDateAfterDate:matching* family), NSDateFormatter *(partial)*,
NSISO8601DateFormatter.

**Numeric** — NSNumber, NSDecimal + NSDecimalNumber (39-digit mantissa, handler,
init-swap), NSNumberFormatter (CFNumberFormatter-backed, all style/parse bridges).

**Runtime** — NSObject, NSValue, NSNull (toll-free with CFNull), NSError,
NSException, NSZone, NSRange, NSGeometry, NSLog, NSProcessInfo, NSBundle,
NSUserDefaults, NSPropertyList, NSJSONSerialization, NSKeyValueCoding,
NSDebug, NSObjCRuntime, NSAutoreleasePool; `FoundationErrors.h`,
`Foundation.apinotes`.

**Serialization** — NSCoder, and the recently completed keyed-archive pair:
NSKeyedArchiver + NSKeyedUnarchiver (codec categories, encoding/substitution
pipeline, delegate hooks, `+unarchiveTopLevelObjectWithData:error:`).

**FileManager** — NSFileHandle, NSFileManager, NSPathUtilities, NSPipe, NSTask.

**Locale** — NSLocale (preferredLanguages, available/ISO lists, autoupdating).

**Text** — NSAttributedString / NSMutableAttributedString (attributes, effective
and longest-effective ranges, substrings, equality, block enumeration in both
directions, and the mutable attribute/edit surface; see the notes below).

**Lock / Notification / RunLoop / Thread / Sorting / Stream / URL** — NSLock,
NSRecursiveLock, NSCondition, NSConditionLock; NSNotification,
NSNotificationCenter; NSRunLoop, NSTimer; NSThread; NSSortDescriptor (key /
selector / comparator with evaluation lock); NSStream/NSInputStream/
NSOutputStream (CF-backed); NSURL *(partial)*.

**Swift overlay** — `Swift.subproj/Foundation.swiftinterface` declaring the
String/Array/Dictionary ↔ Foundation bridging conformances, backed by the
system binary's exports (the Swift counterpart of a `.tbd`).

**Stubs (declaration-only, no implementation yet)** — `NSXPCConnection.h`
(NSXPCInterface/NSXPCConnection/NSXPCProxyCreating names so headers compile).

## Current status and known issues

- **`NSException` ownership is now correct and raises no longer leak.**
  `Runtime.subproj/NSException.m` is built with `-fno-objc-arc` (it is listed in
  `MRC_GATE_PAT`), and it had no `-dealloc` while storing its three object ivars
  without retaining them, returned an un-autoreleased instance from
  `+exceptionWithName:reason:userInfo:`, and left the formatted reason strings
  owned by a leaked `+1`. The file now retains its ivars, releases them in
  `-dealloc`, and autoreleases the factory result and the strings it throws with.
  50,000 caught `+[NSException raise:format:]` calls are now flat (previously ~19 MB).
- **`-[NSException copyWithZone:]` returned `self` without retaining.** Returning
  the receiver is correct for an immutable exception, but the `copy` family must
  still return `+1`; callers that release the result over-released the original.
  This stayed invisible only because the class had no `-dealloc`, and became a
  release-only use-after-free (SIGSEGV at `-[NSException description]`) as soon as
  one was added. It now returns `[self retain]`.
- **Raising from `NSAttributedString`'s range and nil checks no longer leaks.**
  `NSAttributedStringCheckRange` and `NSAttributedStringCheckNotNil` raise out of
  an ARC file, and clang emits no cleanup landing pads for Objective-C exception
  unwinds in Objective-C sources, so the raising frame stranded everything ARC
  owned there: ~100 bytes per out-of-bounds raise from the retained receiver
  parameter, plus two `CFString`s per raise from the `NSStringFromClass` and
  `NSStringFromSelector` used to build the message. The helpers now borrow their
  object parameters (`__unsafe_unretained` — they only read them before raising,
  and a `__strong` parameter would retain on entry and schedule the release for a
  normal exit that a raise never reaches) and format the class and selector names
  from C strings with `%s` through `class_getName`/`sel_getName`, which the
  runtime owns outright and which produce byte-identical text. 50,000 caught
  raises now add 3 `CFString`s where they used to add 100,003, and a repeated
  25,000-iteration batch measures 0.0 bytes per iteration. Note that
  `NSStringFrom…` must *not* be used this way from ARC code: handing the
  autoreleased result straight to a format leaks it (ARC claims the autorelease
  and nothing releases), while an `__unsafe_unretained` local is use-after-free
  (ARC claims and immediately balances it, and the local is dangling when the
  format runs) — the second of which is a `SIGTRAP` in `__CF_IS_OBJC` reached
  from `__CFCopyFormattingDescription`. Separately, `NSStringFromClass` and its
  two siblings leaked ~12 bytes per call because they are built in an
  `-fno-objc-arc` file (`MRC_GATE_PAT`) and did not autorelease the `+1` from
  `CFStringCreateWithCString`; Cocoa documents all three as plain accessors
  returning autoreleased objects, so `Runtime.subproj/NSObjCRuntime.m` now does
  that.
- **Tree is green**: `make all` (build + pairing sweep + behavior gate) passes for
  both `release` and `debug` configurations. 970 selectors across 54 headers are
  declared and implemented.
- **Delegation protocols are handled**: the pairing sweep strips `@protocol`
  bodies and forward declarations (delegate methods are implemented by
  conformers, never by the framework itself) and allowlists
  `unarchiveTopLevelObjectWithData:error:`, whose `NS_SWIFT_UNAVAILABLE` on the
  `error:` parameter fools the flat selector matcher despite the implementation
  at `Serialization.subproj/NSKeyedUnarchiver.m:329`.
- `NSKeyedArchiver.m` / `NSKeyedUnarchiver.m` are in `GATE_SRCS`, so keyed-archive
  behavior is gate-pinned against Apple ground truth.
- **`NSAutoreleasePool` now ships** (`Runtime.subproj/NSAutoreleasePool.m`), and
  with it the last Apple-Foundation link dependency is gone. `otool -L` on the
  built dylib lists only the install name, `CoreFoundation`, `libobjc` and
  `libSystem`. The last symbol that bound to Apple's copy,
  `_OBJC_CLASS_$_NSAutoreleasePool` (a `__objc_classrefs` entry from clang's
  `@autoreleasepool` lowering), is now defined by the port itself. The actual
  culprit was `-fobjc-arc` on the *link* line, which makes the driver autolink
  Foundation; the `-fno-autolink` flag only removed the per-object options.
  Both are documented in `Common.mk`.
- The pool keeps the Apple 40-byte layout (`_token`, `_reserved3`, `_reserved2`,
  `_reserved`) and delegates to `objc_autoreleasePoolPush`/`Pop`, so
  `@autoreleasepool` in `NSThread`/`NSNotificationCenter` drains into it.
  Instance `-addObject:` uses a side table, because
  `objc_autoreleasePoolAddObject` is not exported. Debug selectors Apple keeps
  out of the SDK live in the non-umbrella `NSAutoreleasePoolInternal.h`.

## What's left

**Finish / gate the current slice**
- _The `NSURL` string parser slice is implemented and gate-pinned:_
  `NSURLEncodeIllegalCharacters` reproduces Apple's pre-CFURL parsing —
  percent-encoding of illegal characters, preservation of well-formed `%XX`
  escapes, IPv6 bracket literals in the authority, and the scheme/authority
  validation that makes `http://[`, `http://[]x/`, `//[a[b]/`, `http://a b/`
  and `1:2` nil. 29 probes in `Tests/port_behavior.golden` pin this._
- _`NSURL` owns its `CFURL` instead of bridging to it:_ CoreFoundation registers
  its own `NSURL` against the `CFURL` type while CF itself initializes, which is
  necessarily before this library's constructors, so a toll-free port `NSURL` lost
  every instance method to CoreFoundation's implementation — the port's
  `-path`, `-URLByStandardizingPath`, resource values and bookmarks were dead
  code in both the dylib and the gate. `NSURL` is now an owning wrapper (the
  `NSLocale`/`CFLocale` pattern) with its `CFURL` in an ivar, so
  `object_getClass(url) == [NSURL class]` holds and the instance-method probes
  finally exercise port code. Because it is a plain object again, it supplies its
  own value identity: `isEqual:`/`hash` compare the backing `CFURL`, and `-copy`
  returns the receiver, as Apple does for an immutable URL. 11 probes pin this.
- _`NSAttributedString` is an owning wrapper, for the same reason:_ CoreFoundation
  registers its own `NSAttributedString` against the `CFAttributedString` type
  before this library loads, so the port class holds a `CFAttributedString` in an
  ivar rather than bridging to it. Attributes need no conversion because the
  port's `NSString`/`NSDictionary` are themselves toll-free with `CFString`/
  `CFDictionary`.
  Three CF behaviours needed working around and are commented in
  `String.subproj/NSAttributedString.m`: `CFAttributedStringReplaceString`
  segfaults on a NULL replacement (deletion passes `CFSTR("")` instead), and
  `CFAttributedStringGetMutableString` returns NULL for these backings, so
  `-mutableString` is a proxy that forwards mutations to its owner the way
  Apple's `NSMutableStringProxyForMutableAttributedString` does. Note that
  CoreFoundation has no accessor for the shorter `-effectiveRange:`, so those
  methods report the longest effective range, searched over the whole string so
  a run can still extend backwards past the requested index. Like `NSURL`,
  `-copy` returns the receiver when the receiver is immutable. 59 probes pin this,
  covering the argument and range errors as well: Apple raises
  `NSInvalidArgumentException` for a nil string, nil replacement, nil attributed
  string, or nil attribute value, and `NSRangeException` for an out-of-bounds
  range — several of which CoreFoundation would crash or hang on, so the port
  validates before delegating. `-setAttributes:range:` is a *replacement*
  (`clearOtherAttributes` must be set, or CF merges instead), while
  `-addAttributes:range:` merges and `-setAttributes:nil` clears the range.
- _`NSAttributedString`/`NSMutableAttributedString` are now `NSSecureCoding`:_ the
  archive uses Apple's keyed shape — `NSString`, an `NSAttributes` array with one
  dictionary per attribute run (a bare run is an empty dictionary), and an
  `NSAttributeInfo` LEB128 `(runLength, attributeIndex)` blob that is omitted when
  there is at most one run, as Apple omits it. Encoding walks maximal runs and is
  linear; decoding validates the whole archive before adopting any CF backing, so a
  malformed archive cannot strand a half-built CF object (these sources do not use
  `-fobjc-arc-exceptions`). The decoder reads with `decodeObjectOfClass:`, and a
  foreign-writer proof is baked in: 12 probes decode a 682-byte archive captured
  from Apple's own archiver for the same string to the identical run layout.
  Two keyed-archiver gaps surfaced and were fixed: the archiver now always writes
  `NS.keys`/`NS.objects` for an empty dictionary and `NS.objects` for an empty set
  (Apple writes them even when empty, and Apple's reader requires them), and the
  unarchiver now materializes `NSData`/`NSMutableData` entries from their plist
  bytes — those classes are host toll-free in the gate, so no allocator exists.
  Secure decode still refuses an archive whose top-level class is not in the
  allowed set, including structural containers like a root `NSArray`, while nested
  containers stay ungated because they are rebuilt from plist leaves, never
  `initWithCoder:`. 12 probes pin all of this against Apple.
- _`NSTextAttachment` and the attachment conveniences:_ the class
  (`initWithData:ofType:` plus copy-semantics `contents`/`fileType`, surfaced from
  Foundation where Apple keeps it behind AppKit on UIFoundation), the
  `NSAttachmentCharacter` (0xFFFC) and `NSAttachmentAttributeName` ("NSAttachment")
  constants, and `+attributedStringWithAttachment:` (plus the `attributes:` variant,
  where the attachment argument wins over any value already under the key while the
  remaining attributes ride along). The archive matches Apple's keyed shape —
  `NS.contents` (plist data), `NS.fileType` (plist string) and an `NSFileWrapper`
  slot — and Apple's own `-initWithCoder:` ignores the file-wrapper node its writer
  emits (that node holds the RTFD serialization Apple's rich-text machinery builds
  at encode time), so the port encodes nil in that slot and Apple-made archives
  still decode, pinned by a baked-in 695-byte fixture from Apple's own archiver
  alongside the legacy and secure round trips. Apple's macOS 26 `-setFileType:`
  writes an unused slot, so a UTI assigned after init never comes back; the port
  deliberately does not reproduce that quirk. The AppKit-dependent surface —
  image, bounds, fileWrapper, cell, view provider, `NSTextAttachmentLayout` — is out
  of scope for a Foundation without AppKit. 14 probes pin all of this against Apple.

**Deepen partial classes**
- `NSURL`: file bookmarks and resource-value accessors are still approximate
  (`bookmarkDataWithOptions:` is a placeholder, `fileReferenceURL` returns nil,
  `getResourceValue:forKey:error:` only forwards to CFURL). `NSFileManager`/
  `NSFileHandle`/`NSPipe` (integration props), `NSBundle`, `NSUserDefaults`,
  `NSProcessInfo`, `NSStream` (schemes, sockets), fuller `NSDateFormatter`/
  `NSNumberFormatter` edge behavior.
- `NSAttributedString`/`NSMutableAttributedString`: full attribute surface,
  layout/document accessors.

**Add missing Apple Foundation classes not yet present at all** (grouped):
- *Collections/convenience*: NSCache, NSUUID, NSIndexPath, NSPointerArray,
  NSValueTransformer.
- *Predicates & regex*: NSPredicate, NSComparisonPredicate, NSCompoundPredicate,
  NSExpression, NSRegularExpression, NSTextCheckingResult.
- *KVO*: NSKeyValueObserving (NSObject KVO machinery).
- *Concurrency*: NSOperation/NSOperationQueue, NSProgress,
  NSBackgroundActivityScheduler.
- *Messaging/ports*: NSPort, NSPortMessage, NSPortCoder, NSPortNameServer,
  NSConnection, NSDistantObject, NSDistributedLock, NSDistributedNotificationCenter,
  NSNotificationQueue, NSProxy, NSInvocation, NSMethodSignature, NSProtocolChecker.
- *Process/undo*: NSUndoManager, NSUbiquitousKeyValueStore, NSUserActivity,
  NSUserNotification, NSUserScriptTask.
- *URL networking*: NSURLRequest, NSURLResponse, NSURLSession, NSURLConnection,
  NSURLCache, NSURLCredential(+Storage), NSURLAuthenticationChallenge,
  NSURLProtectionSpace, NSURLProtocol, NSHTTPCookie(+Storage), NSURLDownload.
- *File coordination*: NSFileCoordinator, NSFilePresenter, NSFileVersion,
  NSFileWrapper.
- *Formatters/units*: NSFormatter base, NSDateComponentsFormatter, NSDateInterval,
  NSDateIntervalFormatter, NSRelativeDateTimeFormatter, NSMeasurement, NSUnit,
  NSMeasurementFormatter, NSByteCountFormatter, NSEnergyFormatter,
  NSLengthFormatter, NSMassFormatter, NSListFormatter,
  NSPersonNameComponents(+Formatter).
- *XML & metadata*: NSXMLParser, NSXMLDocument/NSXMLDTD/NSXMLElement/NSXMLNode,
  NSMetadata, NSMetadataAttributes.
- *Linguistics*: NSLinguisticTagger, NSOrthography, NSInflectionRule,
  NSMorphology, NSTermOfAddress, NSSpellServer.
- *XPC*: real NSXPCConnection/NSXPCInterface/NSXPCListener (currently names only).
- *Scripting & legacy*: NSAppleScript, NSAppleEventManager/NSAppleEventDescriptor,
  NSScript* suite, NSArchiver, NSCalendarDate, NSHost, NSHFSFileTypes,
  NSNetServices.
- *Extensions/items*: NSExtensionContext, NSExtensionItem,
  NSExtensionRequestHandling, NSItemProvider.
- *Obsolete/misc*: NSGarbageCollector, NSClassDescription,
  NSObjectScripting, NSOrderedCollectionChange/Difference (used by the collection
  observers in the KVO slice).

**Cultivation**
- Grow `Tests/port_behavior.m` (and the golden) toward full behavioral parity per
  class; document reverse-engineered checkpoints in `local/disasm/fns/`.
- Expand the Swift overlay as more classes are completed.

## Project layout

```
Collections.subproj/   Date.subproj/  FileManager.subproj/  Locale.subproj/
Lock.subproj/          Notification.subproj/  Numeric.subproj/  RunLoop.subproj/
Runtime.subproj/       Serialization.subproj/  Sorting.subproj/  Stream.subproj/
String.subproj/        Swift.subproj/  Thread.subproj/  URL.subproj/  XPC.subproj/
Tests/                 # port_behavior.m, port_behavior_pool.m (MRC),
                       # port_behavior.golden, pairing_sweep.py
Tools/                 # gen_xcodeproj.py (make xcodeproj)
Common.mk  Makefile(bmake)  GNUmakefile(GNU make)  Info.plist  LICENSE
local/                 # project rules (Foundation.md), vendored CF headers,
                       # Apple Foundation dylib + disassembly reference (gitignored)
```