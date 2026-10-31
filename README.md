# StreamMarkdown

A native Swift renderer for Markdown that arrives a few tokens at a time, as an LLM answer does. It parses with Apple's [swift-markdown](https://github.com/swiftlang/swift-markdown) (cmark-gfm) and draws each root block in its own TextKit 2 view, so only the block being written re-renders.

It is being built for the Ask overlay in Duoxiv, where it replaces MarkdownView.

Done:

- streaming parse off the main thread, one view per root block, finished blocks never rebuilt;
- prose: headings, emphasis, strikethrough, monospaced inline code, links through `openURL`, nested and task lists, quotes, rules, Dynamic Type, selection within one block at a time, heading levels for VoiceOver;
- a demo app that replays recorded answers and measures frame rate and main-thread time.

Planned:

- math: `$…$`, `$$…$$`, `\(…\)` and `\[…\]` through SwiftMath;
- code blocks with highlighting and a copy button, and tables, each in a horizontal scroll (until then both show as monospaced source, and math shows as Markdown reads it);
- streaming polish: unfinished syntax hidden at the tail, a paced reveal, and words fading in, all off under Reduce Motion.

Nothing is released yet.

## Use

```swift
import StreamMarkdown

StreamMarkdownView(answer, isStreaming: isResponding)
    .streamMarkdownStyle(style)                 // optional; StreamMarkdownStyle() is the default
    .environment(\.openURL, OpenURLAction { url in … })
```

Pass the whole answer so far each time it grows. The view needs iOS 27.1; the parser and builder also build on macOS 27, where the tests run.

`StreamMarkdownStyle` holds the tokens: fonts by role as Dynamic Type text styles (a serif body and SF headings by default, as in Duoxiv's reader), spacing in ems of the body font, and colours.

## How it works

- `Parse/BlockParser.swift` parses the whole answer with swift-markdown and cuts it into root blocks, each with its index, kind and UTF-8 source range. A block's key is its kind and everything its rendering reads from the parse (`RenderInputs`), resolved link targets included, so a definition that arrives after its use redraws the block that uses it and nothing else.
- `Stream/MarkdownStream.swift` is the coordinator. It runs one parse at a time on a background task, and a text that arrives meanwhile waits, so only the latest is parsed next. A block whose key is unchanged keeps the content it was built with, and the views skip it.
- `Render/BlockContent.swift` is the seam for later pieces: `BlockRenderer` turns a parsed block into a `BlockContent` (prose text, a quote of child blocks, a rule, or monospaced source). Code blocks and tables replace the `.source` fallback by adding a case there and a view in `Views/StreamMarkdownView.swift`; math adds its extraction and its own content. A field a renderer starts reading goes into `RenderInputs` too, or a block that changes only there is not redrawn.
- `Render/ProseBuilder.swift` is a `MarkupWalker` that builds a paragraph, heading or whole list into one `NSAttributedString`, with list markers right-aligned on a tab before the text. It runs inside the parse job, off the main thread.
- `Views/ProseTextView.swift` draws a block in a non-scrolling TextKit 2 `UITextView`, sized with `sizeThatFits`, with links sent to SwiftUI's `openURL`.

## Demo and measurement

`scripts/demo.sh [bundle id]` generates `Demo/StreamMarkdownDemo.xcodeproj` with [XcodeGen](https://github.com/yonaskolb/XcodeGen) from `Demo/project.yml` and builds the app for the simulator. The app lists answers from `Demo/Answers` and replays one at a chosen rate: 20, 60 or 120 tokens a second, 480 characters a second, or all at once. A meter shows frames, main-thread time and the renderer's parse and build counts. Launch arguments: `-answer <id>` opens an answer, `-rate <tokens per second>` sets the rate (0 for all at once), and `-hud 0` hides the meter.

`scripts/perf.sh <issue> [runs] [launch arguments]` runs the measurement from Duoxiv's renderer study ([renderer-performance.md](https://github.com/softlash/LIN-2404/blob/main/docs/renderer-performance.md)) on the shared iPhone Duo simulator. It streams the 10k-character answer at 24 characters every 50 ms, scrolls it down over 8 s and up over 4 s, and prints `PERF` lines: frame rate, hitches, main-thread busy time, its stretches over 8.3 and 16.7 ms, memory, and the renderer's own main-thread and parse timings. `-render 0` runs the same harness with the renderer removed, to measure the floor. The demo asks for 120 Hz (`CADisableMinimumFrameDurationOnPhone`), but the simulator runs at 60, so frame rates above that need a device.

`scripts/ui-check.sh <issue> <shots dir>` runs the demo's UI tests on the shared Duo in light and dark appearance (links reach `openURL`, headings carry the header trait, one block holds a selection) and saves screenshots.

## Tests

`swift test` runs the parser, coordinator and builder tests on the Mac.

## License

MIT, see [LICENSE](LICENSE).
