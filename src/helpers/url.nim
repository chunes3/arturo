######################################################
# Arturo
# Programming Language + Bytecode VM compiler
# (c) 2019-2020 Yanis Zafirópulos
#
# @file: helpers/url.nim
######################################################

#=======================================
# Libraries
#=======================================

import re

#=======================================
# Methods
#=======================================

proc isUrl*(s: string): bool {.inline.} =
    return s.match(re"^(?:http(s)?:\/\/)[\w.-]+(?:\.[\w\.-]+)+[\w\-\._~:/?#[\]@!\$&'\(\)\*\+,;=.]+$")