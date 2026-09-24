#!/usr/bin/env python3
"""Regenerate Foundation.xcodeproj from the current source tree.

Kept in lock-step with the make build: sources are the .m files under the
*.subproj directories (Tests, build/ and local/ are never part of the
framework), and the non-ARC files are taken from MRC_SOURCES in Common.mk
so they get -fno-objc-arc as compiler flags.

Run via `make xcodeproj` (GNU make or bmake).  Regenerates
Foundation.xcodeproj/project.pbxproj deterministically.
"""

import hashlib
import os
import re
import sys


def root_dir():
    return os.path.abspath(os.path.join(os.path.dirname(os.path.abspath(__file__)), ".."))


def oid(key):
    """Stable 24-hex object id for a pbxproj object."""
    return hashlib.sha1(key.encode("utf-8")).hexdigest()[:24].upper()


def iter_subproject_sources(project_root):
    """Yield 'SUBPROJ/Name.m' for every .m under a *.subproj directory."""
    for name in sorted(os.listdir(project_root)):
        if not name.endswith(".subproj"):
            continue
        base = os.path.join(project_root, name)
        for dirpath, dirnames, filenames in os.walk(base):
            dirnames.sort()
            for fn in sorted(filenames):
                if fn.endswith(".m"):
                    rel = os.path.relpath(os.path.join(dirpath, fn), project_root)
                    yield rel.replace(os.sep, "/")


def read_mrc_sources(project_root):
    """Extract the ./-prefixed MRC_SOURCES list from Common.mk."""
    mrc = []
    with open(os.path.join(project_root, "Common.mk"), "r", encoding="utf-8") as f:
        pending = False
        for line in f:
            if line.startswith("MRC_SOURCES ="):
                pending = True
            if pending:
                for m in re.finditer(r"(\./[^\s\\]+)", line):
                    mrc.append(m.group(1)[2:])  # strip leading ./
                if not line.rstrip("\n").endswith("\\"):
                    pending = False
    return set(mrc)


def q(s):
    return '"%s"' % s


def buildfile_id(src):
    return oid("buildfile:" + src)


def fileref_id(src):
    return oid("fileref:" + src)


def group_id():          return oid("group:sources")
def products_group_id(): return oid("group:products")
def main_group_id():     return oid("group:main")
def target_id():         return oid("target:Foundation")
def project_id():        return oid("project:Foundation")
def cf_fileref_id():     return oid("fileref:CoreFoundation.framework")
def cf_buildfile_id():   return oid("buildfile:CoreFoundation.framework")
def sources_phase_id():  return oid("phase:sources")
def frameworks_phase_id(): return oid("phase:frameworks")
def resources_phase_id():  return oid("phase:resources")
def umbrella_phase_id():   return oid("phase:umbrella")
def proj_configlist_id(): return oid("configlist:project")
def target_configlist_id(): return oid("configlist:target")
def proj_cfg_debug_id():   return oid("cfg:project:Debug")
def proj_cfg_release_id(): return oid("cfg:project:Release")
def tgt_cfg_debug_id():    return oid("cfg:target:Debug")
def tgt_cfg_release_id():  return oid("cfg:target:Release")


def build_config_block(cfg_id, comment, is_target, is_debug):
    lines = [
        "\t\t%s /* %s */ = {" % (cfg_id, comment),
        "\t\t\tisa = XCBuildConfiguration;",
    ]
    if is_target:
        settings = {
            "CODE_SIGN_IDENTITY": "-",
            "CODE_SIGN_STYLE": "Automatic",
            "CURRENT_PROJECT_VERSION": "1",
            "DEFINES_MODULE": "YES",
            "DYLIB_COMPATIBILITY_VERSION": "1",
            "DYLIB_CURRENT_VERSION": "1",
            "DYLIB_INSTALL_NAME_BASE": "@rpath",
            "CLANG_ENABLE_MODULES": "NO",
            "CLANG_ENABLE_OBJC_ARC": "YES",
            "GCC_PREPROCESSOR_DEFINITIONS": [
                "$(inherited)",
                "NSBUILDINGFOUNDATION=1",
                "CF_SWIFT_SENDABLE=",
                "CF_SWIFT_NAME(x)=",
            ],
            "HEADER_SEARCH_PATHS": [
                "$(inherited)",
                "$(SRCROOT)/build/gen",
                "$(SRCROOT)/local/include",
                "$(SDKROOT)/System/Library/Frameworks/CoreFoundation.framework/Headers",
                "$(SDKROOT)/System/Library/Frameworks/CoreFoundation.framework/PrivateHeaders",
            ],
            "INFOPLIST_FILE": "Info.plist",
            "INSTALL_PATH": "$(LOCAL_LIBRARY_DIR)/Frameworks",
            "LD_RUNPATH_SEARCH_PATHS": [
                "$(inherited)",
                "@executable_path/../Frameworks",
                "@loader_path/Frameworks",
            ],
            "MACH_O_TYPE": "mh_dylib",
            "OTHER_LDFLAGS": ["$(inherited)", "-framework", "CoreFoundation"],
            "PRODUCT_BUNDLE_IDENTIFIER": "org.libredarwin.Foundation",
            "PRODUCT_NAME": "Foundation",
            "SDKROOT": "macosx",
            "SKIP_INSTALL": "YES",
            "WRAPPER_EXTENSION": "framework",
        }
        if is_debug:
            settings["GCC_OPTIMIZATION_LEVEL"] = "0"
            settings["ONLY_ACTIVE_ARCH"] = "YES"
            settings["MACOSX_DEPLOYMENT_TARGET"] = "12.0"
        else:
            settings["GCC_OPTIMIZATION_LEVEL"] = "s"
            settings["MACOSX_DEPLOYMENT_TARGET"] = "12.0"
    else:
        settings = {
            "MACOSX_DEPLOYMENT_TARGET": "12.0",
            "SDKROOT": "macosx",
        }
    lines.append("\t\t\tbuildSettings = {")
    for k in sorted(settings.keys()):
        v = settings[k]
        if isinstance(v, list):
            items = ", ".join(q(x) for x in v)
            lines.append("\t\t\t\t%s = (%s);" % (k, items))
        else:
            lines.append("\t\t\t\t%s = %s;" % (k, q(v)))
    lines.append("\t\t\t};")
    lines.append("\t\t\tname = %s;" % ("Debug" if is_debug else "Release"))
    lines.append("\t\t};")
    return lines


def emit_project(pbxproject_path, source_list, mrc_set):
    src_filerefs = []
    src_buildfiles = []
    for src in source_list:
        fr = fileref_id(src)
        bf = buildfile_id(src)
        settings = ""
        if src in mrc_set:
            settings = ' settings = {COMPILER_FLAGS = "-fno-objc-arc"; };'
        src_filerefs.append("\t\t%s /* %s */ = {isa = PBXFileReference; lastKnownFileType = sourcecode.c.objc; name = %s; path = %s; sourceTree = \"<group>\"; };" % (fr, src, q(os.path.basename(src)), q(src)))
        src_buildfiles.append("\t\t%s /* %s in Sources */ = {isa = PBXBuildFile; fileRef = %s /* %s */;%s };" % (bf, src, fr, src, settings))

    lines = []
    lines.append("// !$*UTF8*$!")
    lines.append("{")
    lines.append("\tarchiveVersion = 1;")
    lines.append("\tclasses = {")
    lines.append("\t};")
    lines.append("\tobjectVersion = 56;")
    lines.append("\tobjects = {")
    lines.append("")
    lines.append("/* Begin PBXBuildFile section */")
    lines.extend(src_buildfiles)
    lines.append("\t\t%s /* CoreFoundation.framework in Frameworks */ = {isa = PBXBuildFile; fileRef = %s /* CoreFoundation.framework */; };" % (cf_buildfile_id(), cf_fileref_id()))
    lines.append("/* End PBXBuildFile section */")
    lines.append("")
    lines.append("/* Begin PBXFileReference section */")
    lines.append("\t\t%s /* CoreFoundation.framework */ = {isa = PBXFileReference; lastKnownFileType = wrapper.framework; name = CoreFoundation.framework; path = System/Library/Frameworks/CoreFoundation.framework; sourceTree = SDKROOT; };" % cf_fileref_id())
    lines.extend(src_filerefs)
    lines.append("\t\t%s /* Foundation.framework */ = {isa = PBXFileReference; explicitFileType = wrapper.framework; includeInIndex = 0; path = Foundation.framework; sourceTree = BUILT_PRODUCTS_DIR; };" % fileref_id("Foundation.framework"))
    lines.append("/* End PBXFileReference section */")
    lines.append("")
    lines.append("/* Begin PBXFrameworksBuildPhase section */")
    lines.append("\t\t%s /* Frameworks */ = {" % frameworks_phase_id())
    lines.append("\t\t\tisa = PBXFrameworksBuildPhase;")
    lines.append("\t\t\tbuildActionMask = 2147483647;")
    lines.append("\t\t\tfiles = (")
    lines.append("\t\t\t\t%s /* CoreFoundation.framework in Frameworks */," % cf_buildfile_id())
    lines.append("\t\t\t);")
    lines.append("\t\t\trunOnlyForDeploymentPostprocessing = 0;")
    lines.append("\t\t};")
    lines.append("/* End PBXFrameworksBuildPhase section */")
    lines.append("")
    lines.append("/* Begin PBXGroup section */")
    lines.append("\t\t%s = {" % main_group_id())
    lines.append("\t\t\tisa = PBXGroup;")
    lines.append("\t\t\tchildren = (")
    lines.append("\t\t\t\t%s /* Sources */," % group_id())
    lines.append("\t\t\t\t%s /* Products */," % products_group_id())
    lines.append("\t\t\t);")
    lines.append("\t\t\tsourceTree = \"<group>\";")
    lines.append("\t\t};")
    lines.append("\t\t%s /* Products */ = {" % products_group_id())
    lines.append("\t\t\tisa = PBXGroup;")
    lines.append("\t\t\tchildren = (")
    lines.append("\t\t\t\t%s /* Foundation.framework */," % fileref_id("Foundation.framework"))
    lines.append("\t\t\t);")
    lines.append("\t\t\tname = Products;")
    lines.append("\t\t\tsourceTree = \"<group>\";")
    lines.append("\t\t};")
    lines.append("\t\t%s /* Sources */ = {" % group_id())
    lines.append("\t\t\tisa = PBXGroup;")
    lines.append("\t\t\tchildren = (")
    for src in source_list:
        lines.append("\t\t\t\t%s /* %s */," % (fileref_id(src), src))
    lines.append("\t\t\t);")
    lines.append("\t\t\tname = Sources;")
    lines.append("\t\t\tsourceTree = \"<group>\";")
    lines.append("\t\t};")
    lines.append("/* End PBXGroup section */")
    lines.append("")
    lines.append("/* Begin PBXNativeTarget section */")
    lines.append("\t\t%s /* Foundation */ = {" % target_id())
    lines.append("\t\t\tisa = PBXNativeTarget;")
    lines.append("\t\t\tbuildConfigurationList = %s /* Build configuration list for PBXNativeTarget \"Foundation\" */;" % target_configlist_id())
    lines.append("\t\t\tbuildPhases = (")
    lines.append("\t\t\t\t%s /* Generate umbrella header */," % umbrella_phase_id())
    lines.append("\t\t\t\t%s /* Sources */," % sources_phase_id())
    lines.append("\t\t\t\t%s /* Frameworks */," % frameworks_phase_id())
    lines.append("\t\t\t\t%s /* Resources */," % resources_phase_id())
    lines.append("\t\t\t);")
    lines.append("\t\t\tbuildRules = (")
    lines.append("\t\t\t);")
    lines.append("\t\t\tdependencies = (")
    lines.append("\t\t\t);")
    lines.append("\t\t\tname = Foundation;")
    lines.append("\t\t\tproductName = Foundation;")
    lines.append("\t\t\tproductReference = %s /* Foundation.framework */;" % fileref_id("Foundation.framework"))
    lines.append("\t\t\tproductType = \"com.apple.product-type.framework\";")
    lines.append("\t\t};")
    lines.append("/* End PBXNativeTarget section */")
    lines.append("")
    lines.append("/* Begin PBXProject section */")
    lines.append("\t\t%s /* Project object */ = {" % project_id())
    lines.append("\t\t\tisa = PBXProject;")
    lines.append("\t\t\tattributes = {")
    lines.append("\t\t\t\tBuildIndependentTargetsInParallel = 1;")
    lines.append("\t\t\t\tLastUpgradeCheck = 1510;")
    lines.append("\t\t\t\tTargetAttributes = {")
    lines.append("\t\t\t\t\t%s = { CreatedOnToolsVersion = 15.0; };" % target_id())
    lines.append("\t\t\t\t};")
    lines.append("\t\t\t};")
    lines.append("\t\t\tbuildConfigurationList = %s /* Build configuration list for PBXProject \"Foundation\" */;" % proj_configlist_id())
    lines.append("\t\t\tcompatibilityVersion = \"Xcode 14.0\";")
    lines.append("\t\t\tdevelopmentRegion = en;")
    lines.append("\t\t\thasScannedForEncodings = 0;")
    lines.append("\t\t\tknownRegions = (en, Base);")
    lines.append("\t\t\tmainGroup = %s;" % main_group_id())
    lines.append("\t\t\tproductRefGroup = %s /* Products */;" % products_group_id())
    lines.append("\t\t\tprojectDirPath = \"\";")
    lines.append("\t\t\tprojectRoot = \"\";")
    lines.append("\t\t\ttargets = (")
    lines.append("\t\t\t\t%s /* Foundation */," % target_id())
    lines.append("\t\t\t);")
    lines.append("\t\t};")
    lines.append("/* End PBXProject section */")
    lines.append("")
    lines.append("/* Begin PBXResourcesBuildPhase section */")
    lines.append("\t\t%s /* Resources */ = {" % resources_phase_id())
    lines.append("\t\t\tisa = PBXResourcesBuildPhase;")
    lines.append("\t\t\tbuildActionMask = 2147483647;")
    lines.append("\t\t\tfiles = (")
    lines.append("\t\t\t);")
    lines.append("\t\t\trunOnlyForDeploymentPostprocessing = 0;")
    lines.append("\t\t};")
    lines.append("/* End PBXResourcesBuildPhase section */")
    lines.append("")
    lines.append("/* Begin PBXShellScriptBuildPhase section */")
    lines.append("\t\t%s /* Generate umbrella header */ = {" % umbrella_phase_id())
    lines.append("\t\t\tisa = PBXShellScriptBuildPhase;")
    lines.append("\t\t\tbuildActionMask = 2147483647;")
    lines.append("\t\t\tfiles = (")
    lines.append("\t\t\t);")
    lines.append("\t\t\tinputPaths = (")
    lines.append("\t\t\t);")
    lines.append("\t\t\tname = \"Generate umbrella header\";")
    lines.append("\t\t\toutputPaths = (")
    lines.append("\t\t\t\t\"$(SRCROOT)/build/gen/Foundation/Foundation.h\",")
    lines.append("\t\t\t);")
    lines.append("\t\t\trunOnlyForDeploymentPostprocessing = 0;")
    lines.append("\t\t\tshellPath = /bin/sh;")
    lines.append("\t\t\tshellScript = \"make -C \\\"$SRCROOT\\\" umbrella\";")
    lines.append("\t\t};")
    lines.append("/* End PBXShellScriptBuildPhase section */")
    lines.append("")
    lines.append("/* Begin PBXSourcesBuildPhase section */")
    lines.append("\t\t%s /* Sources */ = {" % sources_phase_id())
    lines.append("\t\t\tisa = PBXSourcesBuildPhase;")
    lines.append("\t\t\tbuildActionMask = 2147483647;")
    lines.append("\t\t\tfiles = (")
    for src in source_list:
        lines.append("\t\t\t\t%s /* %s in Sources */," % (buildfile_id(src), src))
    lines.append("\t\t\t);")
    lines.append("\t\t\trunOnlyForDeploymentPostprocessing = 0;")
    lines.append("\t\t};")
    lines.append("/* End PBXSourcesBuildPhase section */")
    lines.append("")
    lines.append("/* Begin XCBuildConfiguration section */")
    for (cfg, comment, is_target, is_debug) in (
        (proj_cfg_debug_id(), 'Debug', False, True),
        (proj_cfg_release_id(), 'Release', False, False),
        (tgt_cfg_debug_id(), 'Debug', True, True),
        (tgt_cfg_release_id(), 'Release', True, False),
    ):
        lines.extend(build_config_block(cfg, comment, is_target, is_debug))
    lines.append("/* End XCBuildConfiguration section */")
    lines.append("")
    lines.append("/* Begin XCConfigurationList section */")
    for (cfgl, comment, debug_id, release_id) in (
        (proj_configlist_id(), 'Build configuration list for PBXProject "Foundation"', proj_cfg_debug_id(), proj_cfg_release_id()),
        (target_configlist_id(), 'Build configuration list for PBXNativeTarget "Foundation"', tgt_cfg_debug_id(), tgt_cfg_release_id()),
    ):
        lines.append("\t\t%s /* %s */ = {" % (cfgl, comment))
        lines.append("\t\t\tisa = XCConfigurationList;")
        lines.append("\t\t\tbuildConfigurations = (")
        lines.append("\t\t\t\t%s /* Debug */," % debug_id)
        lines.append("\t\t\t\t%s /* Release */," % release_id)
        lines.append("\t\t\t);")
        lines.append("\t\t\tdefaultConfigurationIsVisible = 0;")
        lines.append("\t\t\tdefaultConfigurationName = Release;")
        lines.append("\t\t};")
    lines.append("/* End XCConfigurationList section */")
    lines.append("")
    lines.append("\t};")
    lines.append("\trootObject = %s /* Project object */;" % project_id())
    lines.append("}")
    lines.append("")

    with open(pbxproject_path, "w", encoding="utf-8") as f:
        f.write("\n".join(lines))


def main():
    project_root = root_dir()
    source_list = list(iter_subproject_sources(project_root))
    mrc_set = read_mrc_sources(project_root)
    if not source_list:
        print("error: no subproject sources found under %s" % project_root, file=sys.stderr)
        return 1
    proj_dir = os.path.join(project_root, "Foundation.xcodeproj")
    os.makedirs(proj_dir, exist_ok=True)
    emit_project(os.path.join(proj_dir, "project.pbxproj"), source_list, mrc_set)
    print("Generated Foundation.xcodeproj: %d sources, %d MRC sources" % (len(source_list), len(mrc_set & set(source_list))))
    return 0


if __name__ == "__main__":
    sys.exit(main())