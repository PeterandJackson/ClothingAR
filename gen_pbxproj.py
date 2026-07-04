#!/usr/bin/env python3
"""Generate ClothingAR.xcodeproj/project.pbxproj"""
import os
FILES = [
    ('AppDelegate.swift','App'),('SceneDelegate.swift','App'),
    ('CameraManager.swift','Core'),('BodyTracker.swift','Core'),('SkeletonMapper.swift','Core'),
    ('PersonSegmentation.swift','Core'),('SceneRenderer.swift','Core'),('ModelLoader.swift','Core'),
    ('ModelCalibration.swift','Core'),('VideoRecorder.swift','Recording'),('PhotoAlbumSaver.swift','Recording'),
    ('ARViewController.swift','UI'),('RecordButton.swift','UI'),('StatusIndicator.swift','UI'),
    ('PerformanceMonitor.swift','Performance'),('QualityManager.swift','Performance'),
    ('Info.plist','Resources'),('Assets.xcassets','Resources'),
]
def fid(n): return '{:024X}'.format(n)
B={}
FR={}
for i,(n,_) in enumerate(FILES):
    B[n]=fid(1000001+i)
    FR[n]=fid(2000001+i)
PR=fid(2999999)
FW=fid(3000001)
TGT=fid(5000001)
PJ=fid(9000001)
L=[]
def a(s=''):
    L.append(s)
a('// !$*UTF8*$!')
a('{')
a('\tarchiveVersion = 1;')
a('\tclasses = {};')
a('\tobjectVersion = 56;')
a('\tobjects = {')
a('')
a('/* Begin PBXBuildFile section */')
for n,_ in FILES:
    r=FR[n]
    if n=='Assets.xcassets':
        a('\t\t'+B[n]+' /* '+n+' in Resources */ = {isa = PBXBuildFile; fileRef = '+r+' /* '+n+' */; };')
    elif n!='Info.plist':
        a('\t\t'+B[n]+' /* '+n+' in Sources */ = {isa = PBXBuildFile; fileRef = '+r+' /* '+n+' */; };')
a('/* End PBXBuildFile section */')
a('')
a('/* Begin PBXFileReference section */')
for n,_ in FILES:
    r=FR[n]
    if n=='Assets.xcassets':
        a('\t\t'+r+' /* '+n+' */ = {isa = PBXFileReference; lastKnownFileType = folder.assetcatalog; path = '+n+'; sourceTree = "<group>"; };')
    elif n=='Info.plist':
        a('\t\t'+r+' /* '+n+' */ = {isa = PBXFileReference; lastKnownFileType = text.plist.xml; path = '+n+'; sourceTree = "<group>"; };')
    else:
        a('\t\t'+r+' /* '+n+' */ = {isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = '+n+'; sourceTree = "<group>"; };')
a('\t\t'+PR+' /* ClothingAR.app */ = {isa = PBXFileReference; explicitFileType = wrapper.application; includeInIndex = 0; path = ClothingAR.app; sourceTree = BUILT_PRODUCTS_DIR; };')
a('/* End PBXFileReference section */')
a('')
a('/* Begin PBXFrameworksBuildPhase section */')
a('\t\t'+FW+' /* Frameworks */ = {isa = PBXFrameworksBuildPhase; buildActionMask = 2147483647; files = (); runOnlyForDeploymentPostprocessing = 0; };')
a('/* End PBXFrameworksBuildPhase section */')
a('')
G={}
for k in ['ROOT','App','Core','Recording','UI','Performance','Resources','Products']:
    G[k]=fid(4000000+len(G))
def grp(gid,refs,name='',path=''):
    a('\t\t'+gid+' /* '+(name or path)+' */ = {')
    a('\t\t\tisa = PBXGroup;')
    a('\t\t\tchildren = (')
    for c in refs:
        a('\t\t\t\t'+c+',')
    a('\t\t\t);')
    if name:
        a('\t\t\tname = '+name+';')
    if path:
        a('\t\t\tpath = '+path+';')
    a('\t\t\tsourceTree = "<group>";')
    a('\t\t};')
a('/* Begin PBXGroup section */')
for gn in ['App','Core','Recording','UI','Performance']:
    r=[FR[n] for n,g in FILES if g==gn]
    grp(G[gn],r,path=gn)
grp(G['Resources'],[FR['Info.plist'],FR['Assets.xcassets']],path='Resources')
grp(G['Products'],[PR],name='Products')
grp(G['ROOT'],[G[k] for k in ['App','Core','Recording','UI','Performance','Resources','Products']])
a('/* End PBXGroup section */')
a('')
a('/* Begin PBXNativeTarget section */')
a('\t\t'+TGT+' /* ClothingAR */ = {')
a('\t\t\tisa = PBXNativeTarget;')
a('\t\t\tbuildConfigurationList = '+fid(8000002)+' /* BCL */;')
a('\t\t\tbuildPhases = (')
a('\t\t\t\t'+fid(6000001)+' /* Sources */,')
a('\t\t\t\t'+FW+' /* Frameworks */,')
a('\t\t\t\t'+fid(7000001)+' /* Resources */,')
a('\t\t\t);')
a('\t\t\tbuildRules = ();')
a('\t\t\tdependencies = ();')
a('\t\t\tname = ClothingAR;')
a('\t\t\tproductName = ClothingAR;')
a('\t\t\tproductReference = '+PR+';')
a('\t\t\tproductType = "com.apple.product-type.application";')
a('\t\t};')
a('/* End PBXNativeTarget section */')
a('')
a('/* Begin PBXProject section */')
a('\t\t'+PJ+' /* Project object */ = {')
a('\t\t\tisa = PBXProject;')
a('\t\t\tattributes = {')
a('\t\t\t\tBuildIndependentTargetsInParallel = 1;')
a('\t\t\t\tLastSwiftUpdateCheck = 1520;')
a('\t\t\t\tLastUpgradeCheck = 1520;')
a('\t\t\t\tTargetAttributes = {')
a('\t\t\t\t\t'+TGT+' = {CreatedOnToolsVersion = 15.2; };')
a('\t\t\t\t};')
a('\t\t\t};')
a('\t\t\tbuildConfigurationList = '+fid(8000001)+';')
a('\t\t\tcompatibilityVersion = "Xcode 14.0";')
a('\t\t\tdevelopmentRegion = "zh-Hans";')
a('\t\t\thasScannedForEncodings = 0;')
a('\t\t\tknownRegions = (en, "zh-Hans", Base);')
a('\t\t\tmainGroup = '+G['ROOT']+';')
a('\t\t\tproductRefGroup = '+G['Products']+';')
a('\t\t\tprojectDirPath = "ClothingAR";')
a('\t\t\tprojectRoot = "";')
a('\t\t\ttargets = (')
a('\t\t\t\t'+TGT+' /* ClothingAR */,')
a('\t\t\t);')
a('\t\t};')
a('/* End PBXProject section */')
a('')
a('/* Begin PBXResourcesBuildPhase section */')
a('\t\t'+fid(7000001)+' /* Resources */ = {isa = PBXResourcesBuildPhase; buildActionMask = 2147483647; files = ('+B['Assets.xcassets']+' /* Assets.xcassets in Resources */,); runOnlyForDeploymentPostprocessing = 0; };')
a('/* End PBXResourcesBuildPhase section */')
a('')
a('/* Begin PBXSourcesBuildPhase section */')
a('\t\t'+fid(6000001)+' /* Sources */ = {isa = PBXSourcesBuildPhase; buildActionMask = 2147483647; files = (')
for n,_ in FILES:
    if n not in ('Assets.xcassets','Info.plist'):
        a('\t\t\t\t'+B[n]+' /* '+n+' in Sources */,')
a('\t\t\t); runOnlyForDeploymentPostprocessing = 0; };')
a('/* End PBXSourcesBuildPhase section */')
a('')
def cfg(cid,name_,settings):
    a('\t\t'+cid+' /* '+name_+' */ = {isa = XCBuildConfiguration; buildSettings = {')
    for s in settings:
        a('\t\t\t\t'+s)
    a('\t\t\t};')
    a('\t\t\tname = '+name_+';')
    a('\t\t};')
a('/* Begin XCBuildConfiguration section */')
base=['ALWAYS_SEARCH_USER_PATHS = NO;','CLANG_ANALYZER_NONNULL = YES;','CLANG_CXX_LANGUAGE_STANDARD = "gnu++20";','CLANG_ENABLE_MODULES = YES;','CLANG_ENABLE_OBJC_ARC = YES;','IPHONEOS_DEPLOYMENT_TARGET = 16.0;','SDKROOT = iphoneos;']
cfg(fid(11000001),'Debug',base+['DEBUG_INFORMATION_FORMAT = dwarf;','GCC_OPTIMIZATION_LEVEL = 0;','ONLY_ACTIVE_ARCH = YES;','SWIFT_OPTIMIZATION_LEVEL = "-Onone";'])
cfg(fid(11000002),'Release',base+['DEBUG_INFORMATION_FORMAT = "dwarf-with-dsym";','GCC_OPTIMIZATION_LEVEL = s;','SWIFT_OPTIMIZATION_LEVEL = "-O";'])
tgt=['CODE_SIGN_STYLE = Automatic;','CURRENT_PROJECT_VERSION = 1;','INFOPLIST_FILE = Info.plist;','MARKETING_VERSION = 1.0;','PRODUCT_BUNDLE_IDENTIFIER = com.clothingar.app;','PRODUCT_NAME = "$(TARGET_NAME)";','SUPPORTED_PLATFORMS = "iphoneos iphonesimulator";','SWIFT_VERSION = 5.0;','TARGETED_DEVICE_FAMILY = 1;','LD_RUNPATH_SEARCH_PATHS = ("$(inherited)","@executable_path/Frameworks");','INFOPLIST_KEY_NSCameraUsageDescription = "ClothingAR needs camera";','INFOPLIST_KEY_NSMicrophoneUsageDescription = "ClothingAR needs mic";','INFOPLIST_KEY_NSPhotoLibraryAddUsageDescription = "ClothingAR needs album";','INFOPLIST_KEY_UIApplicationSceneManifest_Generation = YES;','INFOPLIST_KEY_UILaunchScreen_Generation = YES;','INFOPLIST_KEY_UIStatusBarHidden = YES;','INFOPLIST_KEY_UISupportedInterfaceOrientations = UIInterfaceOrientationPortrait;']
cfg(fid(11000003),'Debug',tgt)
cfg(fid(11000004),'Release',tgt)
a('/* End XCBuildConfiguration section */')
a('')
a('/* Begin XCConfigurationList section */')
a('\t\t'+fid(8000002)+' /* BCL target */ = {isa = XCConfigurationList; buildConfigurations = ('+fid(11000003)+' /* Debug */,'+fid(11000004)+' /* Release */,); defaultConfigurationIsVisible = 0; defaultConfigurationName = Release; };')
a('\t\t'+fid(8000001)+' /* BCL project */ = {isa = XCConfigurationList; buildConfigurations = ('+fid(11000001)+' /* Debug */,'+fid(11000002)+' /* Release */,); defaultConfigurationIsVisible = 0; defaultConfigurationName = Release; };')
a('/* End XCConfigurationList section */')
a('')
a('\t};')
a('\trootObject = '+PJ+' /* Project object */;')
a('}')
os.makedirs('ClothingAR.xcodeproj',exist_ok=True)
with open('ClothingAR.xcodeproj/project.pbxproj','w',encoding='utf-8',newline='\n') as f:
    f.write('\n'.join(L)+'\n')
print('ClothingAR pbxproj generated')
