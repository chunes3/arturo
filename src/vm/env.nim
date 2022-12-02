#=======================================================
# Arturo
# Programming Language + Bytecode VM compiler
# (c) 2019-2022 Yanis Zafirópulos
#
# @file: vm/env.nim
#=======================================================

## General environment configuration, paths, etc.

#=======================================
# Libraries
#=======================================
when not defined(WEB) and not defined(windows):
    import parseopt, sequtils, sugar

import os, strutils, tables, times

import helpers/terminal

import vm/[parse,values/value]
import vm/values/custom/[vlogical]

#=======================================
# Globals
#=======================================

var 
    PathStack*  {.threadvar.}: seq[string]      ## The main path stack
    HomeDir*    : string                        ## User's home directory
    TmpDir*     : string                        ## User's temp directory

    #--------------------
    # private
    #--------------------
    Arguments       : Value
    ArturoVersion   : string
    ArturoBuild     : string

    ScriptInfo      : Value

#=======================================
# Helpers
#=======================================

proc getCmdlineArgumentArray*(): Value =
    ## return all command0line arguments as 
    ## a Block value
    Arguments

proc parseCmdlineValue(v: string): Value =
    if v=="" or v=="true" or v=="on": return newLogical(True)
    elif v=="false" or v=="off": return newLogical(False)
    else:
        try:
            discard parseFloat(v)
            return doParse(v, isFile=false).a[0]
        except:
            return newString(v)

# TODO(Env\parseCmdlineArguments) verify it's working right
#  labels: vm,library,language,unit-test
proc parseCmdlineArguments*(): ValueDict =
    ## parse command-line arguments and return 
    ## result as a Dictionary value
    result = initOrderedTable[string,Value]()
    var values: ValueArray

    when not defined(windows) and not defined(WEB):
        var p = initOptParser(Arguments.a.map((x)=>x.s))
        for kind, key, val in p.getopt():
            case kind
                of cmdArgument:
                    values.add(parseCmdlineValue(key))
                of cmdLongOption, cmdShortOption:
                    result[key] = parseCmdlineValue(val)
                of cmdEnd: assert(false) # cannot happen
    else:
        values = Arguments.a

    result["values"] = newBlock(values)

proc getSystemInfo*(): ValueDict =
    ## return system info as a Dictionary value
    {
        "author"    : newString("Yanis Zafirópulos"),
        "copyright" : newString("(c) 2019-2022"),
        "version"   : newVersion(ArturoVersion),
        "build"     : newInteger(parseInt(ArturoBuild)),
        "buildDate" : newDate(now()),
        "binary"    : 
            when defined(WEB):
                newString("arturo.js")
            else:
                newString(getAppFilename()),
        "cpu"       : newString(hostCPU),
        "os"        : newString(hostOS),
        "release"   : 
            when defined(MINI):
                newLiteral("mini")
            else:
                newLiteral("full")
    }.toOrderedTable

proc getPathInfo*(): ValueDict =
    ## return path info as a Dictionary value
    {
        "current"   : newString(getCurrentDir()),
        "home"      : newString(HomeDir),
        "temp"      : newString(TmpDir),
    }.toOrderedTable

proc getScriptInfo*(): Value =
    ## return script info as a Dictionary value
    ScriptInfo

#=======================================
# Methods
#=======================================

proc entryPath*(): string =
    ## get initial script path
    PathStack[0]

proc currentPath*(): string =
    ## get current path
    PathStack[^1]

proc addPath*(newPath: string) =
    ## add given path to path stack
    var (dir, _, _) = splitFile(newPath)
    PathStack.add(dir)

proc popPath*(): string =
    ## pop last path from path stack
    PathStack.pop()

proc initEnv*(arguments: seq[string], version: string, build: string, script: Value) =
    ## initialize environment with given arguments
    Arguments = newStringBlock(arguments)
    ArturoVersion = version
    ArturoBuild = build

    if not script.isNil:
        ScriptInfo = script
    else:
        ScriptInfo = newDictionary()

    PathStack = @[]
    when not defined(WEB):
        HomeDir = getHomeDir()
        TmpDir  = getTempDir()

proc setColors*(muted: bool = false) =
    ## switch terminal colors on/off, globally
    NoColors = muted