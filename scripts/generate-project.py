#!/usr/bin/env python3
"""Generate a dependency-free native Xcode app project from Sources/."""
from pathlib import Path

root = Path(__file__).resolve().parent.parent
project = root / "Amoss.xcodeproj"
project.mkdir(exist_ok=True)
objects = []
counter = 1

def uid():
    global counter
    value = f"{counter:024X}"
    counter += 1
    return value

def obj(identity, body):
    objects.append(f"\t\t{identity} = {{ {body} }};")

proj, group, sources, resources, products, product, target, source_phase, framework_phase, resource_phase = [uid() for _ in range(10)]
project_configs, target_configs, pd, pr, td, tr = [uid() for _ in range(6)]
source_refs, source_builds = [], []
for path in sorted((root / "Sources").rglob("*.swift")):
    ref, build = uid(), uid()
    source_refs.append(ref)
    source_builds.append(build)
    obj(ref, f'isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = "{path.relative_to(root)}"; sourceTree = SOURCE_ROOT;')
    obj(build, f'isa = PBXBuildFile; fileRef = {ref};')
obj(product, 'isa = PBXFileReference; explicitFileType = wrapper.application; includeInIndex = 0; path = Amoss.app; sourceTree = BUILT_PRODUCTS_DIR;')
obj(sources, f'isa = PBXGroup; children = ({", ".join(source_refs)}); name = Sources; sourceTree = "<group>";')
obj(resources, 'isa = PBXGroup; children = (); name = Resources; sourceTree = "<group>";')
obj(products, f'isa = PBXGroup; children = ({product}); name = Products; sourceTree = "<group>";')
obj(group, f'isa = PBXGroup; children = ({sources}, {resources}, {products}); sourceTree = "<group>";')
obj(source_phase, f'isa = PBXSourcesBuildPhase; buildActionMask = 2147483647; files = ({", ".join(source_builds)}); runOnlyForDeploymentPostprocessing = 0;')
obj(framework_phase, 'isa = PBXFrameworksBuildPhase; buildActionMask = 2147483647; files = (); runOnlyForDeploymentPostprocessing = 0;')
obj(resource_phase, 'isa = PBXShellScriptBuildPhase; buildActionMask = 2147483647; files = (); inputPaths = (); outputPaths = (); name = "Bundle standalone tools"; alwaysOutOfDate = 1; runOnlyForDeploymentPostprocessing = 0; shellPath = /bin/bash; shellScript = "bash \\\"$SRCROOT/scripts/copy-resources.sh\\\"";')
obj(target, f'isa = PBXNativeTarget; buildConfigurationList = {target_configs}; buildPhases = ({source_phase}, {framework_phase}, {resource_phase}); buildRules = (); dependencies = (); name = Amoss; productName = Amoss; productReference = {product}; productType = "com.apple.product-type.application";')
obj(proj, f'isa = PBXProject; attributes = {{ LastUpgradeCheck = 2700; }}; buildConfigurationList = {project_configs}; compatibilityVersion = "Xcode 14.0"; developmentRegion = en; hasScannedForEncodings = 0; knownRegions = (en, "zh-Hans", Base); mainGroup = {group}; productRefGroup = {products}; projectDirPath = ""; projectRoot = ""; targets = ({target});')
for identity, name in [(pd, "Debug"), (pr, "Release")]:
    obj(identity, f'isa = XCBuildConfiguration; buildSettings = {{ SDKROOT = macosx; MACOSX_DEPLOYMENT_TARGET = 15.0; CLANG_ENABLE_MODULES = YES; SWIFT_VERSION = 6.0; }}; name = {name};')
for identity, name in [(td, "Debug"), (tr, "Release")]:
    debug = name == "Debug"
    settings = 'PRODUCT_NAME = Amoss; PRODUCT_BUNDLE_IDENTIFIER = com.amoss.app; INFOPLIST_FILE = Resources/Info.plist; GENERATE_INFOPLIST_FILE = NO; CODE_SIGN_IDENTITY = "-"; CODE_SIGN_STYLE = Manual; ENABLE_APP_SANDBOX = NO; ENABLE_HARDENED_RUNTIME = YES; ENABLE_USER_SCRIPT_SANDBOXING = NO; COMBINE_HIDPI_IMAGES = YES; LD_RUNPATH_SEARCH_PATHS = "$(inherited) @executable_path/../Frameworks"; '
    settings += 'SWIFT_OPTIMIZATION_LEVEL = "-Onone"; SWIFT_ACTIVE_COMPILATION_CONDITIONS = DEBUG; DEBUG_INFORMATION_FORMAT = dwarf;' if debug else 'SWIFT_OPTIMIZATION_LEVEL = "-O"; SWIFT_COMPILATION_MODE = wholemodule; DEBUG_INFORMATION_FORMAT = "dwarf-with-dsym";'
    obj(identity, f'isa = XCBuildConfiguration; buildSettings = {{ {settings} }}; name = {name};')
obj(project_configs, f'isa = XCConfigurationList; buildConfigurations = ({pd}, {pr}); defaultConfigurationIsVisible = 0; defaultConfigurationName = Release;')
obj(target_configs, f'isa = XCConfigurationList; buildConfigurations = ({td}, {tr}); defaultConfigurationIsVisible = 0; defaultConfigurationName = Release;')
content = '// !$*UTF8*$!\n{\n\tarchiveVersion = 1;\n\tclasses = {};\n\tobjectVersion = 56;\n\tobjects = {\n' + '\n'.join(objects) + f'\n\t}};\n\trootObject = {proj};\n}}\n'
(project / "project.pbxproj").write_text(content)
schemes = project / "xcshareddata/xcschemes"
schemes.mkdir(parents=True, exist_ok=True)
reference = f'<BuildableReference BuildableIdentifier="primary" BlueprintIdentifier="{target}" BuildableName="Amoss.app" BlueprintName="Amoss" ReferencedContainer="container:Amoss.xcodeproj"/>'
(schemes / "Amoss.xcscheme").write_text(f'''<?xml version="1.0" encoding="UTF-8"?>
<Scheme LastUpgradeVersion="2700" version="1.3">
  <BuildAction parallelizeBuildables="YES" buildImplicitDependencies="YES"><BuildActionEntries><BuildActionEntry buildForTesting="YES" buildForRunning="YES" buildForProfiling="YES" buildForArchiving="YES" buildForAnalyzing="YES">{reference}</BuildActionEntry></BuildActionEntries></BuildAction>
  <LaunchAction buildConfiguration="Debug" selectedDebuggerIdentifier="Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier="Xcode.IDEFoundation.Launcher.LLDB" launchStyle="0" useCustomWorkingDirectory="NO" ignoresPersistentStateOnLaunch="NO" debugDocumentVersioning="YES" allowLocationSimulation="YES"><BuildableProductRunnable runnableDebuggingMode="0">{reference}</BuildableProductRunnable></LaunchAction>
  <ProfileAction buildConfiguration="Release" shouldUseLaunchSchemeArgsEnv="YES" savedToolIdentifier="" useCustomWorkingDirectory="NO" debugDocumentVersioning="YES"><BuildableProductRunnable runnableDebuggingMode="0">{reference}</BuildableProductRunnable></ProfileAction>
  <AnalyzeAction buildConfiguration="Debug"/>
  <ArchiveAction buildConfiguration="Release" revealArchiveInOrganizer="YES"/>
</Scheme>
''')
print("Generated Amoss.xcodeproj")
