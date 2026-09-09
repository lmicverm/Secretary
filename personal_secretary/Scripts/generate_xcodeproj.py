#!/usr/bin/env python3
"""Generate Secretary.xcodeproj for the multiplatform app."""

from __future__ import annotations

import os
import uuid
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
PROJECT = ROOT / "Secretary.xcodeproj"


def uid() -> str:
    return uuid.uuid4().hex[:24].upper()


def stable(name: str) -> str:
    """Deterministic 24-char hex id from a name (Xcode-compatible)."""
    import hashlib

    return hashlib.md5(f"secretary.{name}".encode()).hexdigest()[:24].upper()


# Stable IDs so schemes survive regeneration
IDS = {
    "project": stable("project"),
    "root_group": stable("root_group"),
    "apps_group": stable("apps_group"),
    "packages_group": stable("packages_group"),
    "products_group": stable("products_group"),
    "secretary_group": stable("secretary_group"),
    "shared_group": stable("shared_group"),
    "ios_group": stable("ios_group"),
    "resources_group": stable("resources_group"),
    "share_group": stable("share_group"),
    "target_ios": stable("target_ios"),
    "target_mac": stable("target_mac"),
    "target_share": stable("target_share"),
    "sources_ios": stable("sources_ios"),
    "sources_mac": stable("sources_mac"),
    "sources_share": stable("sources_share"),
    "resources_ios": stable("resources_ios"),
    "resources_mac": stable("resources_mac"),
    "resources_share": stable("resources_share"),
    "frameworks_ios": stable("frameworks_ios"),
    "frameworks_mac": stable("frameworks_mac"),
    "frameworks_share": stable("frameworks_share"),
    "product_ios": stable("product_ios"),
    "product_mac": stable("product_mac"),
    "product_share": stable("product_share"),
    "config_list_project": stable("config_list_project"),
    "config_list_ios": stable("config_list_ios"),
    "config_list_mac": stable("config_list_mac"),
    "config_list_share": stable("config_list_share"),
    "debug_project": stable("debug_project"),
    "release_project": stable("release_project"),
    "debug_ios": stable("debug_ios"),
    "release_ios": stable("release_ios"),
    "debug_mac": stable("debug_mac"),
    "release_mac": stable("release_mac"),
    "debug_share": stable("debug_share"),
    "release_share": stable("release_share"),
    "package_ref": stable("package_ref"),
    "package_product_ios": stable("package_product_ios"),
    "package_product_mac": stable("package_product_mac"),
    "package_product_share": stable("package_product_share"),
    "embed_share": stable("embed_share"),
    "dep_share": stable("dep_share"),
    "container": stable("container"),
}


def file_ref(path: str, name: str | None = None) -> tuple[str, str]:
    i = uid()
    display = name or Path(path).name
    last = Path(path).name
    explicit = f"path = {last};" if "/" not in path.replace("\\", "/") else f"path = \"{path}\";"
    # We'll set path relative to group
    return i, display


SHARED_SOURCES = [
    "Apps/Secretary/Shared/SecretaryApp.swift",
    "Apps/Secretary/Shared/LibraryStore.swift",
    "Apps/Secretary/Shared/RootView.swift",
    "Apps/Secretary/Shared/DocumentListView.swift",
    "Apps/Secretary/Shared/DocumentDetailView.swift",
    "Apps/Secretary/Shared/SettingsView.swift",
    "Apps/Secretary/Shared/SecretaryTheme.swift",
]

IOS_ONLY = [
    "Apps/Secretary/iOS/ImportToolbarButtons.swift",
]

MAC_ONLY: list[str] = []

SHARE_SOURCES = [
    "Apps/ShareExtension/ShareViewController.swift",
]

RESOURCES = [
    ("Apps/Secretary/Resources/Assets.xcassets", "Assets.xcassets"),
]


def main() -> None:
    # Optional: export SECRETARY_DEVELOPMENT_TEAM=XXXXXXXXXX before regenerating,
    # or put the team id in Config/DeveloperTeam.txt (gitignored).
    team = os.environ.get("SECRETARY_DEVELOPMENT_TEAM", "").strip()
    team_file = ROOT / "Config" / "DeveloperTeam.txt"
    if not team and team_file.exists():
        team = team_file.read_text(encoding="utf-8").strip().splitlines()[0].strip()

    file_entries: dict[str, tuple[str, str]] = {}  # path -> (id, filename)

    def add_file(path: str) -> str:
        if path in file_entries:
            return file_entries[path][0]
        i = uid()
        file_entries[path] = (i, Path(path).name)
        return i

    for p in SHARED_SOURCES + IOS_ONLY + SHARE_SOURCES:
        add_file(p)

    assets_id = add_file("Apps/Secretary/Resources/Assets.xcassets")
    info_ios = add_file("Apps/Secretary/Resources/Info-iOS.plist")
    info_mac = add_file("Apps/Secretary/Resources/Info-macOS.plist")
    info_share = add_file("Apps/ShareExtension/Info.plist")
    ent_ios = add_file("Apps/Secretary/Resources/Secretary.entitlements")
    ent_mac = add_file("Apps/Secretary/Resources/Secretary-macOS.entitlements")
    ent_share = add_file("Apps/ShareExtension/ShareExtension.entitlements")

    # Build PBXFileReference section
    refs = []
    for path, (fid, name) in file_entries.items():
        rel = path
        if name.endswith(".xcassets"):
            refs.append(
                f'\t\t{fid} /* {name} */ = {{isa = PBXFileReference; lastKnownFileType = folder.assetcatalog; path = {name}; sourceTree = "<group>"; }};'
            )
        elif name.endswith(".plist"):
            refs.append(
                f'\t\t{fid} /* {name} */ = {{isa = PBXFileReference; lastKnownFileType = text.plist.xml; path = {name}; sourceTree = "<group>"; }};'
            )
        elif name.endswith(".entitlements"):
            refs.append(
                f'\t\t{fid} /* {name} */ = {{isa = PBXFileReference; lastKnownFileType = text.plist.entitlements; path = {name}; sourceTree = "<group>"; }};'
            )
        else:
            refs.append(
                f'\t\t{fid} /* {name} */ = {{isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = {name}; sourceTree = "<group>"; }};'
            )

    refs.append(
        f'\t\t{IDS["product_ios"]} /* Secretary.app */ = {{isa = PBXFileReference; explicitFileType = wrapper.application; includeInIndex = 0; path = Secretary.app; sourceTree = BUILT_PRODUCTS_DIR; }};'
    )
    refs.append(
        f'\t\t{IDS["product_mac"]} /* SecretaryMac.app */ = {{isa = PBXFileReference; explicitFileType = wrapper.application; includeInIndex = 0; path = SecretaryMac.app; sourceTree = BUILT_PRODUCTS_DIR; }};'
    )
    refs.append(
        f'\t\t{IDS["product_share"]} /* ShareExtension.appex */ = {{isa = PBXFileReference; explicitFileType = "wrapper.app-extension"; includeInIndex = 0; path = ShareExtension.appex; sourceTree = BUILT_PRODUCTS_DIR; }};'
    )

    def build_phase_files(paths: list[str], phase_name: str) -> tuple[str, list[str]]:
        lines = []
        build_ids = []
        for path in paths:
            bid = uid()
            build_ids.append(bid)
            name = Path(path).name
            fid = file_entries[path][0]
            lines.append(f"\t\t{bid} /* {name} in {phase_name} */ = {{isa = PBXBuildFile; fileRef = {fid} /* {name} */; }};")
        return "\n".join(lines), build_ids

    build_files = []
    shared_ios_build, shared_ios_ids = build_phase_files(SHARED_SOURCES + IOS_ONLY, "Sources")
    shared_mac_build, shared_mac_ids = build_phase_files(SHARED_SOURCES + MAC_ONLY, "Sources")
    share_build, share_ids = build_phase_files(SHARE_SOURCES, "Sources")
    build_files.extend([shared_ios_build, shared_mac_build, share_build])

    assets_build_ios = uid()
    assets_build_mac = uid()
    embed_build = uid()
    build_files.append(
        f"\t\t{assets_build_ios} /* Assets.xcassets in Resources */ = {{isa = PBXBuildFile; fileRef = {assets_id} /* Assets.xcassets */; }};"
    )
    build_files.append(
        f"\t\t{assets_build_mac} /* Assets.xcassets in Resources */ = {{isa = PBXBuildFile; fileRef = {assets_id} /* Assets.xcassets */; }};"
    )
    build_files.append(
        f'\t\t{embed_build} /* ShareExtension.appex in Embed Foundation Extensions */ = {{isa = PBXBuildFile; fileRef = {IDS["product_share"]} /* ShareExtension.appex */; settings = {{ATTRIBUTES = (RemoveHeadersOnCopy, ); }}; }};'
    )

    pkg_ios = uid()
    pkg_mac = uid()
    pkg_share = uid()
    build_files.append(
        f'\t\t{pkg_ios} /* SecretaryCore in Frameworks */ = {{isa = PBXBuildFile; productRef = {IDS["package_product_ios"]} /* SecretaryCore */; }};'
    )
    build_files.append(
        f'\t\t{pkg_mac} /* SecretaryCore in Frameworks */ = {{isa = PBXBuildFile; productRef = {IDS["package_product_mac"]} /* SecretaryCore */; }};'
    )
    build_files.append(
        f'\t\t{pkg_share} /* SecretaryCore in Frameworks */ = {{isa = PBXBuildFile; productRef = {IDS["package_product_share"]} /* SecretaryCore */; }};'
    )

    # Groups — paths relative so Xcode finds files
    shared_children = "\n".join(
        f'\t\t\t\t{file_entries[p][0]} /* {Path(p).name} */,' for p in SHARED_SOURCES
    )
    ios_children = "\n".join(
        f'\t\t\t\t{file_entries[p][0]} /* {Path(p).name} */,' for p in IOS_ONLY
    )
    resources_children = "\n".join(
        [
            f'\t\t\t\t{assets_id} /* Assets.xcassets */,',
            f'\t\t\t\t{info_ios} /* Info-iOS.plist */,',
            f'\t\t\t\t{info_mac} /* Info-macOS.plist */,',
            f'\t\t\t\t{ent_ios} /* Secretary.entitlements */,',
            f'\t\t\t\t{ent_mac} /* Secretary-macOS.entitlements */,',
        ]
    )
    share_children = "\n".join(
        [
            f'\t\t\t\t{file_entries[SHARE_SOURCES[0]][0]} /* ShareViewController.swift */,',
            f'\t\t\t\t{info_share} /* Info.plist */,',
            f'\t\t\t\t{ent_share} /* ShareExtension.entitlements */,',
        ]
    )

    # Without a Development Team, embedding ShareExtension blocks iOS Debug builds in Xcode.
    # Keep the target in the project; only wire it into the app when a team is configured.
    embed_share = bool(team)
    ios_build_phases = f"""
				{IDS["sources_ios"]} /* Sources */,
				{IDS["frameworks_ios"]} /* Frameworks */,
				{IDS["resources_ios"]} /* Resources */,"""
    if embed_share:
        ios_build_phases += f"""
				{IDS["embed_share"]} /* Embed Foundation Extensions */,"""
    ios_dependencies = (
        f"""
				{IDS["dep_share"]} /* PBXTargetDependency */,"""
        if embed_share
        else ""
    )

    copy_files_section = ""
    container_section = ""
    dep_section = ""
    if embed_share:
        container_section = f"""
/* Begin PBXContainerItemProxy section */
		{IDS["container"]} /* PBXContainerItemProxy */ = {{
			isa = PBXContainerItemProxy;
			containerPortal = {IDS["project"]} /* Project object */;
			proxyType = 1;
			remoteGlobalIDString = {IDS["target_share"]};
			remoteInfo = ShareExtension;
		}};
/* End PBXContainerItemProxy section */
"""
        copy_files_section = f"""
/* Begin PBXCopyFilesBuildPhase section */
		{IDS["embed_share"]} /* Embed Foundation Extensions */ = {{
			isa = PBXCopyFilesBuildPhase;
			buildActionMask = 2147483647;
			dstPath = "";
			dstSubfolderSpec = 13;
			files = (
				{embed_build} /* ShareExtension.appex in Embed Foundation Extensions */,
			);
			name = "Embed Foundation Extensions";
			runOnlyForDeploymentPostprocessing = 0;
		}};
/* End PBXCopyFilesBuildPhase section */
"""
        dep_section = f"""
/* Begin PBXTargetDependency section */
		{IDS["dep_share"]} /* PBXTargetDependency */ = {{
			isa = PBXTargetDependency;
			target = {IDS["target_share"]} /* ShareExtension */;
			targetProxy = {IDS["container"]} /* PBXContainerItemProxy */;
		}};
/* End PBXTargetDependency section */
"""

    # Fix file paths: groups need correct path attributes
    # Shared group path = Apps/Secretary/Shared
    # Re-write file refs to just filenames under group path

    pbx = f'''// !$*UTF8*$!
{{
	archiveVersion = 1;
	classes = {{
	}};
	objectVersion = 56;
	objects = {{

/* Begin PBXBuildFile section */
{chr(10).join(build_files)}
/* End PBXBuildFile section */
{container_section}{copy_files_section}
/* Begin PBXFileReference section */
{chr(10).join(refs)}
/* End PBXFileReference section */

/* Begin PBXFrameworksBuildPhase section */
		{IDS["frameworks_ios"]} /* Frameworks */ = {{
			isa = PBXFrameworksBuildPhase;
			buildActionMask = 2147483647;
			files = (
				{pkg_ios} /* SecretaryCore in Frameworks */,
			);
			runOnlyForDeploymentPostprocessing = 0;
		}};
		{IDS["frameworks_mac"]} /* Frameworks */ = {{
			isa = PBXFrameworksBuildPhase;
			buildActionMask = 2147483647;
			files = (
				{pkg_mac} /* SecretaryCore in Frameworks */,
			);
			runOnlyForDeploymentPostprocessing = 0;
		}};
		{IDS["frameworks_share"]} /* Frameworks */ = {{
			isa = PBXFrameworksBuildPhase;
			buildActionMask = 2147483647;
			files = (
				{pkg_share} /* SecretaryCore in Frameworks */,
			);
			runOnlyForDeploymentPostprocessing = 0;
		}};
/* End PBXFrameworksBuildPhase section */

/* Begin PBXGroup section */
		{IDS["root_group"]} = {{
			isa = PBXGroup;
			children = (
				{IDS["apps_group"]} /* Apps */,
				{IDS["packages_group"]} /* Packages */,
				{IDS["products_group"]} /* Products */,
			);
			sourceTree = "<group>";
		}};
		{IDS["apps_group"]} /* Apps */ = {{
			isa = PBXGroup;
			children = (
				{IDS["secretary_group"]} /* Secretary */,
				{IDS["share_group"]} /* ShareExtension */,
			);
			path = Apps;
			sourceTree = "<group>";
		}};
		{IDS["secretary_group"]} /* Secretary */ = {{
			isa = PBXGroup;
			children = (
				{IDS["shared_group"]} /* Shared */,
				{IDS["ios_group"]} /* iOS */,
				{IDS["resources_group"]} /* Resources */,
			);
			path = Secretary;
			sourceTree = "<group>";
		}};
		{IDS["shared_group"]} /* Shared */ = {{
			isa = PBXGroup;
			children = (
{shared_children}
			);
			path = Shared;
			sourceTree = "<group>";
		}};
		{IDS["ios_group"]} /* iOS */ = {{
			isa = PBXGroup;
			children = (
{ios_children}
			);
			path = iOS;
			sourceTree = "<group>";
		}};
		{IDS["resources_group"]} /* Resources */ = {{
			isa = PBXGroup;
			children = (
{resources_children}
			);
			path = Resources;
			sourceTree = "<group>";
		}};
		{IDS["share_group"]} /* ShareExtension */ = {{
			isa = PBXGroup;
			children = (
{share_children}
			);
			path = ShareExtension;
			sourceTree = "<group>";
		}};
		{IDS["packages_group"]} /* Packages */ = {{
			isa = PBXGroup;
			children = (
			);
			path = Packages;
			sourceTree = "<group>";
		}};
		{IDS["products_group"]} /* Products */ = {{
			isa = PBXGroup;
			children = (
				{IDS["product_ios"]} /* Secretary.app */,
				{IDS["product_mac"]} /* SecretaryMac.app */,
				{IDS["product_share"]} /* ShareExtension.appex */,
			);
			name = Products;
			sourceTree = "<group>";
		}};
/* End PBXGroup section */

/* Begin PBXNativeTarget section */
		{IDS["target_ios"]} /* Secretary */ = {{
			isa = PBXNativeTarget;
			buildConfigurationList = {IDS["config_list_ios"]} /* Build configuration list for PBXNativeTarget "Secretary" */;
			buildPhases = ({ios_build_phases}
			);
			buildRules = (
			);
			dependencies = ({ios_dependencies}
			);
			name = Secretary;
			packageProductDependencies = (
				{IDS["package_product_ios"]} /* SecretaryCore */,
			);
			productName = Secretary;
			productReference = {IDS["product_ios"]} /* Secretary.app */;
			productType = "com.apple.product-type.application";
		}};
		{IDS["target_mac"]} /* SecretaryMac */ = {{
			isa = PBXNativeTarget;
			buildConfigurationList = {IDS["config_list_mac"]} /* Build configuration list for PBXNativeTarget "SecretaryMac" */;
			buildPhases = (
				{IDS["sources_mac"]} /* Sources */,
				{IDS["frameworks_mac"]} /* Frameworks */,
				{IDS["resources_mac"]} /* Resources */,
			);
			buildRules = (
			);
			dependencies = (
			);
			name = SecretaryMac;
			packageProductDependencies = (
				{IDS["package_product_mac"]} /* SecretaryCore */,
			);
			productName = SecretaryMac;
			productReference = {IDS["product_mac"]} /* SecretaryMac.app */;
			productType = "com.apple.product-type.application";
		}};
		{IDS["target_share"]} /* ShareExtension */ = {{
			isa = PBXNativeTarget;
			buildConfigurationList = {IDS["config_list_share"]} /* Build configuration list for PBXNativeTarget "ShareExtension" */;
			buildPhases = (
				{IDS["sources_share"]} /* Sources */,
				{IDS["frameworks_share"]} /* Frameworks */,
				{IDS["resources_share"]} /* Resources */,
			);
			buildRules = (
			);
			dependencies = (
			);
			name = ShareExtension;
			packageProductDependencies = (
				{IDS["package_product_share"]} /* SecretaryCore */,
			);
			productName = ShareExtension;
			productReference = {IDS["product_share"]} /* ShareExtension.appex */;
			productType = "com.apple.product-type.app-extension";
		}};
/* End PBXNativeTarget section */

/* Begin PBXProject section */
		{IDS["project"]} /* Project object */ = {{
			isa = PBXProject;
			attributes = {{
				BuildIndependentTargetsInParallel = 1;
				LastSwiftUpdateCheck = 1600;
				LastUpgradeCheck = 1600;
			}};
			buildConfigurationList = {IDS["config_list_project"]} /* Build configuration list for PBXProject "Secretary" */;
			compatibilityVersion = "Xcode 15.0";
			developmentRegion = en;
			hasScannedForEncodings = 0;
			knownRegions = (
				en,
				Base,
			);
			mainGroup = {IDS["root_group"]};
			packageReferences = (
				{IDS["package_ref"]} /* XCLocalSwiftPackageReference "Packages/SecretaryCore" */,
			);
			productRefGroup = {IDS["products_group"]} /* Products */;
			projectDirPath = "";
			projectRoot = "";
			targets = (
				{IDS["target_ios"]} /* Secretary */,
				{IDS["target_mac"]} /* SecretaryMac */,
				{IDS["target_share"]} /* ShareExtension */,
			);
		}};
/* End PBXProject section */

/* Begin PBXResourcesBuildPhase section */
		{IDS["resources_ios"]} /* Resources */ = {{
			isa = PBXResourcesBuildPhase;
			buildActionMask = 2147483647;
			files = (
				{assets_build_ios} /* Assets.xcassets in Resources */,
			);
			runOnlyForDeploymentPostprocessing = 0;
		}};
		{IDS["resources_mac"]} /* Resources */ = {{
			isa = PBXResourcesBuildPhase;
			buildActionMask = 2147483647;
			files = (
				{assets_build_mac} /* Assets.xcassets in Resources */,
			);
			runOnlyForDeploymentPostprocessing = 0;
		}};
		{IDS["resources_share"]} /* Resources */ = {{
			isa = PBXResourcesBuildPhase;
			buildActionMask = 2147483647;
			files = (
			);
			runOnlyForDeploymentPostprocessing = 0;
		}};
/* End PBXResourcesBuildPhase section */

/* Begin PBXSourcesBuildPhase section */
		{IDS["sources_ios"]} /* Sources */ = {{
			isa = PBXSourcesBuildPhase;
			buildActionMask = 2147483647;
			files = (
{chr(10).join(f"\t\t\t\t{bid} /* {Path(p).name} in Sources */," for bid, p in zip(shared_ios_ids, SHARED_SOURCES + IOS_ONLY))}
			);
			runOnlyForDeploymentPostprocessing = 0;
		}};
		{IDS["sources_mac"]} /* Sources */ = {{
			isa = PBXSourcesBuildPhase;
			buildActionMask = 2147483647;
			files = (
{chr(10).join(f"\t\t\t\t{bid} /* {Path(p).name} in Sources */," for bid, p in zip(shared_mac_ids, SHARED_SOURCES + MAC_ONLY))}
			);
			runOnlyForDeploymentPostprocessing = 0;
		}};
		{IDS["sources_share"]} /* Sources */ = {{
			isa = PBXSourcesBuildPhase;
			buildActionMask = 2147483647;
			files = (
{chr(10).join(f"\t\t\t\t{bid} /* {Path(p).name} in Sources */," for bid, p in zip(share_ids, SHARE_SOURCES))}
			);
			runOnlyForDeploymentPostprocessing = 0;
		}};
/* End PBXSourcesBuildPhase section */
{dep_section}
/* Begin XCBuildConfiguration section */
		{IDS["debug_project"]} /* Debug */ = {{
			isa = XCBuildConfiguration;
			buildSettings = {{
				ALWAYS_SEARCH_USER_PATHS = NO;
				CLANG_ENABLE_MODULES = YES;
				COPY_PHASE_STRIP = NO;
				DEBUG_INFORMATION_FORMAT = dwarf;
				ENABLE_TESTABILITY = YES;
				GCC_DYNAMIC_NO_PIC = NO;
				MTL_ENABLE_DEBUG_INFO = INCLUDE_SOURCE;
				ONLY_ACTIVE_ARCH = YES;
				SWIFT_ACTIVE_COMPILATION_CONDITIONS = "DEBUG $(inherited)";
				SWIFT_OPTIMIZATION_LEVEL = "-Onone";
				SWIFT_VERSION = 5.0;
			}};
			name = Debug;
		}};
		{IDS["release_project"]} /* Release */ = {{
			isa = XCBuildConfiguration;
			buildSettings = {{
				ALWAYS_SEARCH_USER_PATHS = NO;
				CLANG_ENABLE_MODULES = YES;
				COPY_PHASE_STRIP = NO;
				DEBUG_INFORMATION_FORMAT = "dwarf-with-dsym";
				MTL_ENABLE_DEBUG_INFO = NO;
				SWIFT_COMPILATION_MODE = wholemodule;
				SWIFT_VERSION = 5.0;
			}};
			name = Release;
		}};
		{IDS["debug_ios"]} /* Debug */ = {{
			isa = XCBuildConfiguration;
			buildSettings = {{
				ASSETCATALOG_COMPILER_APPICON_NAME = "";
				ASSETCATALOG_COMPILER_GENERATE_SWIFT_ASSET_SYMBOL_EXTENSIONS = YES;
				CODE_SIGN_ENTITLEMENTS = Apps/Secretary/Resources/Secretary.entitlements;
				CODE_SIGN_IDENTITY = "-";
				CODE_SIGN_STYLE = Automatic;
				CODE_SIGNING_ALLOWED = YES;
				CURRENT_PROJECT_VERSION = 1;
				DEVELOPMENT_TEAM = "{team}";
				ENABLE_PREVIEWS = YES;
				GENERATE_INFOPLIST_FILE = NO;
				INFOPLIST_FILE = "Apps/Secretary/Resources/Info-iOS.plist";
				IPHONEOS_DEPLOYMENT_TARGET = 17.0;
				LD_RUNPATH_SEARCH_PATHS = (
					"$(inherited)",
					"@executable_path/Frameworks",
				);
				MARKETING_VERSION = 1.0;
				PRODUCT_BUNDLE_IDENTIFIER = be.vermeir.secretary;
				PRODUCT_NAME = Secretary;
				SDKROOT = iphoneos;
				SUPPORTED_PLATFORMS = "iphoneos iphonesimulator";
				SUPPORTS_MACCATALYST = NO;
				SWIFT_EMIT_LOC_STRINGS = YES;
				TARGETED_DEVICE_FAMILY = "1,2";
			}};
			name = Debug;
		}};
		{IDS["release_ios"]} /* Release */ = {{
			isa = XCBuildConfiguration;
			buildSettings = {{
				ASSETCATALOG_COMPILER_APPICON_NAME = "";
				ASSETCATALOG_COMPILER_GENERATE_SWIFT_ASSET_SYMBOL_EXTENSIONS = YES;
				CODE_SIGN_ENTITLEMENTS = Apps/Secretary/Resources/Secretary.entitlements;
				CODE_SIGN_STYLE = Automatic;
				CURRENT_PROJECT_VERSION = 1;
				DEVELOPMENT_TEAM = "{team}";
				ENABLE_PREVIEWS = YES;
				GENERATE_INFOPLIST_FILE = NO;
				INFOPLIST_FILE = "Apps/Secretary/Resources/Info-iOS.plist";
				IPHONEOS_DEPLOYMENT_TARGET = 17.0;
				LD_RUNPATH_SEARCH_PATHS = (
					"$(inherited)",
					"@executable_path/Frameworks",
				);
				MARKETING_VERSION = 1.0;
				PRODUCT_BUNDLE_IDENTIFIER = be.vermeir.secretary;
				PRODUCT_NAME = Secretary;
				SDKROOT = iphoneos;
				SUPPORTED_PLATFORMS = "iphoneos iphonesimulator";
				SUPPORTS_MACCATALYST = NO;
				SWIFT_EMIT_LOC_STRINGS = YES;
				TARGETED_DEVICE_FAMILY = "1,2";
				VALIDATE_PRODUCT = YES;
			}};
			name = Release;
		}};
		{IDS["debug_mac"]} /* Debug */ = {{
			isa = XCBuildConfiguration;
			buildSettings = {{
				ASSETCATALOG_COMPILER_APPICON_NAME = "";
				ASSETCATALOG_COMPILER_GENERATE_SWIFT_ASSET_SYMBOL_EXTENSIONS = YES;
				CODE_SIGN_ENTITLEMENTS = "Apps/Secretary/Resources/Secretary-macOS.entitlements";
				CODE_SIGN_STYLE = Automatic;
				COMBINE_HIDPI_IMAGES = YES;
				CURRENT_PROJECT_VERSION = 1;
				DEVELOPMENT_TEAM = "{team}";
				ENABLE_HARDENED_RUNTIME = YES;
				ENABLE_PREVIEWS = YES;
				GENERATE_INFOPLIST_FILE = NO;
				INFOPLIST_FILE = "Apps/Secretary/Resources/Info-macOS.plist";
				LD_RUNPATH_SEARCH_PATHS = (
					"$(inherited)",
					"@executable_path/../Frameworks",
				);
				MACOSX_DEPLOYMENT_TARGET = 14.0;
				MARKETING_VERSION = 1.0;
				PRODUCT_BUNDLE_IDENTIFIER = be.vermeir.secretary;
				PRODUCT_NAME = SecretaryMac;
				SDKROOT = macosx;
				SWIFT_EMIT_LOC_STRINGS = YES;
			}};
			name = Debug;
		}};
		{IDS["release_mac"]} /* Release */ = {{
			isa = XCBuildConfiguration;
			buildSettings = {{
				ASSETCATALOG_COMPILER_APPICON_NAME = "";
				ASSETCATALOG_COMPILER_GENERATE_SWIFT_ASSET_SYMBOL_EXTENSIONS = YES;
				CODE_SIGN_ENTITLEMENTS = "Apps/Secretary/Resources/Secretary-macOS.entitlements";
				CODE_SIGN_STYLE = Automatic;
				COMBINE_HIDPI_IMAGES = YES;
				CURRENT_PROJECT_VERSION = 1;
				DEVELOPMENT_TEAM = "{team}";
				ENABLE_HARDENED_RUNTIME = YES;
				ENABLE_PREVIEWS = YES;
				GENERATE_INFOPLIST_FILE = NO;
				INFOPLIST_FILE = "Apps/Secretary/Resources/Info-macOS.plist";
				LD_RUNPATH_SEARCH_PATHS = (
					"$(inherited)",
					"@executable_path/../Frameworks",
				);
				MACOSX_DEPLOYMENT_TARGET = 14.0;
				MARKETING_VERSION = 1.0;
				PRODUCT_BUNDLE_IDENTIFIER = be.vermeir.secretary;
				PRODUCT_NAME = SecretaryMac;
				SDKROOT = macosx;
				SWIFT_EMIT_LOC_STRINGS = YES;
			}};
			name = Release;
		}};
		{IDS["debug_share"]} /* Debug */ = {{
			isa = XCBuildConfiguration;
			buildSettings = {{
				CODE_SIGN_ENTITLEMENTS = Apps/ShareExtension/ShareExtension.entitlements;
				CODE_SIGN_IDENTITY = "-";
				CODE_SIGN_STYLE = Automatic;
				CODE_SIGNING_ALLOWED = YES;
				CURRENT_PROJECT_VERSION = 1;
				DEVELOPMENT_TEAM = "{team}";
				GENERATE_INFOPLIST_FILE = NO;
				INFOPLIST_FILE = Apps/ShareExtension/Info.plist;
				IPHONEOS_DEPLOYMENT_TARGET = 17.0;
				LD_RUNPATH_SEARCH_PATHS = (
					"$(inherited)",
					"@executable_path/Frameworks",
					"@executable_path/../../Frameworks",
				);
				MARKETING_VERSION = 1.0;
				PRODUCT_BUNDLE_IDENTIFIER = be.vermeir.secretary.share;
				PRODUCT_NAME = "$(TARGET_NAME)";
				SDKROOT = iphoneos;
				SKIP_INSTALL = YES;
				SUPPORTED_PLATFORMS = "iphoneos iphonesimulator";
				SWIFT_EMIT_LOC_STRINGS = YES;
				TARGETED_DEVICE_FAMILY = "1,2";
			}};
			name = Debug;
		}};
		{IDS["release_share"]} /* Release */ = {{
			isa = XCBuildConfiguration;
			buildSettings = {{
				CODE_SIGN_ENTITLEMENTS = Apps/ShareExtension/ShareExtension.entitlements;
				CODE_SIGN_STYLE = Automatic;
				CURRENT_PROJECT_VERSION = 1;
				DEVELOPMENT_TEAM = "{team}";
				GENERATE_INFOPLIST_FILE = NO;
				INFOPLIST_FILE = Apps/ShareExtension/Info.plist;
				IPHONEOS_DEPLOYMENT_TARGET = 17.0;
				LD_RUNPATH_SEARCH_PATHS = (
					"$(inherited)",
					"@executable_path/Frameworks",
					"@executable_path/../../Frameworks",
				);
				MARKETING_VERSION = 1.0;
				PRODUCT_BUNDLE_IDENTIFIER = be.vermeir.secretary.share;
				PRODUCT_NAME = "$(TARGET_NAME)";
				SDKROOT = iphoneos;
				SKIP_INSTALL = YES;
				SUPPORTED_PLATFORMS = "iphoneos iphonesimulator";
				SWIFT_EMIT_LOC_STRINGS = YES;
				TARGETED_DEVICE_FAMILY = "1,2";
				VALIDATE_PRODUCT = YES;
			}};
			name = Release;
		}};
/* End XCBuildConfiguration section */

/* Begin XCConfigurationList section */
		{IDS["config_list_project"]} /* Build configuration list for PBXProject "Secretary" */ = {{
			isa = XCConfigurationList;
			buildConfigurations = (
				{IDS["debug_project"]} /* Debug */,
				{IDS["release_project"]} /* Release */,
			);
			defaultConfigurationIsVisible = 0;
			defaultConfigurationName = Release;
		}};
		{IDS["config_list_ios"]} /* Build configuration list for PBXNativeTarget "Secretary" */ = {{
			isa = XCConfigurationList;
			buildConfigurations = (
				{IDS["debug_ios"]} /* Debug */,
				{IDS["release_ios"]} /* Release */,
			);
			defaultConfigurationIsVisible = 0;
			defaultConfigurationName = Release;
		}};
		{IDS["config_list_mac"]} /* Build configuration list for PBXNativeTarget "SecretaryMac" */ = {{
			isa = XCConfigurationList;
			buildConfigurations = (
				{IDS["debug_mac"]} /* Debug */,
				{IDS["release_mac"]} /* Release */,
			);
			defaultConfigurationIsVisible = 0;
			defaultConfigurationName = Release;
		}};
		{IDS["config_list_share"]} /* Build configuration list for PBXNativeTarget "ShareExtension" */ = {{
			isa = XCConfigurationList;
			buildConfigurations = (
				{IDS["debug_share"]} /* Debug */,
				{IDS["release_share"]} /* Release */,
			);
			defaultConfigurationIsVisible = 0;
			defaultConfigurationName = Release;
		}};
/* End XCConfigurationList section */

/* Begin XCLocalSwiftPackageReference section */
		{IDS["package_ref"]} /* XCLocalSwiftPackageReference "Packages/SecretaryCore" */ = {{
			isa = XCLocalSwiftPackageReference;
			relativePath = Packages/SecretaryCore;
		}};
/* End XCLocalSwiftPackageReference section */

/* Begin XCSwiftPackageProductDependency section */
		{IDS["package_product_ios"]} /* SecretaryCore */ = {{
			isa = XCSwiftPackageProductDependency;
			package = {IDS["package_ref"]} /* XCLocalSwiftPackageReference "Packages/SecretaryCore" */;
			productName = SecretaryCore;
		}};
		{IDS["package_product_mac"]} /* SecretaryCore */ = {{
			isa = XCSwiftPackageProductDependency;
			package = {IDS["package_ref"]} /* XCLocalSwiftPackageReference "Packages/SecretaryCore" */;
			productName = SecretaryCore;
		}};
		{IDS["package_product_share"]} /* SecretaryCore */ = {{
			isa = XCSwiftPackageProductDependency;
			package = {IDS["package_ref"]} /* XCLocalSwiftPackageReference "Packages/SecretaryCore" */;
			productName = SecretaryCore;
		}};
/* End XCSwiftPackageProductDependency section */
	}};
	rootObject = {IDS["project"]} /* Project object */;
}}
'''

    PROJECT.mkdir(parents=True, exist_ok=True)
    (PROJECT / "project.pbxproj").write_text(pbx)
    workspace = PROJECT / "project.xcworkspace"
    workspace.mkdir(exist_ok=True)
    (workspace / "contents.xcworkspacedata").write_text(
        """<?xml version="1.0" encoding="UTF-8"?>
<Workspace
   version = "1.0">
   <FileRef
      location = "self:">
   </FileRef>
</Workspace>
"""
    )
    write_scheme("SecretaryMac", IDS["target_mac"], "SecretaryMac.app")
    write_scheme("Secretary", IDS["target_ios"], "Secretary.app")
    print(f"Wrote {PROJECT}")


def write_scheme(name: str, target_id: str, product: str) -> None:
    schemes = PROJECT / "xcshareddata" / "xcschemes"
    schemes.mkdir(parents=True, exist_ok=True)
    (schemes / f"{name}.xcscheme").write_text(
        f"""<?xml version="1.0" encoding="UTF-8"?>
<Scheme
   LastUpgradeVersion = "1600"
   version = "1.7">
   <BuildAction parallelizeBuildables = "YES" buildImplicitDependencies = "YES">
      <BuildActionEntries>
         <BuildActionEntry buildForTesting = "YES" buildForRunning = "YES" buildForProfiling = "YES" buildForArchiving = "YES" buildForAnalyzing = "YES">
            <BuildableReference BuildableIdentifier = "primary" BlueprintIdentifier = "{target_id}" BuildableName = "{product}" BlueprintName = "{name}" ReferencedContainer = "container:Secretary.xcodeproj"/>
         </BuildActionEntry>
      </BuildActionEntries>
   </BuildAction>
   <LaunchAction buildConfiguration = "Debug" selectedDebuggerIdentifier = "Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier = "Xcode.DebuggerFoundation.Launcher.LLDB" launchStyle = "0" useCustomWorkingDirectory = "NO" ignoresPersistentStateOnLaunch = "NO" debugDocumentVersioning = "YES" debugServiceExtension = "internal" allowLocationSimulation = "YES">
      <BuildableProductRunnable runnableDebuggingMode = "0">
         <BuildableReference BuildableIdentifier = "primary" BlueprintIdentifier = "{target_id}" BuildableName = "{product}" BlueprintName = "{name}" ReferencedContainer = "container:Secretary.xcodeproj"/>
      </BuildableProductRunnable>
   </LaunchAction>
   <ProfileAction buildConfiguration = "Release" shouldUseLaunchSchemeArgsEnv = "YES" savedToolIdentifier = "" useCustomWorkingDirectory = "NO" debugDocumentVersioning = "YES">
      <BuildableProductRunnable runnableDebuggingMode = "0">
         <BuildableReference BuildableIdentifier = "primary" BlueprintIdentifier = "{target_id}" BuildableName = "{product}" BlueprintName = "{name}" ReferencedContainer = "container:Secretary.xcodeproj"/>
      </BuildableProductRunnable>
   </ProfileAction>
   <AnalyzeAction buildConfiguration = "Debug"/>
   <ArchiveAction buildConfiguration = "Release" revealArchiveInOrganizer = "YES"/>
</Scheme>
"""
    )


if __name__ == "__main__":
    main()
