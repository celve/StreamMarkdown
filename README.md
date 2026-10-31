# StreamMarkdown

A native Swift renderer for Markdown that arrives a few tokens at a time, as an LLM answer does. It parses with Apple's [swift-markdown](https://github.com/swiftlang/swift-markdown) (cmark-gfm) and draws each root block in its own TextKit 2 view, so only the block being written re-renders.

It is being built for the Ask overlay in Duoxiv, where it replaces MarkdownView. Planned:

- prose: headings, emphasis, strikethrough, monospaced inline code, links, nested and task lists, quotes, rules, Dynamic Type;
- math: `$…$`, `$$…$$`, `\(…\)` and `\[…\]` through SwiftMath;
- code blocks with highlighting and a copy button, and tables, each in a horizontal scroll;
- streaming polish: unfinished syntax hidden at the tail, a paced reveal, and words fading in, all off under Reduce Motion.

Nothing is released yet.

## License

MIT, see [LICENSE](LICENSE).
