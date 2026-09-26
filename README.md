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
  and take precedence so the LibreDarwin CF tree wins.
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
  ~1,250 deterministic, timezone-agnostic probes (`Tests/port_behavior.m`), and
  its output is diffed byte-for-byte against Apple's real Foundation output,
  captured in `Tests/port_behavior.golden`. New probe coverage requires adding the
  touched sources to `GATE_SRCS` in `Common.mk` and re-capturing the Apple truth.
- **Pairing sweep** (`make pairing-sweep`, `Tests/pairing_sweep.py`). Every
  selector declared in any header (53 headers, ~914 selectors) must be
  implemented somewhere in the `.m` sources; 19 hand-verified selectors the
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
NSDebug, NSObjCRuntime; `FoundationErrors.h`, `Foundation.apinotes`.

**Serialization** — NSCoder, and the recently completed keyed-archive pair:
NSKeyedArchiver + NSKeyedUnarchiver (codec categories, encoding/substitution
pipeline, delegate hooks, `+unarchiveTopLevelObjectWithData:error:`).

**FileManager** — NSFileHandle, NSFileManager, NSPathUtilities, NSPipe, NSTask.

**Locale** — NSLocale (preferredLanguages, available/ISO lists, autoupdating).

**Lock / Notification / RunLoop / Thread / Sorting / Stream / URL** — NSLock,
NSRecursiveLock, NSCondition, NSConditionLock; NSNotification,
NSNotificationCenter; NSRunLoop, NSTimer; NSThread; NSSortDescriptor (key /
selector / comparator with evaluation lock); NSStream/NSInputStream/
NSOutputStream (CF-backed); NSURL *(partial)*.

**Swift overlay** — `Swift.subproj/Foundation.swiftinterface` declaring the
String/Array/Dictionary ↔ Foundation bridging conformances, backed by the
system binary's exports (the Swift counterpart of a `.tbd`).

**Stubs (declaration-only, no implementation yet)** — `NSAttributedString.h`
(just enough for CFAttributedString toll-free), `NSXPCConnection.h`
(NSXPCInterface/NSXPCConnection/NSXPCProxyCreating names so headers compile).

## Current status and known issues

- **Tree is green**: `make all` (build + pairing sweep + behavior gate) passes for
  both `release` and `debug` configurations. 896 selectors across 52 headers are
  declared and implemented.
- **Delegation protocols are handled**: the pairing sweep strips `@protocol`
  bodies and forward declarations (delegate methods are implemented by
  conformers, never by the framework itself) and allowlists
  `unarchiveTopLevelObjectWithData:error:`, whose `NS_SWIFT_UNAVAILABLE` on the
  `error:` parameter fools the flat selector matcher despite the implementation
  at `Serialization.subproj/NSKeyedUnarchiver.m:329`.
- `NSKeyedArchiver.m` / `NSKeyedUnarchiver.m` are **not yet in `GATE_SRCS`**, so
  keyed-archive behavior is not yet gate-pinned against Apple ground truth.
- The framework deliberately ships **no `NSAutoreleasePool`**; until it does, the
  dylib keeps a single dependency on Apple's Foundation (the injected
  `-framework Foundation` autolink for `_OBJC_CLASS_$_NSAutoreleasePool`) —
  documented in `Common.mk`.

## What's left

**Finish / gate the current slice**
- Add `NSKeyedArchiver.m`/`NSKeyedUnarchiver.m` to `GATE_SRCS`, extend
  `Tests/port_behavior.m` with keyed-archive probes, and re-capture the Apple
  ground truth into `Tests/port_behavior.golden`.
- Provide `NSAutoreleasePool` (with NSThread/NSRunLoop integration) to drop the
  last Apple-Foundation link dependency and the autolink workaround.

**Deepen partial classes**
- `NSURL`: components, query/relative URLs, file bookmarks, standardize,
  resource-value accessors; `NSFileManager`/`NSFileHandle`/`NSPipe` (integration
  props), `NSBundle`, `NSUserDefaults`, `NSProcessInfo`, `NSStream` (schemes,
  sockets), fuller `NSDateFormatter`/`NSNumberFormatter` edge behavior.
- `NSAttributedString`/`NSMutableAttributedString`: full attribute surface,
  `NSCoding`/copying, attachment handling, layout/document accessors.

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
- *Obsolete/misc*: NSAutoreleasePool, NSGarbageCollector, NSClassDescription,
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
Tests/                 # port_behavior.m, port_behavior.golden, pairing_sweep.py
Tools/                 # gen_xcodeproj.py (make xcodeproj)
Common.mk  Makefile(bmake)  GNUmakefile(GNU make)  Info.plist  LICENSE
local/                 # project rules (Foundation.md), vendored CF headers,
                       # Apple Foundation dylib + disassembly reference (gitignored)
```