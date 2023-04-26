#=======================================================
# Arturo
# Programming Language + Bytecode VM compiler
# (c) 2019-2023 Yanis Zafirópulos
#
# @file: vm/values/custom/vrational.nim
#=======================================================

## The internal `:rational` type

# Contains code based on
# the Rationals module: https://raw.githubusercontent.com/nim-lang/Nim/version-1-6/lib/pure/rationals.nim
# which forms part of the Nim standard library.
# (c) Copyright 2015 Dennis Felsing

#=======================================
# Libraries
#=======================================

import hashes, math, strformat

when not defined(NOGMP):
    import helpers/bignums

#=======================================
# Types
#=======================================

# TODO(VM/values/custom/vrational) add support for BigNum based rational numbers
#  see: https://discord.com/channels/765519132186640445/829324913097048065/1078783018187100341
#  labels: values, enhancement

type 
    VRationalObj*[T] = object
        num*: T
        den*: T

    RationalKind* = enum
        NormalRational,
        BigRational

    VRational* = object
        case rKind*: RationalKind:
            of NormalRational:
                r*: VRationalObj[int]
            of BigRational:
                when not defined(NOGMP):
                    br*: Rat

#=======================================
# Methods
#=======================================

template getNumerator*(x: VRational, big: bool = false): untyped =
    when big:
        numerator(x.br)
    else:
        x.r.num

template getDenominator*(x: VRational, big: bool = false): untyped =
    when big:
        denominator(x.br)
    else:
        x.r.den

func reduce*(x: var VRational) =
    let common = gcd(x.r.num, x.r.den)
    if x.r.den > 0:
        x.r.num = x.r.num div common
        x.r.den = x.r.den div common
    elif x.r.den < 0:
        x.r.num = -x.r.num div common
        x.r.den = -x.r.den div common
    else:
        raise newException(DivByZeroDefect, "division by zero")

func initRational*(num, den: int): VRational =
    result.rKind = NormalRational
    result.r.num = num
    result.r.den = den
    reduce(result)

func simplifyRational*(x: var VRational) =
    if x.rKind == BigRational and canBeSimplified(x.br):
        x = initRational(getInt(numerator(x.br)), getInt(denominator(x.br)))

func initRational*(num: Int, den: Int): VRational =
    result.rKind = BigRational
    result.br = newRat(num, den)

    simplifyRational(result)

func initRational*(num: int, den: Int): VRational =
    result.rKind = BigRational
    result.br = newRat(newInt(num), den)
    
    simplifyRational(result)

func initRational*(num: Int, den: int): VRational =
    result.rKind = BigRational
    result.br = newRat(num, newInt(den))

    simplifyRational(result)

func `//`*(num, den: int): VRational =
    initRational(num, den)

func toRational*(x: int): VRational =
    result.rKind = NormalRational
    result.r.num = x
    result.r.den = 1

when not defined(NOGMP):
    func toBigRational*(x: int | Int | float): VRational =
        result.rKind = BigRational
        result.br = newRat(x)
        
        simplifyRational(result)

    func toBigRational*(x: VRational): VRational =
        result.rKind = BigRational
        result.br = newRat(x.r.num, x.r.den)

func toRational*(x: float, n: int = high(int) shr (sizeof(int) div 2 * 8)): VRational =
    var
        m11, m22 = 1
        m12, m21 = 0
        ai = int(x)
        initial = x
        x = x
    while m21 * ai + m22 <= n:
        swap m12, m11
        swap m22, m21
        m11 = m12 * ai + m11
        m21 = m22 * ai + m21
        if x == float(ai): 
            break # division by zero
        x = 1 / (x - float(ai))
        if x > float(high(int32)): 
            when not defined(NOGMP):
                if m11 == 0 or m21 == 0: 
                    return toBigRational(initial)
                else: 
                    break
            else:
                break # representation failure; should throw error?
        ai = int(x)
    result = m11 // m21

func toFloat*(x: VRational): float =
    if x.rKind == NormalRational:
        result = x.r.num / x.r.den
    else:
        when not defined(NOGMP):
            result = toCDouble(x.br)

func toInt*(x: VRational): int =
    if x.rKind == NormalRational:
        result = x.r.num div x.r.den
    else:
        discard
        # show error

func `+`*(x, y: VRational): VRational =
    if x.rKind == NormalRational:
        if y.rKind == NormalRational:
            let common = lcm(x.r.den, y.r.den)
            result.rKind = NormalRational
            result.r.num = common div x.r.den * x.r.num + common div y.r.den * y.r.num
            result.r.den = common
            reduce(result)
        else:
            result = x + toBigRational(y)
    else:
        if y.rKind == NormalRational:
            result = toBigRational(x) + y
        else:
            result = VRational(
                rKind: BigRational,
                br: x.br + y.br
            )

func `+`*(x: VRational, y: int): VRational =
    if x.rKind == NormalRational:
        result.rKind = NormalRational
        result.r.num = x.r.num + y * x.r.den
        result.r.den = x.r.den
    else:
        result = x + toBigRational(y)

func `+`*(x: int, y: VRational): VRational =
    if y.rKind == NormalRational:
        result.rKind = NormalRational
        result.r.num = y.r.num + x * y.r.den
        result.r.den = y.r.den
    else:
        result = toBigRational(x) + y

func `+=`*(x: var VRational, y: VRational) =
    if x.rKind == NormalRational:
        if y.rKind == NormalRational:
            let common = lcm(x.r.den, y.r.den)
            x.r.num = common div x.r.den * x.r.num + common div y.r.den * y.r.num
            x.r.den = common
            reduce(x)
        else:
            x += toBigRational(y)
    else:
        if y.rKind == NormalRational:
            x = toBigRational(x) + y
        else:
            x.br += y.br

func `+=`*(x: var VRational, y: int) =
    if x.rKind == NormalRational:
        x.r.num += y * x.r.den
    else:
        x += toBigRational(y)

func `-`*(x: VRational): VRational =
    if x.rKind == NormalRational:
        result.r.num = -x.r.num
        result.r.den = x.r.den
    else:
        result.rKind = BigRational
        result.br = neg(x.br)

func `-`*(x, y: VRational): VRational =
    if x.rKind == NormalRational:
        if y.rKind == NormalRational:
            let common = lcm(x.r.den, y.r.den)
            result.r.num = common div x.r.den * x.r.num - common div y.r.den * y.r.num
            result.r.den = common
            reduce(result)
        else:
            result = toBigRational(x) - y
    else:
        if y.rKind == NormalRational:
            result = x - toBigRational(y)
        else:
            result = VRational(
                rKind: BigRational,
                br: x.br - y.br
            )

func `-`*(x: VRational, y: int): VRational =
    if x.rKind == NormalRational:
        result.rKind = NormalRational
        result.r.num = x.r.num - y * x.r.den
        result.r.den = x.r.den
    else:
        result = x - toBigRational(y)

func `-`*(x: int, y: VRational): VRational =
    if y.rKind == NormalRational:
        result.rKind = NormalRational
        result.r.num = x * y.r.den - y.r.num
        result.r.den = y.r.den
    else:
        result = toBigRational(x) - y

func `-=`*(x: var VRational, y: VRational) =
    if x.rKind == NormalRational:
        if y.rKind == NormalRational:
            let common = lcm(x.r.den, y.r.den)
            x.r.num = common div x.r.den * x.r.num - common div y.r.den * y.r.num
            x.r.den = common
            reduce(x)
        else:
            x -= toBigRational(y)
    else:
        if y.rKind == NormalRational:
            x = toBigRational(x) - y
        else:
            x.br -= y.br
    
func `-=`*(x: var VRational, y: int) =
    if x.rKind == NormalRational:
        x.r.num -= y * x.r.den
    else:
        x -= toBigRational(y)

func `*`*(x, y: VRational): VRational =
    if x.rKind == NormalRational:
        if y.rKind == NormalRational:
            result.rKind = NormalRational
            result.r.num = x.r.num * y.r.num
            result.r.den = x.r.den * y.r.den
            reduce(result)
        else:
            result = toBigRational(x) * y
    else:
        if y.rKind == NormalRational:
            result = x * toBigRational(y)
        else:
            result = VRational(
                rKind: BigRational,
                br: x.br * y.br
            )
    
func `*`*(x: VRational, y: int): VRational =
    if x.rKind == NormalRational:
        result.rKind = NormalRational
        result.r.num = x.r.num * y
        result.r.den = x.r.den
        reduce(result)
    else:
        result = x * toBigRational(y)

func `*`*(x: int, y: VRational): VRational =
    if y.rKind == NormalRational:
        result.rKind = NormalRational
        result.r.num = x * y.r.num
        result.r.den = y.r.den
        reduce(result)
    else:
        result = toBigRational(x) * y

func `*=`*(x: var VRational, y: VRational) =
    if x.rKind == NormalRational:
        x.r.num *= y.r.num
        x.r.den *= y.r.den
        reduce(x)
    else:
        x *= toBigRational(y)

func `*=`*(x: var VRational, y: int) =
    if x.rKind == NormalRational:
        x.r.num *= y
        reduce(x)
    else:
        x *= toBigRational(y)

func reciprocal*(x: VRational): VRational =
    if x.rKind == NormalRational:
        result.rKind = NormalRational
        if x.r.num > 0:
            result.r.num = x.r.den
            result.r.den = x.r.num
        elif x.r.num < 0:
            result.r.num = -x.r.den
            result.r.den = -x.r.num
        else:
            raise newException(DivByZeroDefect, "division by zero")
    else:
        result.rKind = BigRational
        result.br = inv(x.br)

func `/`*(x, y: VRational): VRational =
    if x.rKind == NormalRational:
        if y.rKind == NormalRational:
            result.r.num = x.r.num * y.r.den
            result.r.den = x.r.den * y.r.num
            reduce(result)
        else:
            result = toBigRational(x) / y
    else:
        if y.rKind == NormalRational:
            result = x / toBigRational(y)
        else:
            result = VRational(
                rKind: BigRational,
                br: x.br / y.br
            )

func `/`*(x: VRational, y: int): VRational =
    if x.rKind == NormalRational:
        result.rKind = NormalRational
        result.r.num = x.r.num
        result.r.den = x.r.den * y
        reduce(result)
    else:
        result = x / toBigRational(y)

func `/`*(x: int, y: VRational): VRational =
    if y.rKind == NormalRational:
        result.rKind = NormalRational
        result.r.num = x * y.r.den
        result.r.den = y.r.num
        reduce(result)
    else:
        result = toBigRational(x) / y

func `/=`*(x: var VRational, y: VRational) =
    if x.rKind == NormalRational:
        x.r.num *= y.r.den
        x.r.den *= y.r.num
        reduce(x)
    else:
        x.br /= y.br

func `/=`*(x: var VRational, y: int) =
    if x.rKind == NormalRational:
        x.r.den *= y
        reduce(x)
    else:
        x /= toBigRational(y)

func `^`*(x: VRational, y: int): VRational =
    if x.rKind == NormalRational:
        if y < 0:
            result.r.num = x.r.den ^ -y
            result.r.den = x.r.num ^ -y
        else:
            result.r.num = x.r.num ^ y
            result.r.den = x.r.den ^ y
    else:
        result = VRational(
            rKind: BigRational,
            br: x.br ^ y
        )

func `^`*(x: VRational, y: float): VRational =
    if x.rKind == NormalRational:
        result = toBigRational(x) ^ y
    else:
        result = VRational(
            rKind: BigRational,
            br: x.br ^ y
        )

func cmp*(x, y: VRational): int =
    if x.rKind == NormalRational:
        if y.rKind == NormalRational:
            result = (x - y).r.num
        else:
            result = cmp(toBigRational(x), y)
    else:
        if y.rKind == NormalRational:
            result = cmp(x, toBigRational(y))
        else:
            result = cmp(x.br, y.br)

func `<`*(x, y: VRational): bool =
    if x.rKind == NormalRational:
        if y.rKind == NormalRational:
            result = (x - y).r.num < 0
        else:
            result = toBigRational(x) < y
    else:
        if y.rKind == NormalRational:
            result = x < toBigRational(y)
        else:
            result = x.br < y.br

func `<=`*(x, y: VRational): bool =
    if x.rKind == NormalRational:
        if y.rKind == NormalRational:
            result = (x - y).r.num <= 0
        else:
            result = toBigRational(x) <= y
    else:
        if y.rKind == NormalRational:
            result = x <= toBigRational(y)
        else:
            result = x.br <= y.br

func `==`*(x, y: VRational): bool =
    if x.rKind == NormalRational:
        if y.rKind == NormalRational:
            result = (x - y).r.num == 0
        else:
            result = toBigRational(x) == y
    else:
        if y.rKind == NormalRational:
            result = x == toBigRational(y)
        else:
            result = x.br == y.br

func abs*(x: VRational): VRational =
    if x.rKind == NormalRational:
        result.rKind = NormalRational
        result.r.num = abs x.r.num
        result.r.den = abs x.r.den
    else:
        result.rKind = BigRational
        result.br = abs(x.br)

func `div`*(x, y: VRational): int =
    if x.rKind == NormalRational:
        if y.rKind == NormalRational:
            result = x.r.num * y.r.den div y.r.num * x.r.den
        else:
            raise newException(DivByZeroDefect, "div not supported")
    else:
        raise newException(DivByZeroDefect, "div not supported")

func `mod`*(x, y: VRational): VRational =
    if x.rKind == NormalRational:
        if y.rKind == NormalRational:
            result.rKind = NormalRational
            result.r.num = (x.r.num * y.r.den) mod (y.r.num * x.r.den)
            result.r.den = x.r.den * y.r.den
            reduce(result)
        else:
            raise newException(DivByZeroDefect, "mod not supported")
    else:
        raise newException(DivByZeroDefect, "mod not supported")

func floorDiv*(x, y: VRational): int =
    if x.rKind == NormalRational:
        if y.rKind == NormalRational:
            result = floorDiv(x.r.num * y.r.den, y.r.num * x.r.den)
        else:
            raise newException(DivByZeroDefect, "floorDiv not supported")
    else:
        raise newException(DivByZeroDefect, "floorDiv not supported")

func floorMod*(x, y: VRational): VRational =
    if x.rKind == NormalRational:
        if y.rKind == NormalRational:
            result.rKind = NormalRational
            result.r.num = floorMod(x.r.num * y.r.den, y.r.num * x.r.den)
            result.r.den = x.r.den * y.r.den
            reduce(result)
        else:
            raise newException(DivByZeroDefect, "floorMod not supported")
    else:
        raise newException(DivByZeroDefect, "floorMod not supported")

func isZero*(x: VRational): bool =
    if x.rKind == NormalRational:
        result = x.r.num == 0
    else:
        result = numerator(x.br) == 0

func isNegative*(x: VRational): bool =
    if x.rKind == NormalRational:
        result = x.r.num < 0
    else:
        result = numerator(x.br) < 0

func isPositive*(x: VRational): bool =
    if x.rKind == NormalRational:
        result = x.r.num > 0
    else:
        result = numerator(x.br) > 0

func hash*(x: VRational): Hash =
    if x.rKind == NormalRational:
        var copy = x
        reduce(copy)

        var h: Hash = 0
        h = h !& hash(copy.r.num)
        h = h !& hash(copy.r.den)
        result = !$h
    else:
        result = hash(x.br[])

func codify*(x: VRational): string =
    if x.rKind == NormalRational:
        if x.r.num < 0:
            result = fmt("to :rational @[neg {x.r.num * -1} {x.r.den}]")
        else:
            result = fmt("to :rational [{x.r.num} {x.r.den}]")
    else:
        let num = numerator(x.br)
        let den = denominator(x.br)
        if num < 0:
            result = fmt("to :rational @[neg {num * -1} {den}]")
        else:
            result = fmt("to :rational [{num} {den}]")

func `$`*(x: VRational): string =
    if x.rKind == NormalRational:
        result = $x.r.num & "/" & $x.r.den
    else:
        when not defined(NOGMP):
            result = $x.br