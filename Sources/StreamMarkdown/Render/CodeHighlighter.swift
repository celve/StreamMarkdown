import Foundation

/// What a span of code is, for colouring.
enum CodeTokenKind: Sendable, Hashable, CaseIterable {
    case keyword, string, comment, number, type, function, attribute, variable, property, inserted, deleted
}

struct CodeToken: Sendable, Hashable {
    let kind: CodeTokenKind
    /// UTF-16 offsets, as `NSAttributedString` counts.
    let range: NSRange
}

/// A lexical highlighter: keywords, strings, comments, numbers, types and calls by each language's rules, with no grammar.
/// Pure and fast enough to run on every parse of a block.
enum CodeHighlighter {
    /// The code's tokens, or nil for a language it does not know.
    static func tokens(_ code: String, language: String?) -> [CodeToken]? {
        guard let language = language.flatMap(CodeLanguage.named) else { return nil }
        var lexer = Lexer(Array(code.utf16), language)
        lexer.run()
        return lexer.tokens
    }

    static func knows(_ language: String?) -> Bool {
        language.flatMap(CodeLanguage.named) != nil
    }
}

/// How one language's source reads, as far as a lexer cares.
struct CodeLanguage: Sendable {
    enum Mode: Sendable { case code, diff, markup }

    var mode = Mode.code
    var lineComments: [String] = []
    var blockComments: [(open: String, close: String)] = []
    /// Delimiters that open and close a string, longest first; a delimiter of three characters may span lines.
    var strings = ["\"", "'"]
    /// Letters that may prefix a string, as Python's `r` and `f` do; raw prefixes turn escapes off.
    var stringPrefixes: Set<UInt16> = []
    var rawPrefixes: Set<UInt16> = []
    var keywords: Set<String> = []
    /// Built-in type names coloured as types.
    var types: Set<String> = []
    /// Capitalised identifiers are types, as in Swift or Java.
    var capitalisedTypes = false
    var caseInsensitive = false
    /// The keywords whose next identifier is a declared function or type.
    var declaresFunction: Set<String> = []
    var declaresType: Set<String> = []
    /// `@name` (decorators, annotations) or `#name` (preprocessor, Swift directives) as attributes.
    var attributePrefixes: Set<UInt16> = []
    /// `$name` as a variable.
    var variables = false
    /// Characters that continue an identifier besides letters, digits and `_`.
    var identifierExtras: Set<UInt16> = []
    /// `'a` is a lifetime, not a string, unless it closes right after.
    var lifetimes = false
    /// The marks after which a string or a line's first word is a key: `:` in JSON and YAML, `=` too in INI.
    var keys: Set<UInt16> = []
    /// `#` starts a comment only at a line's start or after a space, as in shell.
    var hashCommentsNeedSpace = false

    static func named(_ name: String) -> CodeLanguage? {
        let name = name.lowercased()
        return aliases[name].flatMap { all[$0] }
    }

    private static let aliases: [String: String] = {
        let table: [String: [String]] = [
            "python": ["python", "py", "python3", "py3", "ipython", "pycon", "gyp", "sage"],
            "swift": ["swift"],
            "javascript": ["javascript", "js", "jsx", "mjs", "cjs", "node", "typescript", "ts", "tsx", "mts", "cts"],
            "c": ["c", "h", "cpp", "c++", "cc", "cxx", "hpp", "hxx", "hh", "h++", "cuda", "cu", "cuh", "objc", "objective-c", "objectivec", "obj-c", "m", "mm", "metal", "glsl", "hlsl", "arduino", "ino"],
            "java": ["java"],
            "kotlin": ["kotlin", "kt", "kts"],
            "csharp": ["csharp", "cs", "c#", "fsharp", "fs"],
            "go": ["go", "golang"],
            "rust": ["rust", "rs"],
            "ruby": ["ruby", "rb", "gemspec", "podspec", "rake"],
            "php": ["php"],
            "shell": ["bash", "sh", "shell", "zsh", "console", "shellsession", "terminal", "fish", "ksh", "powershell", "ps1", "ps", "pwsh", "cmd", "bat"],
            "json": ["json", "jsonc", "json5", "jsonl", "geojson", "ipynb"],
            "yaml": ["yaml", "yml"],
            "ini": ["toml", "ini", "cfg", "conf", "properties", "editorconfig", "dotenv", "env"],
            "sql": ["sql", "postgresql", "postgres", "psql", "mysql", "sqlite", "plsql", "tsql", "sparql"],
            "markup": ["html", "xml", "svg", "xhtml", "plist", "vue", "svelte", "xaml", "xsl", "rss", "atom"],
            "css": ["css", "scss", "sass", "less"],
            "latex": ["latex", "tex", "bibtex", "bib"],
            "diff": ["diff", "patch", "udiff"],
            "r": ["r", "rscript"],
            "julia": ["julia", "jl"],
            "matlab": ["matlab", "octave"],
            "scala": ["scala", "sc"],
            "lua": ["lua"],
            "haskell": ["haskell", "hs"],
            "dart": ["dart"],
            "dockerfile": ["dockerfile", "docker", "containerfile"],
            "makefile": ["makefile", "make", "mk", "cmake"],
        ]
        var aliases: [String: String] = [:]
        for (language, names) in table { for name in names { aliases[name] = language } }
        return aliases
    }()

    private static func words(_ text: String) -> Set<String> { Set(text.split(separator: " ").map(String.init)) }
    private static func chars(_ text: String) -> Set<UInt16> { Set(text.utf16) }

    private static let cTypes = words("void bool char short int long float double signed unsigned size_t ssize_t int8_t int16_t int32_t int64_t uint8_t uint16_t uint32_t uint64_t wchar_t auto half dim3 BOOL id instancetype")

    private static let all: [String: CodeLanguage] = {
        var all: [String: CodeLanguage] = [:]
        all["python"] = CodeLanguage(
            lineComments: ["#"], strings: ["\"\"\"", "'''", "\"", "'"], stringPrefixes: chars("rRbBfFuU"), rawPrefixes: chars("rR"),
            keywords: words("and as assert async await break class continue def del elif else except finally for from global if import in is lambda nonlocal not or pass raise return try while with yield match case None True False self cls"),
            types: words("int float str bool list dict set tuple bytes object type complex frozenset range"),
            capitalisedTypes: true, declaresFunction: ["def"], declaresType: ["class"], attributePrefixes: chars("@"))
        all["swift"] = CodeLanguage(
            lineComments: ["//"], blockComments: [("/*", "*/")], strings: ["\"\"\"", "\""],
            keywords: words("actor any associatedtype async await break case catch class continue default defer deinit do else enum extension fallthrough false fileprivate final for func guard if import in indirect init inout internal is lazy let mutating nil nonisolated open operator override private protocol public repeat rethrows return self Self some static struct subscript super switch throw throws true try typealias var weak where while consuming borrowing sending"),
            capitalisedTypes: true, declaresFunction: ["func"], declaresType: words("class struct enum protocol actor extension typealias"), attributePrefixes: chars("@#"))
        all["javascript"] = CodeLanguage(
            lineComments: ["//"], blockComments: [("/*", "*/")], strings: ["\"", "'", "`"],
            keywords: words("abstract as async await break case catch class const constructor continue debugger declare default delete do else enum export extends false finally for from function get if implements import in instanceof interface keyof let namespace new null of private protected public readonly return set static super switch this throw true try type typeof undefined var void while with yield satisfies"),
            types: words("string number boolean any unknown never object symbol bigint"),
            capitalisedTypes: true, declaresFunction: ["function"], declaresType: words("class interface type enum"), attributePrefixes: chars("@"), identifierExtras: chars("$"))
        all["c"] = CodeLanguage(
            lineComments: ["//"], blockComments: [("/*", "*/")],
            keywords: words("alignas alignof asm break case catch class const consteval constexpr const_cast continue co_await co_return co_yield decltype default delete do dynamic_cast else enum explicit export extern false for friend goto if inline mutable namespace new noexcept nullptr operator private protected public register reinterpret_cast return sizeof static static_assert static_cast struct switch template this throw true try typedef typeid typename union using virtual volatile while __global__ __device__ __host__ __shared__ __syncthreads YES NO nil self super @interface @implementation @end @property @protocol @selector @autoreleasepool kernel device constant thread threadgroup"),
            types: cTypes, capitalisedTypes: false, declaresType: words("class struct enum union"), attributePrefixes: chars("#@"))
        all["java"] = CodeLanguage(
            lineComments: ["//"], blockComments: [("/*", "*/")], strings: ["\"\"\"", "\"", "'"],
            keywords: words("abstract assert break case catch class const continue default do else enum extends false final finally for goto if implements import instanceof interface native new null package permits private protected public record return sealed static strictfp super switch synchronized this throw throws transient true try var void volatile while yield"),
            types: words("boolean byte char double float int long short"), capitalisedTypes: true,
            declaresType: words("class interface enum record"), attributePrefixes: chars("@"))
        all["kotlin"] = CodeLanguage(
            lineComments: ["//"], blockComments: [("/*", "*/")], strings: ["\"\"\"", "\"", "'"],
            keywords: words("abstract annotation as break by catch class companion const constructor continue data do else enum false final finally for fun get if import in init inline interface internal is lateinit null object open operator out override package private protected public reified return sealed set super suspend this throw true try typealias val var vararg when where while"),
            capitalisedTypes: true, declaresFunction: ["fun"], declaresType: words("class interface object typealias"), attributePrefixes: chars("@"))
        all["csharp"] = CodeLanguage(
            lineComments: ["//"], blockComments: [("/*", "*/")], strings: ["\"\"\"", "\"", "'"], stringPrefixes: chars("@$"), rawPrefixes: chars("@"),
            keywords: words("abstract as async await base break case catch checked class const continue default delegate do else enum event explicit extern false finally fixed for foreach goto if implicit in interface internal is let lock namespace new null object operator out override params private protected public readonly record ref return sealed sizeof static struct switch this throw true try typeof unchecked unsafe using var virtual void volatile when where while yield"),
            types: words("bool byte char decimal double float int long sbyte short string uint ulong ushort"), capitalisedTypes: true,
            declaresType: words("class interface struct enum record"), attributePrefixes: chars("#"))
        all["go"] = CodeLanguage(
            lineComments: ["//"], blockComments: [("/*", "*/")], strings: ["\"", "'", "`"],
            keywords: words("break case chan const continue default defer else fallthrough false for func go goto if import interface iota map nil package range return select struct switch true type var"),
            types: words("bool byte complex64 complex128 error float32 float64 int int8 int16 int32 int64 rune string uint uint8 uint16 uint32 uint64 uintptr any"),
            declaresFunction: ["func"], declaresType: ["type"])
        all["rust"] = CodeLanguage(
            lineComments: ["//"], blockComments: [("/*", "*/")], strings: ["\"", "'"], stringPrefixes: chars("rbc"), rawPrefixes: chars("r"),
            keywords: words("as async await break const continue crate dyn else enum extern false fn for if impl in let loop match mod move mut pub ref return self Self static struct super trait true type unsafe use where while"),
            types: words("bool char f32 f64 i8 i16 i32 i64 i128 isize str u8 u16 u32 u64 u128 usize"), capitalisedTypes: true,
            declaresFunction: ["fn"], declaresType: words("struct enum trait type impl"), attributePrefixes: chars("#"), lifetimes: true)
        all["ruby"] = CodeLanguage(
            lineComments: ["#"], strings: ["\"", "'"],
            keywords: words("alias and begin break case class def defined? do else elsif end ensure false for if in module next nil not or redo rescue retry return self super then true undef unless until when while yield require attr_accessor attr_reader puts"),
            capitalisedTypes: true, declaresFunction: ["def"], declaresType: words("class module"), attributePrefixes: chars("@:"), identifierExtras: chars("?!"))
        all["php"] = CodeLanguage(
            lineComments: ["//", "#"], blockComments: [("/*", "*/")],
            keywords: words("abstract and array as break case catch class clone const continue declare default do echo else elseif empty enum extends false final finally fn for foreach function global if implements include instanceof interface isset list match namespace new null or print private protected public readonly require return static switch this throw trait true try unset use var while yield"),
            capitalisedTypes: true, declaresFunction: ["function"], declaresType: words("class interface trait enum"), variables: true)
        all["shell"] = CodeLanguage(
            lineComments: ["#"], strings: ["\"", "'"],
            keywords: words("if then else elif fi for while until do done case esac in function return export local readonly unset source alias exit set shift break continue eval exec trap declare"),
            variables: true, identifierExtras: chars("-"), hashCommentsNeedSpace: true)
        all["json"] = CodeLanguage(strings: ["\""], keywords: words("true false null"), keys: chars(":"))
        all["yaml"] = CodeLanguage(
            lineComments: ["#"], keywords: words("true false null yes no on off True False Null ~"), identifierExtras: chars("-."), keys: chars(":"), hashCommentsNeedSpace: true)
        all["ini"] = CodeLanguage(lineComments: ["#", ";"], strings: ["\"\"\"", "'''", "\"", "'"], keywords: words("true false"), identifierExtras: chars("-."), keys: chars(":="))
        all["sql"] = CodeLanguage(
            lineComments: ["--"], blockComments: [("/*", "*/")], strings: ["'", "\""],
            keywords: words("add all alter and any as asc between by case cast check column constraint create cross database default delete desc distinct drop else end exists false foreign from full group having if in index inner insert into is join key left like limit not null offset on or order outer over partition primary references returning right select set table then true union unique update using values view when where with"),
            types: words("int integer bigint smallint serial text varchar char boolean bool date timestamp timestamptz float real double numeric decimal json jsonb uuid blob"),
            caseInsensitive: true)
        all["markup"] = CodeLanguage(mode: .markup, blockComments: [("<!--", "-->")], identifierExtras: chars("-:."))
        all["css"] = CodeLanguage(
            blockComments: [("/*", "*/")], keywords: words("important inherit initial unset none auto"),
            attributePrefixes: chars("@"), variables: true, identifierExtras: chars("-"), keys: chars(":"))
        all["latex"] = CodeLanguage(lineComments: ["%"], strings: [], attributePrefixes: chars("\\"))
        all["diff"] = CodeLanguage(mode: .diff)
        all["r"] = CodeLanguage(
            lineComments: ["#"],
            keywords: words("if else repeat while function for in next break TRUE FALSE NULL Inf NaN NA library return"),
            identifierExtras: chars("."))
        all["julia"] = CodeLanguage(
            lineComments: ["#"], blockComments: [("#=", "=#")], strings: ["\"\"\"", "\"", "'"],
            keywords: words("abstract baremodule begin break catch const continue do else elseif end export false finally for function global if import in let local macro module mutable quote return struct true try using where while nothing"),
            capitalisedTypes: true, declaresFunction: ["function"], declaresType: ["struct"], attributePrefixes: chars("@"))
        all["matlab"] = CodeLanguage(
            lineComments: ["%"], strings: ["\"", "'"],
            keywords: words("break case catch classdef continue else elseif end for function global if otherwise parfor persistent return switch try while true false"),
            declaresFunction: ["function"])
        all["scala"] = CodeLanguage(
            lineComments: ["//"], blockComments: [("/*", "*/")], strings: ["\"\"\"", "\"", "'"],
            keywords: words("abstract case catch class def do else enum extends false final finally for given if implicit import lazy match new null object override package private protected return sealed super then this throw trait true try type using val var while with yield"),
            capitalisedTypes: true, declaresFunction: ["def"], declaresType: words("class object trait enum type"), attributePrefixes: chars("@"))
        all["lua"] = CodeLanguage(
            lineComments: ["--"], blockComments: [("--[[", "]]")],
            keywords: words("and break do else elseif end false for function goto if in local nil not or repeat return then true until while self"),
            declaresFunction: ["function"])
        all["haskell"] = CodeLanguage(
            lineComments: ["--"], blockComments: [("{-", "-}")], strings: ["\""],
            keywords: words("case class data default deriving do else foreign if import in infix infixl infixr instance let module newtype of then type where"),
            capitalisedTypes: true, identifierExtras: chars("'"))
        all["dart"] = CodeLanguage(
            lineComments: ["//"], blockComments: [("/*", "*/")], strings: ["'''", "\"\"\"", "\"", "'"], stringPrefixes: chars("r"), rawPrefixes: chars("r"),
            keywords: words("abstract as assert async await break case catch class const continue default do dynamic else enum export extends extension external factory false final finally for get if implements import in is late library mixin new null on operator part required rethrow return set static super switch sync this throw true try typedef var void while with yield"),
            types: words("int double num bool"), capitalisedTypes: true, declaresType: words("class enum mixin extension"), attributePrefixes: chars("@"))
        all["dockerfile"] = CodeLanguage(
            lineComments: ["#"],
            keywords: words("FROM RUN CMD LABEL EXPOSE ENV ADD COPY ENTRYPOINT VOLUME USER WORKDIR ARG ONBUILD STOPSIGNAL HEALTHCHECK SHELL AS from run cmd label expose env add copy entrypoint volume user workdir arg as"),
            variables: true, hashCommentsNeedSpace: true)
        all["makefile"] = CodeLanguage(
            lineComments: ["#"],
            keywords: words("ifeq ifneq ifdef ifndef else endif include define endef export override .PHONY"),
            variables: true, identifierExtras: chars("-."), hashCommentsNeedSpace: true)
        return all
    }()
}

/// One pass over the code's UTF-16 units.
private struct Lexer {
    private let text: [UInt16]
    private let language: CodeLanguage
    private var index = 0
    private(set) var tokens: [CodeToken] = []
    /// The kind a declaring keyword gives the next identifier.
    private var declares: CodeTokenKind?
    private let keywords: Set<String>

    init(_ text: [UInt16], _ language: CodeLanguage) {
        self.text = text
        self.language = language
        keywords = language.caseInsensitive ? Set(language.keywords.map { $0.lowercased() }) : language.keywords
    }

    mutating func run() {
        switch language.mode {
        case .diff: diff()
        case .markup: markup()
        case .code: while index < text.count { step() }
        }
    }

    // MARK: Code

    private mutating func step() {
        let c = text[index]
        if let comment = commentAt() {
            self.comment(from: index, opener: comment.opener, close: comment.close)
        } else if language.lifetimes, c == quote, let end = lifetimeEnd() {
            add(.attribute, index, end)
            index = end
        } else if let (delimiter, raw) = stringAt() {
            string(delimiter: delimiter, raw: raw)
        } else if isDigit(c) || c == dot && index + 1 < text.count && isDigit(text[index + 1]), !isIdentifierBefore(index) {
            number()
        } else if language.variables, c == dollar {
            variable()
        } else if language.attributePrefixes.contains(c), index + 1 < text.count, isIdentifierStart(text[index + 1]) || c == hash && text[index + 1] == bracket {
            attribute()
        } else if isIdentifierStart(c) {
            identifier()
        } else {
            if !isSpace(c) { declares = nil }
            index += 1
        }
    }

    /// A comment starting here: its opener's length, and the marker that closes it, empty for a line comment.
    private func commentAt() -> (opener: Int, close: String)? {
        for block in language.blockComments where matches(block.open, at: index) { return (block.open.utf16.count, block.close) }
        for line in language.lineComments where matches(line, at: index) {
            if language.hashCommentsNeedSpace, line == "#", index > 0, !isSpace(text[index - 1]) { continue }
            return (line.utf16.count, "")
        }
        return nil
    }

    private mutating func comment(from start: Int, opener: Int, close: String) {
        if close.isEmpty {
            index = lineEnd(from: start)
        } else {
            index = find(close, from: start + opener).map { $0 + close.utf16.count } ?? text.count
        }
        add(.comment, start, index)
    }

    /// A string starting here, after any prefix letters: its delimiter, and whether escapes are off.
    private func stringAt() -> ([UInt16], Bool)? {
        var at = index
        var raw = false
        while at < text.count, at - index < 2, language.stringPrefixes.contains(text[at]) {
            raw = raw || language.rawPrefixes.contains(text[at])
            at += 1
        }
        if language.lifetimes, at > index, text[at - 1] == unit("r"), at < text.count, text[at] == hash { raw = true; at += 1 }
        for delimiter in language.strings where matches(delimiter, at: at) { return (Array(delimiter.utf16), raw) }
        return nil
    }

    private mutating func string(delimiter: [UInt16], raw: Bool) {
        let start = index
        var at = index
        while at < text.count, !matches(delimiter, at: at) { at += 1 }
        at += delimiter.count
        let multiline = delimiter.count == 3 || delimiter == [backtick]
        while at < text.count {
            let c = text[at]
            if !raw, c == backslash { at += 2; continue }
            if matches(delimiter, at: at) { at += delimiter.count; break }
            if c == newline, !multiline { break }
            at += 1
        }
        index = min(at, text.count)
        add(isKeyFollowing(index) ? .property : .string, start, index)
    }

    private mutating func number() {
        let start = index
        index += 1
        while index < text.count {
            let c = text[index]
            if isIdentifierPart(c) || c == dot && index + 1 < text.count && isDigit(text[index + 1]) {
                index += 1
            } else if c == plus || c == minus, text[index - 1] | 0x20 == unit("e"), !isHexNumber(from: start) {
                index += 1
            } else {
                break
            }
        }
        add(.number, start, index)
    }

    private mutating func variable() {
        let start = index
        index += 1
        if index < text.count, text[index] == braceOpen {
            index = (find("}", from: index).map { $0 + 1 }) ?? lineEnd(from: index)
        } else if index < text.count, isIdentifierStart(text[index]) || isDigit(text[index]) {
            while index < text.count, isIdentifierPart(text[index]) { index += 1 }
        } else if index < text.count, "@#?*!$-".utf16.contains(text[index]) {
            index += 1
        } else {
            return
        }
        add(.variable, start, index)
    }

    private mutating func attribute() {
        let start = index
        let prefix = text[index]
        index += 1
        if text[index] == bracket {
            index = find("]", from: index).map { $0 + 1 } ?? lineEnd(from: index)
        } else {
            while index < text.count, isIdentifierPart(text[index]) || text[index] == dot && prefix == atSign { index += 1 }
        }
        add(keywords.contains(word(start, index)) ? .keyword : .attribute, start, index)
    }

    /// The end of a Rust lifetime (`'a`) starting here, or nil for a character literal.
    private func lifetimeEnd() -> Int? {
        var end = index + 1
        guard end < text.count, isIdentifierStart(text[end]) else { return nil }
        while end < text.count, isIdentifierPart(text[end]) { end += 1 }
        return end < text.count && text[end] == quote ? nil : end
    }

    private mutating func identifier() {
        let start = index
        while index < text.count, isIdentifierPart(text[index]) || language.identifierExtras.contains(text[index]) && index > start { index += 1 }
        let word = word(start, index)
        let lookup = language.caseInsensitive ? word.lowercased() : word
        if let declared = declares {
            declares = nil
            if !keywords.contains(lookup) {
                add(declared, start, index)
                return
            }
        }
        if keywords.contains(lookup) {
            add(.keyword, start, index)
            if language.declaresFunction.contains(word) { declares = .function }
            if language.declaresType.contains(word) { declares = .type }
        } else if language.types.contains(lookup) {
            add(.type, start, index)
        } else if isKeyFollowing(index), isLineStart(before: start) {
            add(.property, start, index)
        } else if nextNonSpace(from: index) == parenOpen {
            add(.function, start, index)
        } else if language.capitalisedTypes, let first = word.unicodeScalars.first, CharacterSet.uppercaseLetters.contains(first),
                  word.unicodeScalars.contains(where: CharacterSet.lowercaseLetters.contains) {
            add(.type, start, index)
        }
    }

    // MARK: Diff and markup

    private mutating func diff() {
        while index < text.count {
            let end = lineEnd(from: index)
            let kind: CodeTokenKind? = switch text[index] {
            case plus: matches("+++", at: index) ? .attribute : .inserted
            case minus: matches("---", at: index) ? .attribute : .deleted
            case unit("@"): .comment
            default: matches("diff ", at: index) || matches("index ", at: index) ? .attribute : nil
            }
            if let kind, end > index { add(kind, index, end) }
            index = end + 1
        }
    }

    private mutating func markup() {
        while index < text.count {
            if matches("<!--", at: index) {
                comment(from: index, opener: 4, close: "-->")
            } else if text[index] == angleOpen, index + 1 < text.count, isIdentifierStart(text[index + 1]) || "/!?".utf16.contains(text[index + 1]) {
                tag()
            } else if text[index] == ampersand, let end = find(";", from: index), end - index < 10 {
                add(.attribute, index, end + 1)
                index = end + 1
            } else {
                index += 1
            }
        }
    }

    private mutating func tag() {
        let start = index
        index += 1
        while index < text.count, "/!?".utf16.contains(text[index]) { index += 1 }
        while index < text.count, isIdentifierPart(text[index]) || language.identifierExtras.contains(text[index]) { index += 1 }
        add(.keyword, start, index)
        while index < text.count, text[index] != angleClose {
            let c = text[index]
            if c == quote || c == doubleQuote {
                let open = index
                index = (find(String(decoding: [c], as: UTF16.self), from: index + 1).map { $0 + 1 }) ?? text.count
                add(.string, open, index)
            } else if isIdentifierStart(c) {
                let name = index
                while index < text.count, isIdentifierPart(text[index]) || language.identifierExtras.contains(text[index]) { index += 1 }
                add(.property, name, index)
            } else {
                index += 1
            }
        }
        if index < text.count {
            if index > 0, text[index - 1] == slash || text[index - 1] == unit("?") { add(.keyword, index - 1, index + 1) } else { add(.keyword, index, index + 1) }
            index += 1
        }
    }

    // MARK: Helpers

    private mutating func add(_ kind: CodeTokenKind, _ start: Int, _ end: Int) {
        guard end > start else { return }
        tokens.append(CodeToken(kind: kind, range: NSRange(location: start, length: end - start)))
    }

    private func matches(_ string: String, at offset: Int) -> Bool { matches(Array(string.utf16), at: offset) }

    private func matches(_ units: [UInt16], at offset: Int) -> Bool {
        guard !units.isEmpty, offset + units.count <= text.count else { return false }
        for (i, unit) in units.enumerated() where text[offset + i] != unit { return false }
        return true
    }

    private func find(_ string: String, from offset: Int) -> Int? {
        let units = Array(string.utf16)
        var at = offset
        while at + units.count <= text.count {
            if matches(units, at: at) { return at }
            at += 1
        }
        return nil
    }

    private func lineEnd(from offset: Int) -> Int {
        var at = offset
        while at < text.count, text[at] != newline { at += 1 }
        return at
    }

    private func nextNonSpace(from offset: Int) -> UInt16? {
        var at = offset
        while at < text.count, text[at] == space || text[at] == tab { at += 1 }
        return at < text.count ? text[at] : nil
    }

    private func isKeyFollowing(_ offset: Int) -> Bool {
        nextNonSpace(from: offset).map(language.keys.contains) ?? false
    }

    /// Whether only spaces, list dashes or an opening brace stand between the line's start and `offset`.
    private func isLineStart(before offset: Int) -> Bool {
        var at = offset - 1
        while at >= 0, text[at] != newline {
            if !(isSpace(text[at]) || text[at] == minus || text[at] == braceOpen || text[at] == comma) { return false }
            at -= 1
        }
        return true
    }

    private func isHexNumber(from start: Int) -> Bool {
        start + 1 < text.count && text[start] == unit("0") && (text[start + 1] | 0x20) == unit("x")
    }

    private func isIdentifierBefore(_ offset: Int) -> Bool { offset > 0 && isIdentifierPart(text[offset - 1]) }

    private func word(_ start: Int, _ end: Int) -> String { String(decoding: text[start..<end], as: UTF16.self) }

    private func isDigit(_ c: UInt16) -> Bool { c >= 48 && c <= 57 }
    private func isSpace(_ c: UInt16) -> Bool { c == space || c == tab || c == newline || c == 13 }
    private func isIdentifierStart(_ c: UInt16) -> Bool {
        (c | 0x20) >= 97 && (c | 0x20) <= 122 || c == underscore || c > 127 && !isSpace(c) || language.identifierExtras.contains(c) && c == dollar
    }
    private func isIdentifierPart(_ c: UInt16) -> Bool { isIdentifierStart(c) || isDigit(c) }
}

private let newline = unit("\n"), space = unit(" "), tab = unit("\t")
private let quote = unit("'"), doubleQuote = unit("\""), backtick = unit("`"), backslash = unit("\\")
private let dot = unit("."), comma = unit(",")
private let plus = unit("+"), minus = unit("-"), slash = unit("/"), ampersand = unit("&")
private let dollar = unit("$"), hash = unit("#"), underscore = unit("_"), atSign = unit("@")
private let parenOpen = unit("("), bracket = unit("["), braceOpen = unit("{")
private let angleOpen = unit("<"), angleClose = unit(">")

private func unit(_ scalar: Unicode.Scalar) -> UInt16 { UInt16(scalar.value) }
