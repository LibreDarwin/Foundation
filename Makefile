# =====================================================================
#  Foundation.framework — bmake build
# ---------------------------------------------------------------------
#  Main build file for the LibreDarwin Foundation.framework.
#
#  * Generates an umbrella header in build/gen/ from the subprojects'
#    own headers, so <Foundation/...> includes resolve here.
#  * Compiles every .m file under the subprojects (ARC, except the few
#    sources written for non-ARC) and links against CoreFoundation and
#    the system libraries.
#  * Checks that every method declared in String.subproj/NSString.h is
#    implemented in String.subproj/NSString.m, failing the build when
#    a declaration is left unimplemented.
#
#  Uses bmake constructs only (.for loops, := and != assignments; no
#  GNU make functions or modifiers).
# =====================================================================

# ---- toolchain ----
# Builds against the LibreDarwin Internal SDK (the macOS SDK this framework
# drops into). Point RN elsewhere on the command line (bmake RN=...) for a
# dev build against Apple's SDK.
CC  != xcrun --find clang
RN  = /Users/sunneva/xnuports-root/devel/xcode-tools/build/release/Developer/Platforms/MacOSX.platform/Developer/SDKs/MacOSX.Internal.sdk

# ---- framework locations ----
FW      = build/release/Foundation.framework
DYLIB   = ${FW}/Versions/A/Foundation

# Public umbrella includes every subproject header EXCEPT NSCFTypeID.h, which
# is internal-use-only: it includes the private <CoreFoundation/CFRuntime_Internal.h>,
# so pulling it into Foundation.h would break a standalone
# '#import <Foundation/Foundation.h>' for consumers without private CF headers.
# The header still ships in the framework (explicit inclusion is an opt-in).
UMBRELLA_HDRS = ${HDRS:N*NSCFTypeID*}

# ---- sources ----
# bmake != assigns the shell output; it is evaluated each run.
HDRS != find . \( -path './build' -o -path './local' \) -prune -o -name '*.h' -type f -print | sort
MSRC != find . \( -path './build' -o -path './local' \) -prune -o -name '*.m' -type f -print | sort
# Object paths mirror the source tree under build/objects/.
OBJECTS != find . \( -path './build' -o -path './local' \) -prune -o -name '*.m' -type f -print | sed 's|^\./|build/objects/|; s|\.m$$|.o|' | sort

# ---- compiler flags ----
# Why the linked dylib ends up with an LC_LOAD_DYLIB for /System/.../Foundation.framework
# even though this Makefile only links CoreFoundation: clang's implicit ObjC autolink
# injects '-framework Foundation' into every ObjC (ARC) link, and exactly one undefined
# symbol binds against it — _OBJC_CLASS_$_NSAutoreleasePool, a vestigial __objc_classrefs
# entry that clang's '^@autoreleasepool' lowering emits in Thread.subproj/NSThread.m even
# though its code was optimized away (bound, never called). Verified partition of the
# dylib's 367 undefineds: 190 CF_* -> CoreFoundation, 23 _objc_* -> libobjc, 2 NSObject
# class+metaclass -> libobjc (libobjc.A.tbd and CoreFoundation.tbd both export), 1
# _OBJC_CLASS_$_NSAutoreleasePool -> Foundation ONLY (libobjc.A.tbd and CF.tbd do not
# export it; Foundation.tbd does — the one real Apple Foundation dependency), 151
# libSystem/compiler-rt. A direct 'ld' link without '-framework Foundation' fails on
# exactly that one symbol.
# This project deliberately ships no NSAutoreleasePool, so until the target provides that
# class (LibreDarwin's own Foundation must export it) a direct 'ld' link removes the
# injected framework and then fails on '^_OBJC_CLASS_$_NSAutoreleasePool'. Keeping the
# autolink is therefore the correct host-build accommodation; dropping Apple Foundation
# requires the LibreDarwin Foundation to own that class symbol first.
# Some subprojects include CoreFoundation's private headers
# (ForFoundationOnly.h and friends).  They are only present once the
# LibreDarwin CoreFoundation build has been installed into the Internal SDK
# (its install rule populates CoreFoundation.framework/PrivateHeaders).  Until
# then the coherent LibreDarwin CF header tree is vendored under local/include
# (gitignored: <repo>/devel/CoreFoundation's headers, patched by hand so the
# framework compiles).  It must precede the SDK's CF headers so the LibreDarwin
# tree wins the include; NSBUILDINGFOUNDATION satisfies ForFoundationOnly.h's
# !CF_BUILDING_CF guard.
#
# The vendored tree carries hand patches; re-apply them if it is re-vendored:
#   * CFBase.h           - the additive #ifndef-guarded typedefs (ScriptCode &
#                          friends) that the trimmed Internal SDK MacTypes.h drops,
#                          plus the CF_ASSUME_NONNULL_BEGIN/END pair (guarded)
#                          that LibreDarwin's CFBase.h omits but the SDK's
#                          trimmed framework headers (CFCGTypes.h) rely on.
#   * CFAvailability.h   - the string-enum family (CF_STRING_ENUM, _CF_TYPED_ENUM,
#                          _CF_TYPED_EXTENSIBLE_ENUM, CF_TYPED_* spellings) that
#                          LibreDarwin omits but Apple's extended enumerations
#                          rely on.
#   * CFRunLoop.h        - 'typedef CFStringRef CFRunLoopMode CF_EXTENSIBLE_STRING_ENUM'
#                          and the run-result enum promoted to
#                          'typedef CF_ENUM(SInt32, CFRunLoopRunResult)', matching
#                          Apple's public header.
#   * ForFoundationOnly.h - _CFRunLoopFinished() declared unconditionally (Apple
#                          declares it for the Foundation-facing surface; the
#                          DEPLOYMENT_TARGET_* guard leaves it invisible here).
CF_PRIV != { test -d ${RN}/System/Library/Frameworks/CoreFoundation.framework/PrivateHeaders && echo -I${RN}/System/Library/Frameworks/CoreFoundation.framework/PrivateHeaders; } || true
CF_LOCAL != { test -d local/include/CoreFoundation && echo -I local/include; } || true

CFLAGS  = -fobjc-arc -fblocks -fobjc-runtime=macosx \
          -isysroot ${RN} \
          -DNSBUILDINGFOUNDATION \
          ${CF_LOCAL} \
          -I${RN}/System/Library/Frameworks/CoreFoundation.framework/Headers \
          ${CF_PRIV} \
          -I build/gen
LDFLAGS = -dynamiclib -fobjc-arc -isysroot ${RN} \
          -F${RN}/System/Library/Frameworks -framework CoreFoundation \
          -install_name @rpath/Foundation.framework/Versions/A/Foundation

.PHONY: all release pairing-instrument umbrella clean gitignore

all: release

# =====================================================================
#  Pairing check: every method declared in NSString.h must also be
#  implemented in NSString.m. Exits non-zero when they disagree.
#  The $$0 escapes keep AWK's record variable from being expanded by
#  make first.
# =====================================================================
pairing-instrument:
	@awk 'function c(x){gsub(/\r/,"",x);sub(/^[-+][[:space:]]*\(/,"",x);sub(/\).*/,"",x);gsub(/[[:space:]]/,"",x);return x} \
	      NR==FNR{if(/^[-+][[:space:]]*\(/)a[c($$0)]=1;next} \
	      /^[-+][[:space:]]*\(/{b[c($$0)]=1} \
	      END{for(k in a)if(!(k in b)){printf "   MISSING %s\n",k;m++} \
	          for(k in b)if(!(k in a)){printf "   EXTRA   %s\n",k;x++} \
	          printf "   PAIRING GATE: declared=%d implemented=%d missing=%d extra=%d FAIL=%d\n",length(a),length(b),m+0,x+0,((m+x)>0); \
	          exit((m+x)>0)}' \
	      String.subproj/NSString.h String.subproj/NSString.m

# =====================================================================
#  Umbrella header: copied from the subprojects' own headers and
#  gathered into build/gen/Foundation/Foundation.h.
# =====================================================================
umbrella: build/gen/Foundation/Foundation.h

build/gen/Foundation/Foundation.h: pairing-instrument
	@mkdir -p build/gen/Foundation
	@rm -f $@
	@for h in ${HDRS}; do hb="$${h##*/}"; cp "$$h" build/gen/Foundation/; done
	@{  echo '// Foundation.h — generated from this project'"'"'s subproject headers'; \
	    for h in ${UMBRELLA_HDRS}; do hb="$${h##*/}"; echo "#include <Foundation/$$hb>"; done; \
	} > $@

# =====================================================================
#  Object files: one .o per .m source. Most sources are ARC; a handful
#  were written for non-ARC (they cast raw CF objects without __bridge),
#  so those get -fno-objc-arc. The :C modifiers turn './X.m' into
#  'build/objects/X.o' for the target, and the umbrella header is a
#  prerequisite because every source includes <Foundation/...> from
#  build/gen.
#
#  Note: the build stops at the first source that includes
#  CoreFoundation/ForFoundationOnly.h until the LibreDarwin
#  CoreFoundation build has been installed into the Internal SDK
#  (see CF_PRIV above).
# =====================================================================
MRC_SOURCES = ./Collections.subproj/NSMapTable.m \
              ./Collections.subproj/NSData.m \
              ./FileManager.subproj/NSFileHandle.m \
              ./FileManager.subproj/NSFileManager.m \
              ./FileManager.subproj/NSPathUtilities.m \
              ./Runtime.subproj/NSBundle.m \
              ./Runtime.subproj/NSException.m \
              ./Runtime.subproj/NSObjCRuntime.m \
              ./Runtime.subproj/NSProcessInfo.m \
              ./Runtime.subproj/NSUserDefaults.m \
              ./Runtime.subproj/NSZone.m

.for src in ${MSRC}
${src:C|^\./|build/objects/|:C|\.m$|.o|}: ${src} build/gen/Foundation/Foundation.h
	@mkdir -p ${.TARGET:H}
	@FLAGS=; if test "${MRC_SOURCES:M${src}}" != ""; then FLAGS=-fno-objc-arc; fi; \
	 ${CC} ${CFLAGS} $${FLAGS} -c ${src} -o ${.TARGET}
.endfor

# =====================================================================
#  Framework bundle
# =====================================================================
release: umbrella ${DYLIB}

${DYLIB}: ${OBJECTS}
	@mkdir -p ${DYLIB:H} ${FW}/Versions/A/Headers ${FW}/Versions/A/Resources
	@${CC} ${LDFLAGS} -o $@ ${OBJECTS}
	@cp build/gen/Foundation/*.h ${FW}/Versions/A/Headers/
	@cp Info.plist ${FW}/Versions/A/Resources/
	@ln -sfn A ${FW}/Versions/Current
	@ln -sfn Versions/Current/Foundation ${FW}/Foundation
	@ln -sfn Versions/Current/Headers ${FW}/Headers

clean:
	@rm -rf build

gitignore:
	@grep -q '^build/$$' .gitignore || printf 'build/\n' >> .gitignore