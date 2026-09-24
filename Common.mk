# =====================================================================
#  Common.mk - flavor-neutral build rules shared by the two makefiles.
# ---------------------------------------------------------------------
#  Included by both Makefile (BSD bmake) and GNUmakefile (GNU make),
#  which differ only in *source discovery* (bmake != / :C / :M vs GNU
#  $(shell) / pattern rules) and *per-object compile rules* (bmake .for
#  loop vs GNU pattern rule).  Everything below uses only constructs and
#  POSIX-shell recipes that GNU make (>= 3.81) and bmake both accept:
#  = and := assignments, ${VAR} references, ordinary rules, .PHONY and
#  $@ / $< / $(@D).  No !=, no $(shell), no .for, no ifeq, no :C/:M/:H.
#
#  The framework is built per configuration into build/<CONFIG>/ with
#  CONFIG = release (default) or debug.  `make release` / `make debug`
#  forward CONFIG.  The behavior gate, pairing checks and the generated
#  umbrella header all work for either configuration.
#
#  * Generates an umbrella header in build/gen/ from the subprojects'
#    own headers, so <Foundation/...> includes resolve here.
#  * Compiles every .m file under the subprojects (ARC, except the few
#    sources written for non-ARC) and links against CoreFoundation and
#    the system libraries.
#  * Checks that every method declared in String.subproj/NSString.h is
#    implemented in String.subproj/NSString.m, failing the build when
#    a declaration is left unimplemented.
# =====================================================================

# ---- toolchain ----
# Builds against the LibreDarwin Internal SDK (the macOS SDK this framework
# drops into). Point RN elsewhere on the command line (make RN=...) for a
# dev build against Apple's SDK. MAKE_CC (the resolved clang path) is set by
# each flavor file: 'xcrun --find clang' is flagless, but it must be resolved
# once because compile/link recipes always pass flags after the compiler.
CC = ${MAKE_CC}
RN  = /Users/sunneva/xnuports-root/devel/xcode-tools/build/release/Developer/Platforms/MacOSX.platform/Developer/SDKs/MacOSX.Internal.sdk

# ---- requested build configuration: release (default) or debug ----
CONFIG ?= release

# ---- framework locations (per configuration) ----
FW     = build/${CONFIG}/Foundation.framework
DYLIB  = ${FW}/Versions/A/Foundation

# OPT_FLAGS is set by the including flavor file: release = -O2,
# debug = -O0 -g -DDEBUG.  Used by the object rules and the behavior gate.

# Public umbrella includes every subproject header EXCEPT NSCFTypeID.h, which
# is internal-use-only: it includes the private <CoreFoundation/CFRuntime_Internal.h>,
# so pulling it into Foundation.h would break a standalone
# '#import <Foundation/Foundation.h>' for consumers without private CF headers.
# The header still ships in the framework (explicit inclusion is an opt-in).

# ---- compiler flags ----
# Why the linked dylib ends up with an LC_LOAD_DYLIB for /System/.../Foundation.framework
# even though we only link CoreFoundation: clang's implicit ObjC autolink
# injects '-framework Foundation' into every ObjC (ARC) link, and exactly one
# undefined symbol binds against it - _OBJC_CLASS_$_NSAutoreleasePool, a
# vestigial __objc_classrefs entry that clang's '^@autoreleasepool' lowering
# emits in Thread.subproj/NSThread.m even though its code was optimized away
# (bound, never called).  Verified partition of the dylib's undefineds:
# 190 CF_* -> CoreFoundation, 23 _objc_* -> libobjc, 2 NSObject class+metaclass
# -> libobjc, 1 _OBJC_CLASS_$_NSAutoreleasePool -> Foundation ONLY
# (libobjc.A.tbd and CF.tbd do not export it; Foundation.tbd does - the one
# real Apple Foundation dependency), 151 libSystem/compiler-rt.  A direct 'ld'
# link without '-framework Foundation' fails on exactly that one symbol.
# This project deliberately ships no NSAutoreleasePool, so until the target
# provides that class a direct 'ld' link removes the injected framework and
# then fails on '^_OBJC_CLASS_$_NSAutoreleasePool'.  Keeping the autolink is
# therefore the correct host-build accommodation; dropping Apple Foundation
# requires the LibreDarwin Foundation to own that class symbol first.
# Some subprojects include CoreFoundation's private headers
# (ForFoundationOnly.h and friends).  Until the LibreDarwin CoreFoundation
# build has been installed into the Internal SDK, the coherent LibreDarwin CF
# header tree is vendored under local/include (gitignored).  It must precede
# the SDK's CF headers so the LibreDarwin tree wins the include; the -I for
# the CoreFoundation PrivateHeaders dir is inert when that dir is absent.
CFLAGS  = -fobjc-arc -fblocks -fobjc-runtime=macosx \
          -isysroot ${RN} \
          -DNSBUILDINGFOUNDATION \
          -I local/include \
          -I${RN}/System/Library/Frameworks/CoreFoundation.framework/PrivateHeaders \
          -I${RN}/System/Library/Frameworks/CoreFoundation.framework/Headers \
          -I build/gen
LDFLAGS = -dynamiclib -fobjc-arc -isysroot ${RN} \
          -F${RN}/System/Library/Frameworks -framework CoreFoundation \
          -install_name @rpath/Foundation.framework/Versions/A/Foundation

.PHONY: all build debug release verify umbrella pairing-instrument pairing-sweep behavior-gate config-check clean gitignore xcodeproj

all: build verify

# =====================================================================
#  Configuration gate: CONFIG must be one of the supported build kinds.
# =====================================================================
config-check:
	@case '${CONFIG}' in release|debug) ;; \
	  *) echo "error: CONFIG must be 'release' or 'debug' (got '${CONFIG}')" >&2; exit 1;; \
	esac

# =====================================================================
#  Convenience entry points.  They re-invoke make with the CONFIG they
#  name; `make` (no arguments) builds with CONFIG=release.
# =====================================================================
release:
	@${MAKE} CONFIG=release all

debug:
	@${MAKE} CONFIG=debug all

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
#  Full-Foundation pairing sweep: every method declared in any subproject
#  header must be implemented somewhere in the .m sources. This is the
#  project-wide extension of pairing-instrument above; it uses
#  Tests/pairing_sweep.py, which carries an allowlist for the handful of
#  declarations the mechanical parser cannot match (macro-generated
#  -initWith*, multiline-attribute, and variadic methods), each verified
#  by hand to exist in the sources.
# =====================================================================
pairing-sweep:
	@cd ${REPO} && python3 Tests/pairing_sweep.py .

# =====================================================================
#  Behavioral gate: compile the port's own .m sources that the harness
#  touches directly INTO the gate executable (NOT against the built
#  dylib), run it, and diff byte-for-byte against the Apple-ground-truth
#  harness output captured in Tests/port_behavior.golden.
#
#  Why compile the sources into the binary instead of linking the built
#  dylib: the dylib and this executable both LC_LOAD Apple's
#  CoreFoundation, whose toll-free classes share names with the port's
#  (NSArray, NSString, ...).  A name lookup on the host resolves to
#  CoreFoundation's class (it registered first), so an object created by
#  CoreFoundation inherits CoreFoundation's implementation -- or crashes
#  on an abstract-class instance ('-[NSArray count]: method sent to an
#  instance of an abstract class').  Compiling the port .m files into the
#  executable's main image binds the port's class objects there, and
#  because message dispatch follows the instance's class pointer (not its
#  name), instances the port's own factories create always run the port's
#  code.  The CF-toll-free classes (NSCalendar, NSLocale, ...) are owning
#  wrappers so every instance is a port class.  This is the same reason
#  the gate must not link -framework Foundation (Apple's): its classes
#  would shadow the port's.  Only -framework CoreFoundation is linked, to
#  satisfy the CF_* C symbols the port sources call.
#
#  The harness only exercises timezone-agnostic, deterministic behavior
#  (values are printed, never system descriptions), so the golden file is
#  portable.  If new probes are added, any additional .m sources the new
#  probe touches must be added to GATE_SRCS.
# =====================================================================
GATE_SRCS = String.subproj/NSString.m \
            String.subproj/NSCharacterSet.m \
            Collections.subproj/NSArray.m \
            Collections.subproj/NSEnumerator_array.m \
            Collections.subproj/NSSet.m \
            Collections.subproj/NSOrderedSet.m \
            Collections.subproj/NSDictionary.m \
            Collections.subproj/NSMapTable.m \
            Collections.subproj/NSHashTable.m \
            Collections.subproj/NSPointerFunctions.m \
            Collections.subproj/NSData.m \
            Sorting.subproj/NSSortDescriptor.m \
            Runtime.subproj/NSKeyValueCoding.m \
            Numeric.subproj/NSDecimal.m \
            Numeric.subproj/NSDecimalNumber.m \
            Numeric.subproj/NSNumber.m \
            Numeric.subproj/NSNumberFormatter.m \
            Date.subproj/NSDate.m \
            Date.subproj/NSCalendar.m \
            Date.subproj/NSCalendarSearchCore.c \
            Date.subproj/NSDateComponents.m \
            Date.subproj/NSDateFormatter.m \
            Date.subproj/NSISO8601DateFormatter.m \
            Date.subproj/NSTimeZone.m \
            Locale.subproj/NSLocale.m \
            String.subproj/NSScanner.m \
            Runtime.subproj/NSError.m \
            Runtime.subproj/NSException.m \
            Runtime.subproj/NSNull.m \
            Runtime.subproj/NSValue.m \
            URL.subproj/NSURL.m

# Sources written for non-ARC (they cast raw CF objects without __bridge).
# The bmake compile rules match with :M; the GNU rules use MRC_OBJ_PAT.
MRC_SOURCES = ./Collections.subproj/NSMapTable.m \
              ./Collections.subproj/NSHashTable.m \
              ./Collections.subproj/NSPointerFunctions.m \
              ./Collections.subproj/NSData.m \
              ./FileManager.subproj/NSFileHandle.m \
              ./FileManager.subproj/NSFileManager.m \
              ./FileManager.subproj/NSPathUtilities.m \
              ./Runtime.subproj/NSBundle.m \
              ./Runtime.subproj/NSException.m \
              ./Runtime.subproj/NSObjCRuntime.m \
              ./Runtime.subproj/NSProcessInfo.m \
              ./Runtime.subproj/NSUserDefaults.m \
              ./Runtime.subproj/NSValue.m \
              ./Runtime.subproj/NSZone.m

# The gate compiles a subset of GATE_SRCS with -fno-objc-arc as well.
MRC_GATE_PAT = Collections.subproj/NSData.m|Collections.subproj/NSMapTable.m|Collections.subproj/NSHashTable.m|Collections.subproj/NSPointerFunctions.m|Runtime.subproj/NSException.m|Runtime.subproj/NSValue.m

# The gate executable links against Apple's CoreFoundation for its CF_* C
# symbols only.  It must link with the Apple SDK sysroot, not ${RN}: the
# Internal SDK has no linkable libSystem ('ld: library System not found').
BEHAVIOR_LINK_SDK = /Applications/Xcode.app/Contents/Developer/Platforms/MacOSX.platform/Developer/SDKs/MacOSX.sdk

behavior-gate: build/gen/Foundation/Foundation.h
	@rm -rf build/${CONFIG}/gate && mkdir -p build/${CONFIG}/gate
	@for src in ${GATE_SRCS}; do FLAGS=; \
	    case "$${src}" in \
	      ${MRC_GATE_PAT}) FLAGS=-fno-objc-arc ;; \
	      Date.subproj/NSCalendarSearchCore.c) FLAGS=-x\ objective-c ;; \
	    esac; \
	    ${CC} ${OPT_FLAGS} ${CFLAGS} $${FLAGS} -c "$${src}" -o build/${CONFIG}/gate/$${src##*/}.o || exit 1; \
	 done
	@${CC} ${OPT_FLAGS} ${CFLAGS} -DPORT_GATE -c Tests/port_behavior.m \
	    -o build/${CONFIG}/gate/port_behavior.o
	@${CC} -isysroot ${BEHAVIOR_LINK_SDK} -o build/${CONFIG}/port_behavior \
	    build/${CONFIG}/gate/*.o -framework CoreFoundation
	@build/${CONFIG}/port_behavior > build/${CONFIG}/port_behavior.out
	@diff Tests/port_behavior.golden build/${CONFIG}/port_behavior.out \
	    && echo "   BEHAVIOR GATE: PASS (port == Apple ground truth, 1100 probes)"

verify: pairing-sweep behavior-gate

# =====================================================================
#  Umbrella header: copied from the subprojects' own headers and
#  gathered into build/gen/Foundation/Foundation.h.  NSCFTypeID.h is
#  copied along (explicit inclusion is an opt-in) but excluded from the
#  umbrella's #include list.
# =====================================================================
umbrella: build/gen/Foundation/Foundation.h

build/gen/Foundation/Foundation.h: pairing-instrument pairing-sweep
	@rm -rf build/gen/Foundation; mkdir -p build/gen/Foundation; \
	  hdrs="$$(find . \( -path './build' -o -path './local' \) -prune -o -name '*.h' -type f -print | sort)"; \
	  for h in $$hdrs; do cp "$$h" build/gen/Foundation/; done; \
	  { echo '// Foundation.h — generated from this project'"'"'s subproject headers'; \
	    for h in $$hdrs; do case "$$h" in \
	      */NSCFTypeID.h) ;; \
	      *) echo "#include <Foundation/$${h##*/}>";; \
	    esac; done; } > $@

# =====================================================================
#  Framework bundle.  `build` is the plain-build entry (the `all`
#  workflow is build + verify); its deliverable is the dylib target
#  below, whose prerequisites are the object files,
#  mapped from the subproject .m sources by the flavor-specific discovery
#  in the including makefile; the object compile rules themselves live
#  there too (bmake .for loop in Makefile, GNU pattern rule in
#  GNUmakefile).
# =====================================================================
build: ${DYLIB}

${DYLIB}: ${OBJECTS}
	@mkdir -p $(@D) ${FW}/Versions/A/Headers ${FW}/Versions/A/Resources
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

# Regenerate Foundation.xcodeproj from the current source tree.  The
# project itself can also be (re)generated via `make xcodeproj`.
xcodeproj:
	@cd ${REPO} && python3 Tools/gen_xcodeproj.py