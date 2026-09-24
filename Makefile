# =====================================================================
#  Foundation.framework - bmake entry point
# ---------------------------------------------------------------------
#  This is the BSD bmake build.  Builds for both configurations:
#      bmake            # CONFIG=release (default)
#      bmake CONFIG=debug
#      bmake release | bmake debug
#  GNU make users get this same project from GNUmakefile (make prefers
#  GNUmakefile; bmake reads Makefile).  Everything except source
#  discovery and the per-object compile rules lives in Common.mk.
# =====================================================================

# ---- requested build configuration ----
CONFIG ?= release
REPO  := ${.CURDIR}

# ---- toolchain (bmake != shell resolution: needs an absolute path so
# xcrun's flagless lookup is computed once, not re-expanded) ----
MAKE_CC != /usr/bin/xcrun --find clang

# ---- source discovery (bmake != shell assignment) ----
# Object paths mirror the source tree under build/<CONFIG>/objects/.
# Tests is excluded: its harness main() must not be linked into the
# framework dylib.
OBJECTS != find . \( -path './build' -o -path './local' -o -path './Tests' \) -prune -o -name '*.m' -type f -print | sed 's|^\./|build/${CONFIG}/objects/|; s|\.m$$|.o|' | sort

# optimization flags follow the requested configuration
OPT_FLAGS != if test "${CONFIG}" = "debug"; then printf '%s' '-O0 -g -DDEBUG'; else printf '%s' '-O2'; fi

# ---- shared rules (flavor-neutral) ----
.include "Common.mk"

# ---- per-object compile rules ----
# bmake cannot use GNU-style pattern rules with a literal directory
# prefix (build/.../%.o fails to match), so each object gets an explicit
# rule from a .for loop.  Most sources are ARC; the MRC_SOURCES list
# (./-prefixed, matching MSRC) selects the handful compiled with
# -fno-objc-arc.
MSRC != find . \( -path './build' -o -path './local' -o -path './Tests' \) -prune -o -name '*.m' -type f -print | sort

.for src in ${MSRC}
build/${CONFIG}/objects/${src:C|^\./||:C|\.m$|.o|}: ${src} build/gen/Foundation/Foundation.h
	@mkdir -p ${.TARGET:H}
	@FLAGS=; if test "${MRC_SOURCES:M${src}}" != ""; then FLAGS=-fno-objc-arc; fi; \
	 ${CC} ${OPT_FLAGS} ${CFLAGS} $${FLAGS} -c ${src} -o ${.TARGET}
.endfor