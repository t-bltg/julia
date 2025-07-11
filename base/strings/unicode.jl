# This file is a part of Julia. License is MIT: https://julialang.org/license

# Various Unicode functionality from the utf8proc library
module Unicode

import Base: show, ==, hash, string, Symbol, isless, length, eltype,
             convert, isvalid, ismalformed, isoverlong, iterate,
             AnnotatedString, AnnotatedChar, annotated_chartransform,
             @assume_effects, annotations, is_overlong_enc

# whether codepoints are valid Unicode scalar values, i.e. 0-0xd7ff, 0xe000-0x10ffff

"""
    isvalid(value)::Bool

Return `true` if the given value is valid for its type, which currently can be either
`AbstractChar` or `String` or `SubString{String}`.

# Examples
```jldoctest
julia> isvalid(Char(0xd800))
false

julia> isvalid(SubString(String(UInt8[0xfe,0x80,0x80,0x80,0x80,0x80]),1,2))
false

julia> isvalid(Char(0xd799))
true
```
"""
isvalid(value)

"""
    isvalid(T, value)::Bool

Return `true` if the given value is valid for that type. Types currently can
be either `AbstractChar` or `String`. Values for `AbstractChar` can be of type `AbstractChar` or [`UInt32`](@ref).
Values for `String` can be of that type, `SubString{String}`, `Vector{UInt8}`,
or a contiguous subarray thereof.

# Examples
```jldoctest
julia> isvalid(Char, 0xd800)
false

julia> isvalid(String, SubString("thisisvalid",1,5))
true

julia> isvalid(Char, 0xd799)
true
```

!!! compat "Julia 1.6"
    Support for subarray values was added in Julia 1.6.
"""
isvalid(T,value)

isvalid(c::AbstractChar) = !ismalformed(c) & !isoverlong(c) & ((c ≤ '\ud7ff') | ('\ue000' ≤ c) & (c ≤ '\U10ffff'))
isvalid(::Type{<:AbstractChar}, c::Unsigned) = ((c ≤  0xd7ff ) | ( 0xe000  ≤ c) & (c ≤  0x10ffff ))
isvalid(::Type{T}, c::Integer) where {T<:AbstractChar}  = isvalid(T, Unsigned(c))
isvalid(::Type{<:AbstractChar}, c::AbstractChar)     = isvalid(c)

# utf8 category constants
const UTF8PROC_CATEGORY_CN = 0
const UTF8PROC_CATEGORY_LU = 1
const UTF8PROC_CATEGORY_LL = 2
const UTF8PROC_CATEGORY_LT = 3
const UTF8PROC_CATEGORY_LM = 4
const UTF8PROC_CATEGORY_LO = 5
const UTF8PROC_CATEGORY_MN = 6
const UTF8PROC_CATEGORY_MC = 7
const UTF8PROC_CATEGORY_ME = 8
const UTF8PROC_CATEGORY_ND = 9
const UTF8PROC_CATEGORY_NL = 10
const UTF8PROC_CATEGORY_NO = 11
const UTF8PROC_CATEGORY_PC = 12
const UTF8PROC_CATEGORY_PD = 13
const UTF8PROC_CATEGORY_PS = 14
const UTF8PROC_CATEGORY_PE = 15
const UTF8PROC_CATEGORY_PI = 16
const UTF8PROC_CATEGORY_PF = 17
const UTF8PROC_CATEGORY_PO = 18
const UTF8PROC_CATEGORY_SM = 19
const UTF8PROC_CATEGORY_SC = 20
const UTF8PROC_CATEGORY_SK = 21
const UTF8PROC_CATEGORY_SO = 22
const UTF8PROC_CATEGORY_ZS = 23
const UTF8PROC_CATEGORY_ZL = 24
const UTF8PROC_CATEGORY_ZP = 25
const UTF8PROC_CATEGORY_CC = 26
const UTF8PROC_CATEGORY_CF = 27
const UTF8PROC_CATEGORY_CS = 28
const UTF8PROC_CATEGORY_CO = 29

# strings corresponding to the category constants
const category_strings = [
    "Other, not assigned",
    "Letter, uppercase",
    "Letter, lowercase",
    "Letter, titlecase",
    "Letter, modifier",
    "Letter, other",
    "Mark, nonspacing",
    "Mark, spacing combining",
    "Mark, enclosing",
    "Number, decimal digit",
    "Number, letter",
    "Number, other",
    "Punctuation, connector",
    "Punctuation, dash",
    "Punctuation, open",
    "Punctuation, close",
    "Punctuation, initial quote",
    "Punctuation, final quote",
    "Punctuation, other",
    "Symbol, math",
    "Symbol, currency",
    "Symbol, modifier",
    "Symbol, other",
    "Separator, space",
    "Separator, line",
    "Separator, paragraph",
    "Other, control",
    "Other, format",
    "Other, surrogate",
    "Other, private use",
    "Invalid, too high",
    "Malformed, bad data",
]

const UTF8PROC_STABLE    = (1<<1)
const UTF8PROC_COMPAT    = (1<<2)
const UTF8PROC_COMPOSE   = (1<<3)
const UTF8PROC_DECOMPOSE = (1<<4)
const UTF8PROC_IGNORE    = (1<<5)
const UTF8PROC_REJECTNA  = (1<<6)
const UTF8PROC_NLF2LS    = (1<<7)
const UTF8PROC_NLF2PS    = (1<<8)
const UTF8PROC_NLF2LF    = (UTF8PROC_NLF2LS | UTF8PROC_NLF2PS)
const UTF8PROC_STRIPCC   = (1<<9)
const UTF8PROC_CASEFOLD  = (1<<10)
const UTF8PROC_CHARBOUND = (1<<11)
const UTF8PROC_LUMP      = (1<<12)
const UTF8PROC_STRIPMARK = (1<<13)

############################################################################

utf8proc_error(result) = error(unsafe_string(ccall(:utf8proc_errmsg, Cstring, (Cssize_t,), result)))

# static wrapper around user callback function
utf8proc_custom_func(codepoint::UInt32, callback::Any) =
    UInt32(callback(codepoint))::UInt32

function utf8proc_decompose(str, options, buffer, nwords, chartransform::typeof(identity))
    ret = ccall(:utf8proc_decompose, Int, (Ptr{UInt8}, Int, Ptr{UInt8}, Int, Cint),
                str, sizeof(str), buffer, nwords, options)
    ret < 0 && utf8proc_error(ret)
    return ret
end
function utf8proc_decompose(str, options, buffer, nwords, chartransform::F) where F
    ret = ccall(:utf8proc_decompose_custom, Int, (Ptr{UInt8}, Int, Ptr{UInt8}, Int, Cint, Ptr{Cvoid}, Ref{F}),
                str, sizeof(str), buffer, nwords, options,
                @cfunction(utf8proc_custom_func, UInt32, (UInt32, Ref{F})), chartransform)
    ret < 0 && utf8proc_error(ret)
    return ret
end

function utf8proc_map(str::Union{String,SubString{String}}, options::Integer, chartransform::F = identity) where F
    nwords = utf8proc_decompose(str, options, C_NULL, 0, chartransform)
    buffer = Base.StringVector(nwords*4)
    nwords = utf8proc_decompose(str, options, buffer, nwords, chartransform)
    nbytes = ccall(:utf8proc_reencode, Int, (Ptr{UInt8}, Int, Cint), buffer, nwords, options)
    nbytes < 0 && utf8proc_error(nbytes)
    return String(resize!(buffer, nbytes))
end

"""
`Dict` of `original codepoint => replacement codepoint` normalizations
to perform on Julia identifiers, to canonicalize characters that
are both easily confused and easily inputted by accident.

!!! warning
    When this table is updated, also update the corresponding table in `src/flisp/julia_charmap.h`.
"""
const _julia_charmap = Dict{UInt32,UInt32}(
    0x025B => 0x03B5, # latin small letter open e -> greek small letter epsilon
    0x00B5 => 0x03BC, # micro sign -> greek small letter mu
    0x00B7 => 0x22C5, # middot char -> dot operator (#25098)
    0x0387 => 0x22C5, # Greek interpunct -> dot operator (#25098)
    0x2212 => 0x002D, # minus -> hyphen-minus (#26193)
    0x210F => 0x0127, # hbar -> small letter h with stroke (#48870)
)

utf8proc_map(s::AbstractString, flags::Integer, chartransform::F = identity) where F = utf8proc_map(String(s), flags, chartransform)

# Documented in Unicode module
function normalize(
    s::AbstractString;
    stable::Bool=false,
    compat::Bool=false,
    compose::Bool=true,
    decompose::Bool=false,
    stripignore::Bool=false,
    rejectna::Bool=false,
    newline2ls::Bool=false,
    newline2ps::Bool=false,
    newline2lf::Bool=false,
    stripcc::Bool=false,
    casefold::Bool=false,
    lump::Bool=false,
    stripmark::Bool=false,
    chartransform=identity,
)
    flags = 0
    stable && (flags = flags | UTF8PROC_STABLE)
    compat && (flags = flags | UTF8PROC_COMPAT)
    # TODO: error if compose & decompose?
    if decompose
        flags = flags | UTF8PROC_DECOMPOSE
    elseif compose
        flags = flags | UTF8PROC_COMPOSE
    elseif compat || stripmark
        throw(ArgumentError("compat=true or stripmark=true require compose=true or decompose=true"))
    end
    stripignore && (flags = flags | UTF8PROC_IGNORE)
    rejectna && (flags = flags | UTF8PROC_REJECTNA)
    newline2ls + newline2ps + newline2lf > 1 && throw(ArgumentError("only one newline conversion may be specified"))
    newline2ls && (flags = flags | UTF8PROC_NLF2LS)
    newline2ps && (flags = flags | UTF8PROC_NLF2PS)
    newline2lf && (flags = flags | UTF8PROC_NLF2LF)
    stripcc && (flags = flags | UTF8PROC_STRIPCC)
    casefold && (flags = flags | UTF8PROC_CASEFOLD)
    lump && (flags = flags | UTF8PROC_LUMP)
    stripmark && (flags = flags | UTF8PROC_STRIPMARK)
    utf8proc_map(s, flags, chartransform)
end

function normalize(s::AbstractString, nf::Symbol)
    utf8proc_map(s, nf === :NFC ? (UTF8PROC_STABLE | UTF8PROC_COMPOSE) :
                    nf === :NFD ? (UTF8PROC_STABLE | UTF8PROC_DECOMPOSE) :
                    nf === :NFKC ? (UTF8PROC_STABLE | UTF8PROC_COMPOSE
                                   | UTF8PROC_COMPAT) :
                    nf === :NFKD ? (UTF8PROC_STABLE | UTF8PROC_DECOMPOSE
                                   | UTF8PROC_COMPAT) :
                    throw(ArgumentError(":$nf is not one of :NFC, :NFD, :NFKC, :NFKD")))
end

############################################################################

## character column width function ##
"""
    textwidth(c)

Give the number of columns needed to print a character.

# Examples
```jldoctest
julia> textwidth('α')
1

julia> textwidth('⛵')
2
```
"""
textwidth(c::AbstractChar) = textwidth(Char(c)::Char)

function textwidth(c::Char)
    u = reinterpret(UInt32, c)
    b = bswap(u) # from isascii(c)
    b < 0x7f && return Int(b >= 0x20) # ASCII fast path
    # We can't know a priori how terminals will render invalid UTF8 chars,
    # so we conservatively decide a width of 1.
    (ismalformed(c) || is_overlong_enc(u)) && return 1
    Int(ccall(:utf8proc_charwidth, Cint, (UInt32,), c))
end

"""
    textwidth(s::AbstractString)

Give the number of columns needed to print a string.

# Examples
```jldoctest
julia> textwidth("March")
5
```
"""
textwidth(s::AbstractString) = mapreduce(textwidth, +, s; init=0)

textwidth(s::AnnotatedString) = textwidth(s.string)

"""
    lowercase(c::AbstractChar)

Convert `c` to lowercase.

See also [`uppercase`](@ref), [`titlecase`](@ref).

# Examples
```jldoctest
julia> lowercase('A')
'a': ASCII/Unicode U+0061 (category Ll: Letter, lowercase)

julia> lowercase('Ö')
'ö': Unicode U+00F6 (category Ll: Letter, lowercase)
```
"""
lowercase(c::T) where {T<:AbstractChar} = isascii(c) ? ('A' <= c <= 'Z' ? c + 0x20 : c) :
    T(ccall(:utf8proc_tolower, UInt32, (UInt32,), c))

lowercase(c::AnnotatedChar) = AnnotatedChar(lowercase(c.char), annotations(c))

"""
    uppercase(c::AbstractChar)

Convert `c` to uppercase.

See also [`lowercase`](@ref), [`titlecase`](@ref).

# Examples
```jldoctest
julia> uppercase('a')
'A': ASCII/Unicode U+0041 (category Lu: Letter, uppercase)

julia> uppercase('ê')
'Ê': Unicode U+00CA (category Lu: Letter, uppercase)
```
"""
uppercase(c::T) where {T<:AbstractChar} = isascii(c) ? ('a' <= c <= 'z' ? c - 0x20 : c) :
    T(ccall(:utf8proc_toupper, UInt32, (UInt32,), c))

uppercase(c::AnnotatedChar) = AnnotatedChar(uppercase(c.char), annotations(c))

"""
    titlecase(c::AbstractChar)

Convert `c` to titlecase. This may differ from uppercase for digraphs,
compare the example below.

See also [`uppercase`](@ref), [`lowercase`](@ref).

# Examples
```jldoctest
julia> titlecase('a')
'A': ASCII/Unicode U+0041 (category Lu: Letter, uppercase)

julia> titlecase('ǆ')
'ǅ': Unicode U+01C5 (category Lt: Letter, titlecase)

julia> uppercase('ǆ')
'Ǆ': Unicode U+01C4 (category Lu: Letter, uppercase)
```
"""
titlecase(c::T) where {T<:AbstractChar} = isascii(c) ? ('a' <= c <= 'z' ? c - 0x20 : c) :
    T(ccall(:utf8proc_totitle, UInt32, (UInt32,), c))

titlecase(c::AnnotatedChar) = AnnotatedChar(titlecase(c.char), annotations(c))

############################################################################

# returns UTF8PROC_CATEGORY code in 0:30 giving Unicode category
function category_code(c::AbstractChar)
    !ismalformed(c) ? category_code(UInt32(c)) : Cint(31)
end

function category_code(x::Integer)
    x ≤ 0x10ffff ? (@assume_effects :foldable @ccall utf8proc_category(UInt32(x)::UInt32)::Cint) : Cint(30)
end

# more human-readable representations of the category code
function category_abbrev(c::AbstractChar)
    ismalformed(c) && return "Ma"
    c ≤ '\U10ffff' || return "In"
    unsafe_string(ccall(:utf8proc_category_string, Cstring, (UInt32,), c))
end

category_string(c) = category_strings[category_code(c)+1]

isassigned(c) = UTF8PROC_CATEGORY_CN < category_code(c) <= UTF8PROC_CATEGORY_CO

## libc character class predicates ##

"""
    islowercase(c::AbstractChar)::Bool

Tests whether a character is a lowercase letter (according to the Unicode
standard's `Lowercase` derived property).

See also [`isuppercase`](@ref).

# Examples
```jldoctest
julia> islowercase('α')
true

julia> islowercase('Γ')
false

julia> islowercase('❤')
false
```
"""
islowercase(c::AbstractChar) = ismalformed(c) ? false :
    Bool(@assume_effects :foldable @ccall utf8proc_islower(UInt32(c)::UInt32)::Cint)

# true for Unicode upper and mixed case

"""
    isuppercase(c::AbstractChar)::Bool

Tests whether a character is an uppercase letter (according to the Unicode
standard's `Uppercase` derived property).

See also [`islowercase`](@ref).

# Examples
```jldoctest
julia> isuppercase('γ')
false

julia> isuppercase('Γ')
true

julia> isuppercase('❤')
false
```
"""
isuppercase(c::AbstractChar) = ismalformed(c) ? false :
    Bool(@assume_effects :foldable @ccall utf8proc_isupper(UInt32(c)::UInt32)::Cint)

"""
    iscased(c::AbstractChar)::Bool

Tests whether a character is cased, i.e. is lower-, upper- or title-cased.

See also [`islowercase`](@ref), [`isuppercase`](@ref).
"""
function iscased(c::AbstractChar)
    cat = category_code(c)
    return cat == UTF8PROC_CATEGORY_LU ||
           cat == UTF8PROC_CATEGORY_LT ||
           cat == UTF8PROC_CATEGORY_LL
end


"""
    isdigit(c::AbstractChar)::Bool

Tests whether a character is an ASCII decimal digit (`0`-`9`).

See also: [`isletter`](@ref).

# Examples
```jldoctest
julia> isdigit('❤')
false

julia> isdigit('9')
true

julia> isdigit('α')
false
```
"""
isdigit(c::AbstractChar) = (c >= '0') & (c <= '9')

"""
    isletter(c::AbstractChar)::Bool

Test whether a character is a letter.
A character is classified as a letter if it belongs to the Unicode general
category Letter, i.e. a character whose category code begins with 'L'.

See also: [`isdigit`](@ref).

# Examples
```jldoctest
julia> isletter('❤')
false

julia> isletter('α')
true

julia> isletter('9')
false
```
"""
isletter(c::AbstractChar) = UTF8PROC_CATEGORY_LU <= category_code(c) <= UTF8PROC_CATEGORY_LO

"""
    isnumeric(c::AbstractChar)::Bool

Tests whether a character is numeric.
A character is classified as numeric if it belongs to the Unicode general category Number,
i.e. a character whose category code begins with 'N'.

Note that this broad category includes characters such as ¾ and ௰.
Use [`isdigit`](@ref) to check whether a character is a decimal digit between 0 and 9.

# Examples
```jldoctest
julia> isnumeric('௰')
true

julia> isnumeric('9')
true

julia> isnumeric('α')
false

julia> isnumeric('❤')
false
```
"""
isnumeric(c::AbstractChar) = UTF8PROC_CATEGORY_ND <= category_code(c) <= UTF8PROC_CATEGORY_NO

# following C++ only control characters from the Latin-1 subset return true

"""
    iscntrl(c::AbstractChar)::Bool

Tests whether a character is a control character.
Control characters are the non-printing characters of the Latin-1 subset of Unicode.

# Examples
```jldoctest
julia> iscntrl('\\x01')
true

julia> iscntrl('a')
false
```
"""
iscntrl(c::AbstractChar) = c <= '\x1f' || '\x7f' <= c <= '\u9f'

"""
    ispunct(c::AbstractChar)::Bool

Tests whether a character belongs to the Unicode general category Punctuation, i.e. a
character whose category code begins with 'P'.

!!! note
    This behavior is different from the `ispunct` function in C.

# Examples
```jldoctest
julia> ispunct('α')
false

julia> ispunct('=')
false

julia> ispunct('/')
true

julia> ispunct(';')
true
```
"""
ispunct(c::AbstractChar) = UTF8PROC_CATEGORY_PC <= category_code(c) <= UTF8PROC_CATEGORY_PO

# \u85 is the Unicode Next Line (NEL) character

"""
    isspace(c::AbstractChar)::Bool

Tests whether a character is any whitespace character. Includes ASCII characters '\\t',
'\\n', '\\v', '\\f', '\\r', and ' ', Latin-1 character U+0085, and characters in Unicode
category Zs.

# Examples
```jldoctest
julia> isspace('\\n')
true

julia> isspace('\\r')
true

julia> isspace(' ')
true

julia> isspace('\\x20')
true
```
"""
@inline isspace(c::AbstractChar) =
    c == ' ' || '\t' <= c <= '\r' || c == '\u85' ||
    '\ua0' <= c && category_code(c) == UTF8PROC_CATEGORY_ZS

"""
    isprint(c::AbstractChar)::Bool

Tests whether a character is printable, including spaces, but not a control character.

# Examples
```jldoctest
julia> isprint('\\x01')
false

julia> isprint('A')
true
```
"""
isprint(c::AbstractChar) = UTF8PROC_CATEGORY_LU <= category_code(c) <= UTF8PROC_CATEGORY_ZS

# true in principal if a printer would use ink

"""
    isxdigit(c::AbstractChar)::Bool

Test whether a character is a valid hexadecimal digit. Note that this does not
include `x` (as in the standard `0x` prefix).

# Examples
```jldoctest
julia> isxdigit('a')
true

julia> isxdigit('x')
false
```
"""
isxdigit(c::AbstractChar) = '0'<=c<='9' || 'a'<=c<='f' || 'A'<=c<='F'

## uppercase, lowercase, and titlecase transformations ##

"""
    uppercase(s::AbstractString)

Return `s` with all characters converted to uppercase.

See also [`lowercase`](@ref), [`titlecase`](@ref), [`uppercasefirst`](@ref).

# Examples
```jldoctest
julia> uppercase("Julia")
"JULIA"
```
"""
uppercase(s::AbstractString) = map(uppercase, s)
uppercase(s::AnnotatedString) = annotated_chartransform(uppercase, s)

"""
    lowercase(s::AbstractString)

Return `s` with all characters converted to lowercase.

See also [`uppercase`](@ref), [`titlecase`](@ref), [`lowercasefirst`](@ref).

# Examples
```jldoctest
julia> lowercase("STRINGS AND THINGS")
"strings and things"
```
"""
lowercase(s::AbstractString) = map(lowercase, s)
lowercase(s::AnnotatedString) = annotated_chartransform(lowercase, s)

"""
    titlecase(s::AbstractString; [wordsep::Function], strict::Bool=true)::String

Capitalize the first character of each word in `s`;
if `strict` is true, every other character is
converted to lowercase, otherwise they are left unchanged.
By default, all non-letters beginning a new grapheme are considered as word separators;
a predicate can be passed as the `wordsep` keyword to determine
which characters should be considered as word separators.
See also [`uppercasefirst`](@ref) to capitalize only the first
character in `s`.

See also [`uppercase`](@ref), [`lowercase`](@ref), [`uppercasefirst`](@ref).

# Examples
```jldoctest
julia> titlecase("the JULIA programming language")
"The Julia Programming Language"

julia> titlecase("ISS - international space station", strict=false)
"ISS - International Space Station"

julia> titlecase("a-a b-b", wordsep = c->c==' ')
"A-a B-b"
```
"""
function titlecase(s::AbstractString; wordsep::Function = !isletter, strict::Bool=true)
    startword = true
    state = Ref{Int32}(0)
    c0 = eltype(s)(0x00000000)
    b = IOBuffer()
    for c in s
        # Note: It would be better to have a word iterator following UAX#29,
        # similar to our grapheme iterator, but utf8proc does not yet have
        # this information.  At the very least we shouldn't break inside graphemes.
        if isgraphemebreak!(state, c0, c) && wordsep(c)
            print(b, c)
            startword = true
        else
            print(b, startword ? titlecase(c) : strict ? lowercase(c) : c)
            startword = false
        end
        c0 = c
    end
    return takestring!(b)
end

# TODO: improve performance characteristics, room for a ~10x improvement.
function titlecase(s::AnnotatedString; wordsep::Function = !isletter, strict::Bool=true)
    initial_state = (; startword = true, state = Ref{Int32}(0),
             c0 = eltype(s)(zero(UInt32)), wordsep, strict)
    annotated_chartransform(s, initial_state) do c, state
        if isgraphemebreak!(state.state, state.c0, c) && state.wordsep(c)
            state = Base.setindex(state, true, :startword)
            cnew = c
        else
            cnew = state.startword ? titlecase(c) : state.strict ? lowercase(c) : c
            state = Base.setindex(state, false, :startword)
        end
        state = Base.setindex(state, c, :c0)
        cnew, state
    end
end

"""
    uppercasefirst(s::AbstractString)::String

Return `s` with the first character converted to uppercase (technically "title
case" for Unicode). See also [`titlecase`](@ref) to capitalize the first
character of every word in `s`.

See also [`lowercasefirst`](@ref), [`uppercase`](@ref), [`lowercase`](@ref),
[`titlecase`](@ref).

# Examples
```jldoctest
julia> uppercasefirst("python")
"Python"
```
"""
function uppercasefirst(s::AbstractString)
    isempty(s) && return ""
    c = s[1]
    c′ = titlecase(c)
    c == c′ ? convert(String, s) :
    string(c′, SubString(s, nextind(s, 1)))
end

# TODO: improve performance characteristics, room for a ~5x improvement.
function uppercasefirst(s::AnnotatedString)
    annotated_chartransform(s, true) do c, state
        if state
            (titlecase(c), false)
        else
            (c, state)
        end
    end
end

"""
    lowercasefirst(s::AbstractString)

Return `s` with the first character converted to lowercase.

See also [`uppercasefirst`](@ref), [`uppercase`](@ref), [`lowercase`](@ref),
[`titlecase`](@ref).

# Examples
```jldoctest
julia> lowercasefirst("Julia")
"julia"
```
"""
function lowercasefirst(s::AbstractString)
    isempty(s) && return ""
    c = s[1]
    c′ = lowercase(c)
    c == c′ ? convert(String, s) :
    string(c′, SubString(s, nextind(s, 1)))
end

# TODO: improve performance characteristics, room for a ~5x improvement.
function lowercasefirst(s::AnnotatedString)
    annotated_chartransform(s, true) do c, state
        if state
            (lowercase(c), false)
        else
            (c, state)
        end
    end
end

############################################################################
# iterators for grapheme segmentation

isgraphemebreak(c1::AbstractChar, c2::AbstractChar) =
    ismalformed(c1) || ismalformed(c2) ||
    ccall(:utf8proc_grapheme_break, Bool, (UInt32, UInt32), c1, c2)

# Stateful grapheme break required by Unicode-9 rules: the string
# must be processed in sequence, with state initialized to Ref{Int32}(0).
# Requires utf8proc v2.0 or later.
@inline function isgraphemebreak!(state::Ref{Int32}, c1::AbstractChar, c2::AbstractChar)
    if ismalformed(c1) || ismalformed(c2)
        state[] = 0
        return true
    end
    ccall(:utf8proc_grapheme_break_stateful, Bool,
          (UInt32, UInt32, Ref{Int32}), c1, c2, state)
end

struct GraphemeIterator{S<:AbstractString}
    s::S # original string (for generation of SubStrings)
end

# Documented in Unicode module
graphemes(s::AbstractString) = GraphemeIterator{typeof(s)}(s)

eltype(::Type{GraphemeIterator{S}}) where {S} = SubString{S}
eltype(::Type{GraphemeIterator{SubString{S}}}) where {S} = SubString{S}

function length(g::GraphemeIterator{S}) where {S}
    c0 = eltype(S)(0x00000000)
    n = 0
    state = Ref{Int32}(0)
    for c in g.s
        n += isgraphemebreak!(state, c0, c)
        c0 = c
    end
    return n
end

function iterate(g::GraphemeIterator, i_=(Int32(0),firstindex(g.s)))
    s = g.s
    statei, i = i_
    state = Ref{Int32}(statei)
    j = i
    y = iterate(s, i)
    y === nothing && return nothing
    c0, k = y
    while k <= ncodeunits(s) # loop until next grapheme is s[i:j]
        c, ℓ = iterate(s, k)::NTuple{2,Any}
        isgraphemebreak!(state, c0, c) && break
        j = k
        k = ℓ
        c0 = c
    end
    return (SubString(s, i, j), (state[], k))
end

==(g1::GraphemeIterator, g2::GraphemeIterator) = g1.s == g2.s
hash(g::GraphemeIterator, h::UInt) = hash(g.s, h)
isless(g1::GraphemeIterator, g2::GraphemeIterator) = isless(g1.s, g2.s)

show(io::IO, g::GraphemeIterator{S}) where {S} = print(io, "length-$(length(g)) GraphemeIterator{$S} for \"$(g.s)\"")

############################################################################

end # module
