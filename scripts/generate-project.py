#!/usr/bin/env python3
"""Create a self-contained Xcode project for the authored iOS app. No network."""
import hashlib
import json
from pathlib import Path
import plistlib
import subprocess

ROOT = Path(__file__).resolve().parents[1]
APP = ROOT / "App"
objects = {}

# Keep identities chosen in Xcode when refreshing the generated source graph.
# Signing is enabled for normal Xcode Archive; build-ipa.py opts out explicitly.
saved_target_settings = {}
existing_project = APP / "RoomRemote.xcodeproj/project.pbxproj"
if existing_project.exists():
    previous = json.loads(subprocess.check_output([
        "plutil", "-convert", "json", "-o", "-", str(existing_project)
    ]))
    previous_objects = previous["objects"]
    for target in previous_objects.values():
        if target.get("isa") != "PBXNativeTarget":
            continue
        configurations = previous_objects[target["buildConfigurationList"]]["buildConfigurations"]
        saved_target_settings[target["name"]] = {
            previous_objects[key]["name"]: previous_objects[key]["buildSettings"] for key in configurations
        }

# The developer team and the app's bundle ID are personal, so they live in the
# untracked App/Signing.local.xcconfig instead of the committed project file.
preserved_keys = ["PRODUCT_BUNDLE_IDENTIFIER", "CODE_SIGN_STYLE",
                  "CODE_SIGN_IDENTITY", "CODE_SIGN_ENTITLEMENTS", "PROVISIONING_PROFILE_SPECIFIER",
                  "PROVISIONING_PROFILE"]
app_signing = saved_target_settings.get("RoomRemote", {})
default_team = app_signing.get("Release", app_signing.get("Debug", {})).get("DEVELOPMENT_TEAM")
saved_bundle = app_signing.get("Release", app_signing.get("Debug", {})).get("PRODUCT_BUNDLE_IDENTIFIER")
local_signing = APP / "Signing.local.xcconfig"
local_text = local_signing.read_text() if local_signing.exists() else ""
for key, value in [("DEVELOPMENT_TEAM", default_team), ("PRODUCT_BUNDLE_IDENTIFIER", saved_bundle)]:
    if value and key not in local_text:
        local_text += f"{key} = {value}\n"
if local_text: local_signing.write_text(local_text)

def ident(value):
    return hashlib.sha256(value.encode()).hexdigest()[:24].upper()

def add(object_name, **fields):
    key = ident(object_name)
    objects[key] = fields
    return key

def config(name, settings):
    target_name = {"app": "RoomRemote", "test": "RoomRemoteTests", "ui": "RoomRemoteUITests"}.get(name.split(".")[0])
    if target_name:
        previous = saved_target_settings.get(target_name, {}).get(name.split(".")[-1], {})
        settings = dict(settings)
        for key in preserved_keys:
            if target_name == "RoomRemote" and key == "PRODUCT_BUNDLE_IDENTIFIER": continue
            if key in previous and (key != "CODE_SIGN_IDENTITY" or previous[key]):
                settings[key] = previous[key]
    fields = {"isa": "XCBuildConfiguration", "buildSettings": settings, "name": name.split(".")[-1]}
    if name.startswith("project.config"): fields["baseConfigurationReference"] = signing
    return add(name, **fields)

def config_list(name, settings):
    return add(name, isa="XCConfigurationList", buildConfigurations=[config(name+".Debug", {**settings, "SWIFT_OPTIMIZATION_LEVEL":"-Onone", "SWIFT_ACTIVE_COMPILATION_CONDITIONS":"DEBUG", "ENABLE_TESTABILITY":"YES"}), config(name+".Release", {**settings, "SWIFT_OPTIMIZATION_LEVEL":"-O"})], defaultConfigurationIsVisible="0", defaultConfigurationName="Release")

source_refs, source_builds, test_refs, test_builds, ui_refs, ui_builds = [], [], [], [], [], []
for directory, refs, builds in [(APP/"Sources",source_refs,source_builds),(APP/"Tests",test_refs,test_builds),(APP/"UITests",ui_refs,ui_builds)]:
    for path in sorted(directory.glob("*.swift")):
        relative = str(path.relative_to(APP))
        reference = add(relative, isa="PBXFileReference", lastKnownFileType="sourcecode.swift", path=relative, sourceTree="<group>")
        refs.append(reference)
        builds.append(add(relative+".build", isa="PBXBuildFile", fileRef=reference))

assets = add("assets", isa="PBXFileReference", lastKnownFileType="folder.assetcatalog", path="Resources/Assets.xcassets", sourceTree="<group>")
assets_build = add("assets.build", isa="PBXBuildFile", fileRef=assets)
notices = add("notices", isa="PBXFileReference", lastKnownFileType="text", path="Resources/ThirdPartyNotices.txt", sourceTree="<group>")
notices_build = add("notices.build", isa="PBXBuildFile", fileRef=notices)
privacy = add("privacy", isa="PBXFileReference", lastKnownFileType="text.xml", path="Resources/PrivacyInfo.xcprivacy", sourceTree="<group>")
privacy_build = add("privacy.build", isa="PBXBuildFile", fileRef=privacy)
signing = add("signing", isa="PBXFileReference", lastKnownFileType="text.xcconfig", path="Signing.xcconfig", sourceTree="<group>")
plist = add("plist", isa="PBXFileReference", lastKnownFileType="text.plist.xml", path="Resources/Info.plist", sourceTree="<group>")
app_product = add("app.product", isa="PBXFileReference", explicitFileType="wrapper.application", path="RoomRemote.app", sourceTree="BUILT_PRODUCTS_DIR")
test_product = add("test.product", isa="PBXFileReference", explicitFileType="wrapper.cfbundle", path="RoomRemoteTests.xctest", sourceTree="BUILT_PRODUCTS_DIR")
ui_product = add("ui.product", isa="PBXFileReference", explicitFileType="wrapper.cfbundle", path="RoomRemoteUITests.xctest", sourceTree="BUILT_PRODUCTS_DIR")
package = add("package.swiftatv", isa="XCLocalSwiftPackageReference", relativePath="../Vendor/SwiftATV")
package_product = add("package.product", isa="XCSwiftPackageProductDependency", package=package, productName="SwiftATV")
package_build = add("package.build", isa="PBXBuildFile", productRef=package_product)
products = add("products", isa="PBXGroup", children=[app_product,test_product,ui_product], name="Products", sourceTree="<group>")
sources = add("sources", isa="PBXGroup", children=source_refs, name="Sources", sourceTree="<group>")
tests = add("tests", isa="PBXGroup", children=test_refs, name="Tests", sourceTree="<group>")
ui_group = add("ui.group", isa="PBXGroup", children=ui_refs, name="UITests", sourceTree="<group>")
resources = add("resources", isa="PBXGroup", children=[assets,notices,privacy,plist], name="Resources", sourceTree="<group>")
main_group = add("main.group", isa="PBXGroup", children=[sources,tests,ui_group,resources,signing,products], sourceTree="<group>")

common = {"CLANG_ENABLE_MODULES":"YES", "SDKROOT":"iphoneos", "ARCHS":"arm64", "ONLY_ACTIVE_ARCH":"YES", "IPHONEOS_DEPLOYMENT_TARGET":"27.0", "SWIFT_VERSION":"6.0", "SWIFT_STRICT_CONCURRENCY":"complete", "CODE_SIGNING_ALLOWED":"YES", "CODE_SIGNING_REQUIRED":"YES", "CODE_SIGN_IDENTITY":"Apple Development", "CODE_SIGN_STYLE":"Automatic", "SWIFT_EMIT_LOC_STRINGS":"YES", "SUPPORTED_PLATFORMS":"iphoneos iphonesimulator", "TARGETED_DEVICE_FAMILY":"1", "ENABLE_USER_SCRIPT_SANDBOXING":"YES"}
project_configs = config_list("project.config", common)
app_configs = config_list("app.config", {**common,"PRODUCT_NAME":"RoomRemote","INFOPLIST_FILE":"Resources/Info.plist","GENERATE_INFOPLIST_FILE":"NO","ASSETCATALOG_COMPILER_APPICON_NAME":"AppIcon","LD_RUNPATH_SEARCH_PATHS":"$(inherited) @executable_path/Frameworks","VERSIONING_SYSTEM":"apple-generic","CURRENT_PROJECT_VERSION":"50","MARKETING_VERSION":"3.5.4","ENABLE_PREVIEWS":"YES"})
app_sources = add("app.sources", isa="PBXSourcesBuildPhase", buildActionMask="2147483647", files=source_builds, runOnlyForDeploymentPostprocessing="0")
app_frameworks = add("app.frameworks", isa="PBXFrameworksBuildPhase", buildActionMask="2147483647", files=[package_build], runOnlyForDeploymentPostprocessing="0")
app_resources = add("app.resources", isa="PBXResourcesBuildPhase", buildActionMask="2147483647", files=[assets_build,notices_build,privacy_build], runOnlyForDeploymentPostprocessing="0")
app_target = add("app.target", isa="PBXNativeTarget", buildConfigurationList=app_configs, buildPhases=[app_sources,app_frameworks,app_resources], buildRules=[], dependencies=[], name="RoomRemote", packageProductDependencies=[package_product], productName="RoomRemote", productReference=app_product, productType="com.apple.product-type.application")
project_id = ident("project")
proxy = add("test.proxy", isa="PBXContainerItemProxy", containerPortal=project_id, proxyType="1", remoteGlobalIDString=app_target, remoteInfo="RoomRemote")
dependency = add("test.dependency", isa="PBXTargetDependency", target=app_target, targetProxy=proxy)
test_sources = add("test.sources", isa="PBXSourcesBuildPhase", buildActionMask="2147483647", files=test_builds, runOnlyForDeploymentPostprocessing="0")
test_frameworks = add("test.frameworks", isa="PBXFrameworksBuildPhase", buildActionMask="2147483647", files=[], runOnlyForDeploymentPostprocessing="0")
test_configs = config_list("test.config", {**common,"PRODUCT_NAME":"RoomRemoteTests","PRODUCT_BUNDLE_IDENTIFIER":"local.roomremote.tests","GENERATE_INFOPLIST_FILE":"YES","TEST_HOST":"$(BUILT_PRODUCTS_DIR)/RoomRemote.app/RoomRemote","BUNDLE_LOADER":"$(TEST_HOST)","LD_RUNPATH_SEARCH_PATHS":"$(inherited) @executable_path/Frameworks @loader_path/Frameworks"})
test_target = add("test.target", isa="PBXNativeTarget", buildConfigurationList=test_configs, buildPhases=[test_sources,test_frameworks], buildRules=[], dependencies=[dependency], name="RoomRemoteTests", productName="RoomRemoteTests", productReference=test_product, productType="com.apple.product-type.bundle.unit-test")
ui_configs = config_list("ui.config", {**common,"PRODUCT_NAME":"RoomRemoteUITests","PRODUCT_BUNDLE_IDENTIFIER":"local.roomremote.uitests","GENERATE_INFOPLIST_FILE":"YES","TEST_TARGET_NAME":"RoomRemote","LD_RUNPATH_SEARCH_PATHS":"$(inherited) @executable_path/Frameworks @loader_path/Frameworks"})
ui_sources = add("ui.sources", isa="PBXSourcesBuildPhase", buildActionMask="2147483647", files=ui_builds, runOnlyForDeploymentPostprocessing="0")
ui_frameworks = add("ui.frameworks", isa="PBXFrameworksBuildPhase", buildActionMask="2147483647", files=[], runOnlyForDeploymentPostprocessing="0")
ui_target = add("ui.target", isa="PBXNativeTarget", buildConfigurationList=ui_configs, buildPhases=[ui_sources,ui_frameworks], buildRules=[], dependencies=[dependency], name="RoomRemoteUITests", productName="RoomRemoteUITests", productReference=ui_product, productType="com.apple.product-type.bundle.ui-testing")
objects[project_id]={"isa":"PBXProject","attributes":{"BuildIndependentTargetsInParallel":"YES","LastUpgradeCheck":"2700","TargetAttributes":{app_target:{"CreatedOnToolsVersion":"27.0"},test_target:{"CreatedOnToolsVersion":"27.0","TestTargetID":app_target},ui_target:{"CreatedOnToolsVersion":"27.0","TestTargetID":app_target}}},"buildConfigurationList":project_configs,"compatibilityVersion":"Xcode 14.0","developmentRegion":"en","hasScannedForEncodings":"0","knownRegions":["en","Base"],"mainGroup":main_group,"packageReferences":[package],"productRefGroup":products,"projectDirPath":"","projectRoot":"","targets":[app_target,test_target,ui_target]}

def render(value, depth=0):
    if isinstance(value,dict): return "{\n"+"\n".join("\t"*(depth+1)+json.dumps(k)+" = "+render(v,depth+1)+";" for k,v in value.items())+"\n"+"\t"*depth+"}"
    if isinstance(value,list): return "("+", ".join(render(v,depth) for v in value)+")"
    return json.dumps(value)

project=APP/"RoomRemote.xcodeproj"
project.mkdir(parents=True,exist_ok=True)
(project/"project.pbxproj").write_text("// !$*UTF8*$!\n"+render({"archiveVersion":"1","classes":{},"objectVersion":"56","objects":objects,"rootObject":project_id})+"\n")
schemes=project/"xcshareddata/xcschemes"
schemes.mkdir(parents=True,exist_ok=True)
def build_ref(target,name,product):
    return f'<BuildableReference BuildableIdentifier="primary" BlueprintIdentifier="{target}" BuildableName="{product}" BlueprintName="{name}" ReferencedContainer="container:RoomRemote.xcodeproj"/>'
(schemes/"RoomRemote.xcscheme").write_text(f'''<?xml version="1.0" encoding="UTF-8"?>
<Scheme LastUpgradeVersion="2700" version="1.3"><BuildAction parallelizeBuildables="YES" buildImplicitDependencies="YES"><BuildActionEntries><BuildActionEntry buildForTesting="YES" buildForRunning="YES" buildForProfiling="YES" buildForArchiving="YES" buildForAnalyzing="YES">{build_ref(app_target,"RoomRemote","RoomRemote.app")}</BuildActionEntry></BuildActionEntries></BuildAction><TestAction buildConfiguration="Debug" selectedDebuggerIdentifier="Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier="Xcode.IDEFoundation.Launcher.LLDB" shouldUseLaunchSchemeArgsEnv="YES"><Testables><TestableReference skipped="NO">{build_ref(test_target,"RoomRemoteTests","RoomRemoteTests.xctest")}</TestableReference></Testables></TestAction><LaunchAction buildConfiguration="Debug" selectedDebuggerIdentifier="Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier="Xcode.IDEFoundation.Launcher.LLDB" launchStyle="0" useCustomWorkingDirectory="NO" ignoresPersistentStateOnLaunch="NO" debugDocumentVersioning="YES" debugServiceExtension="internal" allowLocationSimulation="YES"><BuildableProductRunnable runnableDebuggingMode="0">{build_ref(app_target,"RoomRemote","RoomRemote.app")}</BuildableProductRunnable></LaunchAction><ProfileAction buildConfiguration="Release" shouldUseLaunchSchemeArgsEnv="YES"><BuildableProductRunnable runnableDebuggingMode="0">{build_ref(app_target,"RoomRemote","RoomRemote.app")}</BuildableProductRunnable></ProfileAction><AnalyzeAction buildConfiguration="Debug"/><ArchiveAction buildConfiguration="Release" revealArchiveInOrganizer="YES"/></Scheme>''')
resources_path=APP/"Resources"
scheme_path = schemes/"RoomRemote.xcscheme"
scheme_path.write_text(scheme_path.read_text().replace("</Testables>", f'<TestableReference skipped="NO">{build_ref(ui_target,"RoomRemoteUITests","RoomRemoteUITests.xctest")}</TestableReference></Testables>'))
resources_path.mkdir(parents=True,exist_ok=True)
info={"CFBundleDevelopmentRegion":"en","CFBundleDisplayName":"ATV Remote","CFBundleExecutable":"$(EXECUTABLE_NAME)","CFBundleIdentifier":"$(PRODUCT_BUNDLE_IDENTIFIER)","CFBundleInfoDictionaryVersion":"6.0","CFBundleName":"ATV Remote","CFBundlePackageType":"APPL","CFBundleShortVersionString":"$(MARKETING_VERSION)","CFBundleVersion":"$(CURRENT_PROJECT_VERSION)","LSRequiresIPhoneOS":True,"UILaunchScreen":{},"UISupportedInterfaceOrientations":["UIInterfaceOrientationPortrait"],"NSLocalNetworkUsageDescription":"Find and control the Samsung TVs and Apple TVs you choose on your home network.","NSBonjourServices":["_companion-link._tcp","_device-info._tcp","_sleep-proxy._udp"]}
info.update({"NSFaceIDUsageDescription":"Confirm it is you before sharing saved TV pairings with another iPhone.","NSCameraUsageDescription":"Read the IP and MAC addresses shown on your TV to fill its setup.","LSSupportsOpeningDocumentsInPlace":True,"UTExportedTypeDeclarations":[{"UTTypeIdentifier":"local.roomremote.transfer","UTTypeDescription":"ATV Remote encrypted setup","UTTypeConformsTo":["public.data","public.content"],"UTTypeTagSpecification":{"public.filename-extension":["roomremote"],"public.mime-type":"application/vnd.roomremote.transfer"}}],"CFBundleDocumentTypes":[{"CFBundleTypeName":"ATV Remote setup","CFBundleTypeRole":"Viewer","LSHandlerRank":"Owner","LSItemContentTypes":["local.roomremote.transfer","io.github.atvremote.direct-setup"]}]})
info["UTExportedTypeDeclarations"].append({"UTTypeIdentifier":"io.github.atvremote.direct-setup","UTTypeDescription":"ATV Remote setup","UTTypeConformsTo":["public.data","public.content"],"UTTypeTagSpecification":{"public.filename-extension":["atvsetup"],"public.mime-type":"application/vnd.atvremote.setup"}})
info["UIApplicationSceneManifest"] = {"UIApplicationSupportsMultipleScenes":False}
(resources_path/"Info.plist").write_bytes(plistlib.dumps(info))
print(project)
