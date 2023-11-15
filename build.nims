#!/usr/bin/env nim
######################################################
# Arturo
# Programming Language + Bytecode VM compiler
# (c) 2019-2023 Yanis Zafirópulos
#
# @file: build.nims
######################################################
# initial conversion to NimScript thanks to:
# - Patrick (skydive241@gmx.de)

# TODO(build.nims) General cleanup needed
#  labels: installer, enhancement, cleanup

#=======================================
# Libraries
#=======================================

import os
import strformat, strutils

import src/helpers/terminal

#=======================================
# Initialize globals
#=======================================

mode = ScriptMode.Silent
NoColors = hostOS == "windows"

#=======================================
# Flag system
#=======================================

include ".config/utils/cli.nims"
include ".config/utils/flags.nims"

include ".config/arch.nims"
include ".config/buildmode.nims"
include ".config/devtools.nims"
include ".config/who.nims"

#=======================================
# Constants
#=======================================

let

    colors: tuple = (
        gray: grayColor.fg,
        green: greenColor.bold,
        magenta: magentaColor.fg,
        red: redColor.fg
    )

    styles: tuple = (
        clear: resetColor(),
        bold: bold()
    )

    root = getHomeDir()/".arturo"

    paths: tuple = (
        target:         root/"bin",
        targetLib:      root/"lib",
        targetStores:   root/"stores",
        mainFile:       "src"/"arturo.nim",
    )


#=======================================
# Variables
#=======================================

var
    BINARY              = "bin/arturo"
    TARGET_FILE         = paths.target/"arturo".toExe

    ARGS: seq[string]   = @[]

#=======================================
# Forward declarations
#=======================================

proc getShellRc*(): string

#=======================================
# Types
#=======================================

type BuildConfig = tuple
    binary, version: string
    shouldCompress, shouldInstall, shouldLog, isDeveloper: bool

func webVersion(config: BuildConfig): bool

func backend(config: BuildConfig): string =
    result = "c"
    if config.webVersion:
        return "js"

func silentCompilation(config: BuildConfig): bool =
    ## CI and User builds should actually be silent,
    ## the most important is the exit code.
    ## But for developers, it's useful to have a detailed log.
    not (config.isDeveloper or config.shouldLog)

func webVersion(config: BuildConfig): bool =
    config.version == "@web"

func buildConfig(): BuildConfig =
    (
        binary:             "bin/arturo".toExe,
        version:            "@full",
        shouldCompress:     true,
        shouldInstall:      true,
        shouldLog:          false,
        isDeveloper:        false,
    )

#=======================================
# Output
#=======================================

proc log(msg: string) =
    for line in msg.splitlines:
        echo colors.gray, "  " & line.dedent, styles.clear

proc warn(msg: string) =
    echo colors.red, msg.dedent, styles.clear

proc panic(msg: string = "", exitCode: int = QuitFailure) =
    warn msg
    quit exitCode

func sep(ch: char = '='): string =
    return "".align(80, ch)

proc showLogo*() =
    echo sep()
    echo r"{colors.green}                 _                                     ".fmt
    echo r"                              | |                                    "
    echo r"                     __ _ _ __| |_ _   _ _ __ ___                    "
    echo r"                    / _` | '__| __| | | | '__/ _ \                   "
    echo r"                   | (_| | |  | |_| |_| | | | (_) |                  "
    echo r"                    \__,_|_|   \__|\__,_|_|  \___/                   "
    echo r"{styles.clear}{styles.bold}                                          ".fmt
    echo r"                     Arturo Programming Language{styles.clear}       ".fmt
    echo r"                      (c)2023 Yanis Zafirópulos                      "
    echo r"                                                                     "

proc showHeader*(title: string) =
    echo sep()
    echo fmt" ► {title.toUpperAscii()}"
    echo sep()

proc section*(title: string) =
    echo fmt"{styles.clear}"
    echo sep('-')
    echo fmt" {colors.magenta}●{styles.clear} {title}"
    echo sep('-')

proc showFooter*() =
    echo fmt"{styles.clear}"
    echo sep()
    echo fmt" {colors.magenta}●{styles.clear}{colors.green} Awesome!{styles.clear}"
    echo sep()
    echo "   Arturo has been successfully built & installed!"
    if hostOS != "windows":
        echo ""
        echo "   To be able to run it,"
        echo "   first make sure its in your $PATH:"
        echo ""
        echo "          export PATH=$HOME/.arturo/bin:$PATH"
        echo ""
        echo fmt"   and add it to your {getShellRc()},"
        echo "   so that it's set automatically every time."
    echo ""
    echo "   Rock on! :)"
    echo sep()
    echo fmt"{styles.clear}"

proc showEnvironment*() =
    section "Checking environment..."

    log fmt"os: {hostOS}"
    log fmt"compiler: Nim v{NimVersion}"

proc showBuildInfo*(config: BuildConfig) =
    let
        params = flags.join(" ")
        version = "version/version".staticRead()
        build = "version/build".staticRead()

    section "Building..."
    log fmt"version: {version}/{build}"
    log fmt"config: {config.version}"

    if not config.silentCompilation:
        log fmt"flags: {params}"

#=======================================
# Helpers
#=======================================

func toErrorCode(a: bool): int =
    if a:
        return QuitSuccess
    else:
        return QuitFailure

template unless(condition: bool, body: untyped) =
    if not condition:
        body

# TODO(build.nims) JavaScript compression not working correctly
#  labels: web,bug
proc recompressJS*(jsFile: string) =
    let outputFile = jsFile #.replace(".min.js", ".final.min.js")
    var js = readFile(jsFile)

    # replace Field0, Field1, etc with F0, F1, etc
    js = js.replaceWord("Field0", "F0")
           .replaceWord("Field1", "F1")
           .replaceWord("Field2", "F2")
           .replaceWord("Field3", "F3")

    # replace redundant error messages
    js = js.multiReplace(
        ("field '", ""),
        ("' is not accessible for type '", ""),
        ("' using ", ""),
        ("'kind = ", ""),
        ("'iKind = ", ""),
        ("'tpKind = ", ""),
        ("'fnKind = ", "")
    )

    writeFile(outputFile, js)

proc getShellRc*(): string =
    # will only be called on non-Windows systems -
    # are there any more shells that are not taken into account?
    let (output, _) = gorgeEx("echo $SHELL")
    case output:
        of "/bin/zsh":
            result = "~/.zshrc"
        of "/bin/bash":
            result = "~/.bashrc or ~/.profile"
        of "/bin/sh":
            result = "~/.profile"
        else:
            result = "~/.profile"

proc miniBuild*() =
    # all the necessary "modes" for mini builds
    miniBuildConfig()

    # plus, shrinking + the MINI flag
    if hostOS=="freebsd" or hostOS=="openbsd" or hostOS=="netbsd":
        --verbosity:3

proc compressBinary(config: BuildConfig) =
    assert config.shouldCompress
    assert config.webVersion:
        "Compress should work only for @web versions."

    section "Post-processing..."

    log "compressing binary..."
    let minBin = config.binary.replace(".js",".min.js")
    let CompressionRessult =
        gorgeEx fmt"uglifyjs {config.binary} -c -m ""toplevel,reserved=['A$']"" -c -o {minBin}"

    if CompressionRessult.exitCode != QuitSuccess:
        warn "uglifyjs: 3rd-party tool not available"
    else:
        recompressJS(minBin)

proc verifyDirectories*() =
    log "setting up directories..."
    # create target dirs recursively, if they don't exist
    mkdir paths.target
    mkdir paths.targetLib
    mkdir paths.targetStores

proc updateBuild*() =
    # will only be called in DEV mode -
    # basically, increment the build number by one and perform a git commit
    writeFile("version/build", $(readFile("version/build").strip.parseInt + 1))
    let (output, _) = gorgeEx fmt"git commit -m 'build update' version/build"
    for ln in output.split("\n"):
        echo ln.strip()

proc compile*(config: BuildConfig, showFooter: bool = false): int
    {. raises: [OSError, ValueError, Exception] .} =

    result = QuitSuccess
    let
        params = flags.join(" ")

    proc windowsHostSpecific() =
        if config.isDeveloper and not flags.contains("NOWEBVIEW"):
            discard gorgeEx "src\\extras\\webview\\deps\\build.bat"
        --passL:"\"-static-libstdc++ -static-libgcc -Wl,-Bstatic -lstdc++ -Wl,-Bdynamic\""
        --gcc.linkerexe:"g++"

    proc unixHostSpecific() =
        --passL:"\"-lm\""

    if "windows" == hostOS:
         windowsHostSpecific()
    else:
        unixHostSpecific()

    if config.silentCompilation:
        let res = gorgeEx fmt"nim {config.backend} {params} -o:{config.binary} {paths.mainFile}"
        result = res.exitCode
    else:
        echo fmt"{colors.gray}"
        exec fmt"nim {config.backend} {params} -o:{config.binary} {paths.mainFile}"

proc installAll*(config: BuildConfig) =

    # Helper functions

    proc copy(file: string, from: string, to: string) =
        cpFile from.joinPath(file), to.joinPath(file)

    # Methods
    
    proc copyWebView() =
        let sourcePath = "src\\extras\\webview\\deps\\dlls\\x64\\"
            targetPath = "bin"
        log "copying webview..."
        "webview.dll".copy(sourcePath, targetPath)
        "WebView2Loader.dll".copy(sourcePath, targetPath)

    proc copyArturo(config: BuildConfig) =
        log "copying files..."
        cpFile(config.binary, TARGET_FILE)

    proc giveBinaryPermission() =
        exec fmt"chmod +x {TARGET_FILE}"

    proc main(config: BuildConfig)
        assert not config.webVersion:
            "Web builds can't be installed"

        section "Installing..."

        verifyDirectories()
        config.copyArturo()

        if hostOS != "windows":
            giveBinaryPermission()
        else:
            copyWebView()

        log fmt"deployed to: {root}"

    main(config)

#=======================================
# Methods
#=======================================

proc buildArturo*(config: BuildConfig) =
    
    # Methods 

    proc showInfo(config: BuildConfig) =
        showEnvironment()
        config.showBuildInfo()

    proc setDevmodeUp() =
        section "Updating build..."
        updateBuild()
        devConfig()

    proc tryCompilation(config: BuildConfig) =
        if (let cd = config.compile(showFooter=true); cd != 0):
            quit(cd)

    proc main() =
        showHeader "install"

        if config.isDeveloper:
            setDevmodeUp()

        config.showInfo()
        config.tryCompilation()
        config.compressBinary()

        if config.shouldInstall:
            config.installAll()

        showFooter()

    main()

proc buildPackage*(config: BuildConfig) =

    # Helper functions

    proc dataFile(package: string): string =
        return fmt"{package}.data.json"

    proc file(package: string): string =
        return fmt"{package}.art"

    proc info(package: string): string =
        staticExec fmt"arturo --package-info {package.file}"

    # Subroutines

    proc generateData(package: string) =
        section "Processing data..."
        (package.dataFile).writeFile(package.info)
        log fmt"written to: {package.dataFile}"

    proc setEnvUp(package: string) =
        section "Setting up options..."

        putEnv "PORTABLE_INPUT", package.file
        putEnv "PORTABLE_DATA", package.dataFile

        log fmt"done!"

    proc setFlagsUp() =
        --forceBuild:on
        --opt:size
        --define:NOERRORLINES
        --define:PORTABLE

    proc showFlags() =
        let params = flags.join(" ")
        log fmt"FLAGS: {params}"
        echo ""

    proc cleanUp(package: string) =
        rmFile package.dataFile
        echo fmt"{styles.clear}"

    proc main() =
        let package = config.binary

        showHeader "package"

        package.generateData()
        package.setEnvUp()
        showEnvironment()
        config.showBuildInfo()

        setFlagsUp()
        showFlags()

        if (let cd = compile(config, showFooter=false); cd != 0):
            quit(cd)

        package.cleanUp()

    main()


proc buildDocs*() =
    let params = flags.join(" ")

    showHeader "docs"

    section "Generating documentation..."
    exec fmt"nim doc --project --index:on --outdir:dev-docs {params} src/arturo.nim"
    exec "nim buildIndex -o:dev-docs/theindex.html dev-docs"

proc performTests*(binary: string): bool =
    result = true

    showHeader "test"
    try:
        exec fmt"{binary} ./tools/tester.art"
    except:
        return false

proc performBenchmarks*(binary: string): bool =
    result = true

    showHeader "benchmark"
    try:
        exec fmt"{binary} ./tools/benchmarker.art"
    except:
        return false

#=======================================
# Main
#=======================================

showLogo()

cmd install, "Build arturo and install executable":
    ## build:
    ##     Provides a cross-compilation for the Arturo's binary.
    ##
    ##     --arch: $hostCPU             chooses the target CPU
    ##          [amd64, arm, arm64, i386, x86]
    ##     --build -b: string = full    chooses the target Build Version
    ##          [full, mini, web]
    ##     --os: $hostOS                chooses the target OS
    ##          [freebsd, linux, openbsd, mac, macos, macosx, netbsd, win, windows]
    ##     --profiler -p: none          defines which profiler use
    ##          [default, mem, native, none, profile]
    ##     --who: string = user         defines who is compiling the code
    ##          [dev, user]
    ##     --debug -d                   enables debugging
    ##     --local                      disables installation
    ##     --log -l                     shows compilation logs
    ##     --raw                        disables compression
    ##     --help

    const
        availableCPUs = @["amd-64", "x64", "x86-64", "arm-64", "i386", "x86",
                          "x86-32", "arm", "arm-32"]
        availableOSes = @["freebsd", "openbsd", "netbsd", "linux", "mac",
                          "macos", "macosx", "win", "windows",]
        availableBuilds = @["full", "mini", "safe", "web"]
        availableProfilers = @["default", "mem", "native", "profile"]

    var config = buildConfig()

    match args.getOptionValue("arch", short="a",
                              default=hostCPU,
                              into=availableCPUs):
        let
            amd64 = availableCPUs[0..2]
            arm64 = [availableCPUs[3]]
            x86 = availableCPUs[4..6]
            arm32 = availableCPUs[7..8]

        >> amd64: amd64Config()
        >> arm64: arm64Config()
        >> x86:   arm64Config()
        >> arm32: arm32Config()

    match args.getOptionValue("build", default="full", into=availableBuilds):
        >> ["full"]:
            fullBuildConfig()
        >> ["mini"]:
            miniBuildConfig()
            config.version = "@mini"
            miniBuild()
        >> ["safe"]:
            safeBuildConfig()
            miniBuild()
        >> ["web"]:
            config.binary     = config.binary
                                      .replace(".exe", ".js")
            config.version    = "@web"
            miniBuild()

    match args.getOptionValue("os", default=hostOS, into=availableOSes):
        let
            bsd = availableOSes[0..2]
            linux = [availableOSes[3]]
            macos = availableOSes[4..6]
            windows = availableOSes[7..8]

        >> bsd:     discard
        >> linux:   discard
        >> macos:   discard
        >> windows: discard

    match args.getOptionValue("profiler", default="none", short="p",
                              into=availableProfilers):
        >> ["default"]: profilerConfig()
        >> ["mem"]:     memProfileConfig()
        >> ["native"]:  nativeProfileConfig()
        >> ["profile"]: profileConfig()

    match args.getOptionValue("who", default="", into= @["user", "dev"]):
        >> ["user"]:
            config.isDeveloper = false
            userConfig()
        >> ["dev"]:
            config.isDeveloper = true
            devConfig()

    if args.hasFlag("debug", "d"):
        config.shouldCompress = false
        debugConfig()

    if args.hasFlag("local"):
        config.shouldInstall = false

    if args.hasFlag("log", "l"):
        config.shouldLog = true

    if args.hasFlag("raw"):
        config.shouldCompress = false

    if args.hasFlag("release"):
        releaseConfig()

    config.buildArturo()

cmd package, "Package arturo app and build executable":
    ## package <pkg-name>:
    ##     Compiles packages into executables.
    ##
    ##     --arch: $hostCPU             chooses the target CPU
    ##          [amd64, arm, arm64, i386, x86]
    ##     --debug -d                   enables debugging
    ##     --help

    const availableCPUs = @["amd-64", "x64", "x86-64", "arm-64", "i386", "x86",
                          "x86-32", "arm", "arm-32"]

    var config = buildConfig()
    config.binary = args.getPositionalArg()

    match args.getOptionValue("arch", short="a",
                              default=hostCPU,
                              into=availableCPUs):
        let
            amd64 = availableCPUs[0..2]
            arm64 = [availableCPUs[3]]
            x86 = availableCPUs[4..6]
            arm32 = availableCPUs[7..8]

        >> amd64: amd64Config()
        >> arm64: arm64Config()
        >> x86:   arm64Config()
        >> arm32: arm32Config()

    if args.hasFlag("debug", "d"):
        config.shouldCompress = false
        debugConfig()

    config.buildPackage()

cmd docs, "Build the documentation":
    ## docs:
    ##     Builds the developer documentation
    ##
    ##     --help

    --define:DOCGEN
    buildDocs()

cmd test, "Run test suite":
    ## test:
    ##     Runs test suite
    ##
    ##     --help

    let
        localBin = BINARY.toExe
        installedBin = TARGET_FILE

    unless performTests(installedBin):
        quit performTests(localBin).toErrorCode

cmd benchmark, "Run benchmark suite":
    ## benchmark:
    ##     Runs benchmark suite
    ##
    ##     --help

    let
        localBin = BINARY.toExe
        installedBin = TARGET_FILE

    unless performBenchmarks(installedBin):
        quit performBenchmarks(localBin).toErrorCode