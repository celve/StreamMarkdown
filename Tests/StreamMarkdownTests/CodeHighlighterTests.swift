import Foundation
@testable import StreamMarkdown
import Testing

struct CodeHighlighterTests {
    @Test func pythonKeywordsStringsCommentsNumbersAndNames() throws {
        let code = """
        @dataclass
        class LoRA(nn.Module):
            def forward(self, x):  # the low-rank path
                return x @ self.A.T * 0.5 + f"r={self.r}"
        """
        let kinds = try tokens(code, "python")
        #expect(kinds["@dataclass"] == .attribute)
        #expect(kinds["class"] == .keyword)
        #expect(kinds["LoRA"] == .type)
        #expect(kinds["def"] == .keyword)
        #expect(kinds["forward"] == .function)
        #expect(kinds["self"] == .keyword)
        #expect(kinds["# the low-rank path"] == .comment)
        #expect(kinds["return"] == .keyword)
        #expect(kinds["0.5"] == .number)
        #expect(kinds["f\"r={self.r}\""] == .string)
        #expect(kinds["x"] == nil)
    }

    @Test func triplesSpanLinesAndUnclosedStringsStopAtTheLineEnd() throws {
        let kinds = try tokens("s = \"\"\"one\ntwo\"\"\"\nt = 'open\nu = 1", "py")
        #expect(kinds["\"\"\"one\ntwo\"\"\""] == .string)
        #expect(kinds["'open"] == .string)
        #expect(kinds["1"] == .number)
    }

    @Test func languagesAreFoundByTheirAliasesInAnyCase() {
        for name in ["Python", "py", "C++", "cuda", "TS", "tsx", "sh", "zsh", "console", "yml", "golang", "rs", "objc", "Dockerfile"] {
            #expect(CodeHighlighter.knows(name), "\(name)")
        }
        #expect(!CodeHighlighter.knows("text"))
        #expect(!CodeHighlighter.knows(nil))
        #expect(CodeHighlighter.tokens("print(1)", language: "plaintext") == nil)
    }

    @Test func shellVariablesAndCommentsAfterSpaceOnly() throws {
        let kinds = try tokens("export PATH=\"$HOME/bin:$PATH\" # set\necho a#b ${USER}", "bash")
        #expect(kinds["export"] == .keyword)
        #expect(kinds["\"$HOME/bin:$PATH\""] == .string)
        #expect(kinds["# set"] == .comment)
        #expect(kinds["${USER}"] == .variable)
        #expect(kinds["#b ${USER}"] == nil, "a # inside a word is not a comment")
    }

    @Test func jsonAndYAMLKeysAreNotValues() throws {
        let json = try tokens("{\"rank\": 8, \"name\": \"lora\", \"bias\": false}", "json")
        #expect(json["\"rank\""] == .property)
        #expect(json["\"lora\""] == .string)
        #expect(json["8"] == .number)
        #expect(json["false"] == .keyword)
        let yaml = try tokens("model:\n  - rank: 8 # small\n  name: lora", "yaml")
        #expect(yaml["model"] == .property)
        #expect(yaml["rank"] == .property)
        #expect(yaml["# small"] == .comment)
        #expect(yaml["lora"] == nil)
    }

    @Test func diffLinesAreInsertedOrDeleted() throws {
        let kinds = try tokens("--- a/x.py\n+++ b/x.py\n@@ -1 +1 @@\n-old\n+new\n same", "diff")
        #expect(kinds["--- a/x.py"] == .attribute)
        #expect(kinds["+++ b/x.py"] == .attribute)
        #expect(kinds["@@ -1 +1 @@"] == .comment)
        #expect(kinds["-old"] == .deleted)
        #expect(kinds["+new"] == .inserted)
        #expect(kinds[" same"] == nil)
    }

    @Test func rustLifetimesAreNotCharacters() throws {
        let kinds = try tokens("fn first<'a>(s: &'a str) -> char { 'x' }", "rust")
        #expect(kinds["fn"] == .keyword)
        #expect(kinds["first"] == .function)
        #expect(kinds["'a"] == .attribute)
        #expect(kinds["str"] == .type)
        #expect(kinds["'x'"] == .string)
    }

    @Test func markupTagsAttributesAndValues() throws {
        let kinds = try tokens("<!-- note -->\n<a href=\"/x\">link</a>", "html")
        #expect(kinds["<!-- note -->"] == .comment)
        #expect(kinds["<a"] == .keyword)
        #expect(kinds["href"] == .property)
        #expect(kinds["\"/x\""] == .string)
        #expect(kinds["link"] == nil)
        #expect(kinds["</a"] == .keyword)
    }

    @Test func sqlKeywordsInAnyCase() throws {
        let kinds = try tokens("SELECT name FROM papers where rank > 3 -- top", "sql")
        #expect(kinds["SELECT"] == .keyword)
        #expect(kinds["where"] == .keyword)
        #expect(kinds["-- top"] == .comment)
    }

    @Test func cFamilyPreprocessorTypesAndBlockComments() throws {
        let kinds = try tokens("#include <cuda.h>\n/* kernel */\n__global__ void add(int n) { return; }", "cu")
        #expect(kinds["#include"] == .attribute)
        #expect(kinds["/* kernel */"] == .comment)
        #expect(kinds["__global__"] == .keyword)
        #expect(kinds["void"] == .type)
        #expect(kinds["add"] == .function)
    }

    /// Every language over text that ends mid-token: tokens stay inside the text and never overlap.
    @Test func cutOffCodeNeverEscapesItsText() {
        let ends = ["\"", "'", "`", "\"\"\"", "/*", "<!--", "$", "${", "@", "#", "#[", "<", "&", "\\", "0x", "1e", "r#\"", "'a", "--[["]
        for language in ["python", "swift", "js", "cpp", "java", "kotlin", "cs", "go", "rust", "ruby", "php", "bash", "json", "yaml", "toml", "sql", "html", "css", "latex", "diff", "r", "julia", "matlab", "scala", "lua", "haskell", "dart", "dockerfile", "makefile"] {
            for end in ends {
                let code = "x = 1\n" + end
                let length = (code as NSString).length
                let tokens = CodeHighlighter.tokens(code, language: language) ?? []
                var last = 0
                for token in tokens {
                    #expect(token.range.location >= last && NSMaxRange(token.range) <= length, "\(language) \(end.debugDescription): \(token)")
                    last = NSMaxRange(token.range)
                }
            }
        }
    }

    /// Each token's text and kind; a text that appears twice keeps its first kind.
    private func tokens(_ code: String, _ language: String) throws -> [String: CodeTokenKind] {
        let tokens = try #require(CodeHighlighter.tokens(code, language: language))
        var kinds: [String: CodeTokenKind] = [:]
        for token in tokens {
            let text = (code as NSString).substring(with: token.range)
            if kinds[text] == nil { kinds[text] = token.kind }
        }
        return kinds
    }
}
