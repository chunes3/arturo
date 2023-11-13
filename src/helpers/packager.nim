#=======================================================
# Arturo
# Programming Language + Bytecode VM compiler
# (c) 2019-2023 Yanis Zafirópulos
#
# @file: helpers/packager.nim
#=======================================================

#=======================================
# Libraries
#=======================================

import algorithm, options
import sequtils, strformat, strutils, tables

when not defined(WEB):
    import asyncdispatch, httpClient, os

import extras/miniz

when not defined(WEB):
    import helpers/io
    import helpers/terminal
    import helpers/url

import vm/[env, exec, parse, values/types]

import vm/values/custom/[vsymbol, vversion]

#=======================================
# Types
#=======================================

type
    VersionSpec*        = (bool, VVersion)
    VersionLocation*    = (string, VVersion)

#=======================================
# Constants
#=======================================

let
    NoPackageVersion*   = VVersion(major: 0, minor: 0, patch: 0, extra: "")
    NoVersionLocation*  = ("", NoPackageVersion)
    NoImportResult*     = (false, "")

const
    PackageFolder*      = "{HomeDir}.arturo/packages/"

    SpecLatestUrl*      = "https://{pkg}.pkgr.art/spec"
    SpecVersionUrl*     = "https://{pkg}.pkgr.art/{version}/spec"

    SpecFolder*         = PackageFolder & "specs/"
    SpecPackage*        = SpecFolder & "{pkg}/"
    SpecFile*           = SpecPackage & "{version}.art"

    CacheFolder*        = PackageFolder & "cache/"
    CachePackage*       = CacheFolder & "{pkg}/"
    CacheFiles*         = CachePackage & "{version}/"

#=======================================
# Global Variables
#=======================================

var
    VerbosePackager* = false

#=======================================
# Forward declarations
#=======================================

proc loadLocalPackage(src: string, version: VersionSpec, latest: bool = false): Option[string]
proc loadRemotePackage(src: string, version: VersionSpec): Option[string]
proc verifyDependencies*(deps: seq[Value]): bool

#=======================================
# Helpers
#=======================================

proc getEntryPointFromSourceFolder*(folder: string): Option[string] =
    ## In a supposed package source folder,
    ## look either for the 'entry' as defined in the package's info.art
    ## or a main.art file - our default entry point

    var entryPoint = "{folder}/main.art".fmt
    var allOk = true

    if (let infoPath = "{folder}/info.art".fmt; infoPath.fileExists()):
        let infoArt = execDictionary(doParse(infoPath, isFile=true))

        if infoArt.hasKey("entry"):
            let entryName = infoArt["entry"].s
            entryPoint = "{folder}/{entryName}.art".fmt

        if not entryPoint.fileExists():
            # should throw!
            allOk = false

        if infoArt.hasKey("depends"):
            allOk = verifyDependencies(infoArt["depends"].a)

    if allOk:
        return some(entryPoint)

proc checkLocalFile*(filePath: string): Option[string] =
    ## Check if file exists at given path
    ## or alternatively "file.art"

    if filePath.fileExists():
        return some(filePath)
    else:
        if (let fileWithExtension = filePath & ".art"; fileWithExtension.fileExists()):
            return some(fileWithExtension)

proc checkLocalFolder*(folderPath: string): Option[string] =
    ## Check if valid package folder exists 
    ## at given path and return entry filepath

    if folderPath.dirExists():
        return getEntryPointFromSourceFolder(folderPath)

proc getLocalPackageVersions(inPath: string, ordered: SortOrder): seq[VersionLocation] =
    result = (toSeq(walkDir(inPath))).map(
            proc (vers: tuple[kind: PathComponent, path: string]): VersionLocation = 
                let filepath = vers.path
                let (_, name, ext) = splitFile(filepath)
                (filepath, newVVersion(name & ext))
        ).sorted(
            proc (a: VersionLocation, b: VersionLocation): int =
                cmp(a[1], b[1])
        , order=ordered)

proc getBestVersion(within: seq[VersionLocation], version: VersionSpec): VersionLocation =
    let checkingForMinimum = version[0]
    let checkingForVersion = version[1]

    for vers in within:
        if checkingForMinimum:
            if (vers[1] > checkingForVersion or vers[1] == checkingForVersion):
                return vers
        else:
            if vers[1] == checkingForVersion:
                return vers

    return NoVersionLocation

proc checkLocalPackage*(pkg: string, version: VersionSpec): (bool, VersionLocation) =
    let expectedPath = CachePackage.fmt

    if expectedPath.dirExists():
        let got = getBestVersion(
            getLocalPackageVersions(expectedPath, SortOrder.Descending),
            version
        )
        return (got[0]!="", got)
    else:
        return (false, NoVersionLocation)

#=======================================
# Methods
#=======================================

proc readSpec(pkg: string, version: VVersion): ValueDict =
    let specFile = SpecFile.fmt
    result = execDictionary(doParse(specFile, isFile=true))

proc readSpecFromContent(content: string): ValueDict =
    result = execDictionary(doParse(content, isFile=false))

proc installRemotePackage*(pkg: string, verspec: VersionSpec): bool =
    var packageSpec: string 
    if verspec[0]:
        packageSpec = SpecLatestUrl.fmt
    else:
        let version = verspec[1]
        packageSpec = SpecVersionUrl.fmt

    let specContent = waitFor (newAsyncHttpClient().getContent(packageSpec))
    let spec = readSpecFromContent(specContent)
    let actualVersion = spec["version"].version
    if not verifyDependencies(spec["depends"].a):
        return false
    let specFolder = SpecPackage.fmt
    stdout.write "- Installing package: {pkg} {actualVersion}".fmt
    createDir(specFolder)
    let specFile = "{specFolder}/{actualVersion}.art".fmt
    writeToFile(specFile, specContent)

    let pkgUrl = spec["url"].s
    let client = newHttpClient()
    createDir("{HomeDir}.arturo/tmp/".fmt)
    let tmpPkgZip = "{HomeDir}.arturo/tmp/pkg.zip".fmt
    client.downloadFile(pkgUrl, tmpPkgZip)
    createDir(CachePackage.fmt)
    let files = miniz.unzipAndGetFiles(tmpPkgZip, CachePackage.fmt)
    let (actualSubFolder, _, _) = splitFile(files[0])
    let actualFolder = "{HomeDir}.arturo/packages/cache/{pkg}/{actualSubFolder}".fmt
    let version = actualVersion
    moveDir(actualFolder, CacheFiles.fmt)

    discard tryRemoveFile("{HomeDir}.arturo/tmp/pkg.zip".fmt)

    stdout.write bold(greenColor) & " ✔" & resetColor() & "\n"
    stdout.flushFile()
    return true

proc verifyDependencies*(deps: seq[Value]): bool = 
    var depList: seq[(string, VersionSpec)] = @[]

    for dep in deps:
        if dep.kind == Word or dep.kind == Literal or dep.kind == String:
            depList.add((dep.s, (false, NoPackageVersion)))
        elif dep.kind == Block:
            if dep.a[0].kind == Word or dep.a[0].kind == Literal or dep.a[0].kind == String:
                if dep.a.len == 1:
                    depList.add((dep.a[0].s, (false, NoPackageVersion)))
                elif dep.a.len == 2:
                    depList.add((dep.a[0].s, (false, dep.a[1].version)))
                elif dep.a.len == 3:
                    if dep.a[1].m == greaterequal or dep.a[1].m == greaterthan:
                        depList.add((dep.a[0].s, (true, dep.a[2].version)))
                    elif dep.a[1].m == equal:
                        depList.add((dep.a[0].s, (false, dep.a[2].version)))

    var allOk = true
    for dep in depList:
        let src = dep[0]
        let version = dep[1]
        if loadLocalPackage(src, version).isSome:
            discard
        else:
            if loadRemotePackage(src,version).isSome:
                discard
            else:
                allOk = false

    return allOk

proc getSourceFromRepo*(repo: string, latest: bool = false): Option[string] =
    let cleanName = repo.replace("https://github.com/","")
    let parts = cleanName.split("/")

    let folderPath = "{HomeDir}.arturo/tmp/{parts[1]}@{parts[0]}".fmt
    if (not dirExists(folderPath)) or latest:
        let client = newHttpClient()
        let pkgUrl = "{repo}/archive/main.zip".fmt
        client.downloadFile(pkgUrl, "{HomeDir}.arturo/tmp/pkg.zip".fmt)
        let files = miniz.unzipAndGetFiles("{HomeDir}.arturo/tmp/pkg.zip".fmt, "{HomeDir}.arturo/tmp".fmt)
        let (actualSubFolder, _, _) = splitFile(files[0])
        let actualFolder = "{HomeDir}.arturo/tmp/{actualSubFolder}".fmt
        moveDir(actualFolder, folderPath)

        discard tryRemoveFile("{HomeDir}.arturo/tmp/pkg.zip".fmt)

    return getEntryPointFromSourceFolder(folderPath)

proc loadLocalPackage(src: string, version: VersionSpec, latest: bool = false): Option[string] =
    if latest:
        return loadRemotePackage(src, version)

    if (let (isLocalPackage, packageSource)=checkLocalPackage(src, version); isLocalPackage):
        let (packageLocation, packageVersion) = packageSource
        stdout.write "- Loading local package: {src} {packageVersion}".fmt
        let packageSpec = readSpec(src, packageVersion)
        if not verifyDependencies(packageSpec["depends"].a):
            return

        stdout.write bold(greenColor) & " ✔" & resetColor() & "\n"
        stdout.flushFile()

        return some(packageLocation & "/" & packageSpec["entry"].s)

proc loadRemotePackage(src: string, version: VersionSpec): Option[string] =
    echo "- Querying remote packages...".fmt
    if installRemotePackage(src, version):
        return loadLocalPackage(src, version)

proc getPackageSource*(
    pkg: string, 
    verspec: VersionSpec, 
    latest: bool
): Option[string] {.inline.} =
    ## Given a package name and a version specification
    ## try to find the best match and return
    ## the appropriate entry source filepath

    # is it a file?
    if (result = checkLocalFile(pkg); result.isSome):
        return

    # maybe it's a folder with a "package" in it?
    if (result = checkLocalFolder(pkg); result.isSome):
        return
    
    # maybe it's a github repository url?
    if pkg.isUrl():
        if (result = getSourceFromRepo(pkg, latest); result.isSome):
            return

    # maybe it's a package we already have locally?
    if (result = loadLocalPackage(pkg, verspec, latest); result.isSome):
        return
    else:
        # maybe it's a remote package we should fetch?
        if (result = loadRemotePackage(pkg, verspec); result.isSome):
            return
    
    return none(string)