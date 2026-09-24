# =====================================================================
#  Foundation.framework - GNU make entry point (GNU make >= 3.81)
# ---------------------------------------------------------------------
#  make prefers this file over Makefile, so plain `make` on a GNU make
#  host builds the project; BSD bmake reads the identical-target Makefile.
#  Builds for both configurations:
#      make             # CONFIG=release (default)
#      make CONFIG=debug
#      make release | make debug
#  Everything except source discovery and the per-object compile rules
#  lives in Common.mk.
# =====================================================================

# ---- requested build configuration ----
CONFIG ?= release
REPO  := $(CURDIR)

# ---- toolchain (GNU $(shell) resolution: needs an absolute path so
# xcrun's flagless lookup expands once, not per use) ----
MAKE_CC := $(shell /usr/bin/xcrun --find clang)

# ---- source discovery (GNU $(shell) assignment) ----
# Object paths mirror the source tree under build/$(CONFIG)/objects/.
# Tests is excluded: its harness main() must not be linked into the
# framework dylib.
OBJECTS := $(shell find . \( -path './build' -o -path './local' -o -path './Tests' \) -prune -o -name '*.m' -type f -print | sed 's|^\./|build/$(CONFIG)/objects/|; s|\.m$$|.o|' | sort)

# optimization flags follow the requested configuration
OPT_FLAGS := $(if $(filter-out debug,$(CONFIG)),-O2,-O0 -g -DDEBUG)

# ---- shared rules (flavor-neutral) ----
include Common.mk

# ---- per-object compile rules ----
# GNU pattern rule (bmake cannot match a literal directory prefix in a
# pattern rule; it uses the .for loop in Makefile instead).  Most sources
# are ARC; the sources in MRC_OBJ_PAT are compiled with -fno-objc-arc.
MRC_OBJ_PAT = Collections.subproj/NSMapTable.m|Collections.subproj/NSHashTable.m|Collections.subproj/NSPointerFunctions.m|Collections.subproj/NSData.m|FileManager.subproj/NSFileHandle.m|FileManager.subproj/NSFileManager.m|FileManager.subproj/NSPathUtilities.m|Runtime.subproj/NSBundle.m|Runtime.subproj/NSException.m|Runtime.subproj/NSObjCRuntime.m|Runtime.subproj/NSProcessInfo.m|Runtime.subproj/NSUserDefaults.m|Runtime.subproj/NSValue.m|Runtime.subproj/NSZone.m

build/$(CONFIG)/objects/%.o: %.m build/gen/Foundation/Foundation.h
	@mkdir -p $(@D)
	@FLAGS=; case "$<" in \
	    $(MRC_OBJ_PAT)) FLAGS=-fno-objc-arc ;; \
	esac; \
	 $(CC) $(OPT_FLAGS) $(CFLAGS) $$FLAGS -c "$<" -o "$@"