# StreamMarkdown

A native Swift renderer for Markdown that arrives a few tokens at a time, as an LLM answer does. It parses with Apple's [swift-markdown](https://github.com/swiftlang/swift-markdown) (cmark-gfm) and draws each root block in its own TextKit 2 view, so only the block being written re-renders.

It draws the answers in Duoxiv's Ask overlay.

What it does:

- streaming parse off the main thread, one view per root block, finished blocks never rebuilt;
- prose: headings, emphasis, strikethrough, monospaced inline code, links through `openURL`, nested and task lists, quotes, rules, Dynamic Type, selection within one block at a time, heading levels for VoiceOver;
- math: `$…$`, `$$…$$`, `\(…\)` and `\[…\]` drawn by [SwiftMath](https://github.com/mgriebling/SwiftMath), skipping code, HTML, link destinations and escaped `\$`, with `$5 and $10` left as currency. Inline formulas sit on the text's baseline in its colour; a display formula is its own block, centred, scrolling sideways when wider than the column, and inside a list or quote it takes a line of its own that scrolls the same way. VoiceOver reads each formula's TeX, and a formula SwiftMath cannot draw shows its source;
- code blocks: a header with the language and a copy button, long lines that scroll sideways, and syntax highlighting computed in the parse job once a block is closed (plain while it is still arriving), also inside list items and quotes;
- tables: a grid in a horizontal scroll, header on one line, each column's alignment, cells built like prose (inline code, emphasis, links, inline math), long body cells wrapping at a column width, links opened by a tap (cell text is not selectable);
- streaming polish: syntax still being written at the end of the answer is closed early (`**bold`, `` `code``) or held back (`[text](ht`, a half-written table row, a closing fence being typed, an unclosed formula), text is released at a steady pace instead of in the lumps it arrives in, new words fade in over 300 ms and new blocks over 150 ms; under Reduce Motion text shows as it arrives, without fades;
- a demo app that replays recorded answers and measures frame rate and main-thread time.

Known limits:

- an unclosed `$$` or `\[` holds back the rest of the answer until it closes or the stream ends;
- an unclosed single `~` shows as typed;
- table cells cannot be selected (links in them open on tap);
- a fade already running when Reduce Motion turns on finishes its 300 ms.

## Install

Add the package and depend on its `StreamMarkdown` product. Releases are tagged on `main`, and before 1.0 a minor version may change the API, so pin one exactly:

```swift
.package(url: "https://github.com/celve/StreamMarkdown", exact: "0.1.0"),
```

## Use

```swift
import StreamMarkdown

StreamMarkdownView(answer, isStreaming: isResponding)
    .streamMarkdownStyle(style)                 // optional; StreamMarkdownStyle() is the default
    .environment(\.openURL, OpenURLAction { url in … })
```

Pass the whole answer so far each time it grows, and set `isStreaming` to false when it ends: the rest then shows at once and is parsed as written. The view needs iOS 27.1; the parser and builder also build on macOS 27, where the tests run. Its reveal asks for up to 120 Hz, which an iPhone grants only to an app whose Info.plist sets `CADisableMinimumFrameDurationOnPhone`.

`StreamMarkdownStyle` holds the tokens: fonts by role as Dynamic Type text styles (a serif body and SF headings by default, as in Duoxiv's reader), spacing in ems of the body font, and colours.

## How it works

- `Parse/BlockParser.swift` parses the whole answer with swift-markdown and cuts it into root blocks, each with its index, kind and UTF-8 source range. A block's key is its kind and everything its rendering reads from the parse (`RenderInputs`), resolved link targets included, so a definition that arrives after its use redraws the block that uses it and nothing else.
- `Stream/MarkdownStream.swift` is the coordinator. It runs one parse at a time on a background task, and a text that arrives meanwhile waits, so only the latest is parsed next. A block whose key is unchanged keeps the content it was built with, and the views skip it. Each root block has a `BlockSlot` that the view observes on its own, so an update redraws the block being written and SwiftUI does not walk the others; the slot list changes only when a block is added or removed.
- `Stream/RevealPacer.swift` releases a streaming answer on a 50 ms tick driven by a display link (`Views/FrameClock.swift`, up to 120 Hz): at a rate that would clear the backlog in about a third of a second, rising at once with a burst and easing off by a tenth a tick. Text present when the view appears, and the rest when the stream ends, shows at once.
- `Parse/TailRepair.swift` runs in the parse job while the answer streams. It reads the deepest last block cmark parsed and the last line, on the text with formulas already taken out, and either cuts the text where unfinished syntax starts or appends closers for emphasis and code that can draw as they grow. A reference link whose definition has not arrived yet gets a pending one, drawn in the link colour. The finished answer is parsed as written.
- `Math/MathExtractor.swift` takes the formulas out before the block parse, so cmark never reads TeX as Markdown (`$$\n- x^2\n$$` would be a list). A first cmark parse of the answer says where math cannot be (code, HTML, images, link destinations, link reference definitions); a scan finds the formulas elsewhere, inline dollars by Pandoc's rule; each becomes one private-use placeholder, and a display formula in a root paragraph gets blank lines around it, so it is a block of its own. Block ranges are mapped back to the answer. `MathExtractor.unfinishedMath(in:)` tells the streaming tail whether it ends inside a formula.
- `Math/MathRenderer.swift` typesets with SwiftMath off the main thread into template images, cached by TeX, size and style. A formula SwiftMath rejects is retried with the commands LLMs write that it lacks rewritten (`\dfrac`, `\operatorname`, `align`, `\tag`, `\big`, …), then shown as its source. `MathAttachment` puts an inline formula on the baseline and shrinks it to the line when wider; a display formula inside prose gets a sideways-scrolling view as wide as its line. Text views read each formula's TeX to VoiceOver in place of the attachment character.
- `Render/BlockContent.swift` is the seam for later pieces: `BlockRenderer` turns a parsed block into a `BlockContent` (prose text, a quote of child blocks, a rule, a code block, a table, a list cut around the code blocks and tables in its items, display math, or monospaced source for HTML), and each case has a view in `BlockContentView`. A field a renderer starts reading goes into `RenderInputs` too, or a block that changes only there is not redrawn; a formula is written there as its source, never its placeholder. `RenderContext` says whether a block is the open tail of a streaming answer; a code block's highlighted-or-plain decision depends on it and is written into `RenderInputs`.
- `Render/CodeHighlighter.swift` is a table-driven lexer of our own (keywords, strings, comments, numbers, types, calls, decorators, variables; line modes for diffs and markup) for about 30 languages and their aliases. A language it does not know stays plain. Highlightr (highlight.js in JavaScriptCore) was measured against it: 180–233 ms to start, 17.5 MB, and 3.6 ms for a 15-line block on the build Mac.
- `Render/CodeBuilder.swift` and `Render/TableBuilder.swift` build a code block's text and a table's cells inside the parse job. A streaming table keeps the text of every cell whose inputs are unchanged, so only changed cells' text views update.
- `Render/ProseBuilder.swift` is a `MarkupWalker` that builds a paragraph, heading or whole list into one `NSAttributedString`, with list markers right-aligned on a tab before the text. It runs inside the parse job, off the main thread.
- `Views/ProseTextView.swift` draws a block in a non-scrolling TextKit 2 `UITextView`, sized with `sizeThatFits`, with links sent to SwiftUI's `openURL`. A new string that begins as the shown one did replaces only what follows their common start in the text storage. New characters fade in under a layer mask whose part over each new range Core Animation ramps from transparent, so a fade runs no frames on the main thread; UITextView does not redraw text when TextKit 2 rendering attributes change, and redrawing it by hand every frame cost about 50 ms/s of main thread on the 10k stream. `Views/CodeBlockView.swift` puts a code block's text view in a horizontal `ScrollView` under its header; `Views/TableBlockView.swift` draws a table's grid as one UIKit view of cell labels, in a horizontal `ScrollView`, so a layout pass over the answer asks each table for one cached size; labels because a text view per cell cost the stream about 25 ms/s of main thread, so cell text is not selectable, and a tap on a cell link goes to `openURL`.

## Demo and measurement

`scripts/demo.sh [bundle id]` generates `Demo/StreamMarkdownDemo.xcodeproj` with [XcodeGen](https://github.com/yonaskolb/XcodeGen) from `Demo/project.yml` and builds the app for the simulator. The app lists answers from `Demo/Answers` and replays one at a chosen rate: 20, 60 or 120 tokens a second, 480 characters a second, or all at once. A meter shows frames, main-thread time and the renderer's parse and build counts. Launch arguments: `-answer <id>` opens an answer, `-rate <tokens per second>` sets the rate (0 for all at once), `-hud 0` hides the meter, and `-scrollY <points>` scrolls the answer to that offset, for screenshots where a drag cannot reach, such as the unfolded Duo's inner display.

`scripts/perf.sh <issue> [runs] [launch arguments]` runs the measurement from Duoxiv's renderer study ([renderer-performance.md](https://github.com/softlash/LIN-2404/blob/main/docs/renderer-performance.md)) on the shared iPhone Duo simulator. It streams the 10k-character answer at 24 characters every 50 ms, scrolls it down over 8 s and up over 4 s, and prints `PERF` lines: frame rate, hitches, main-thread busy time, its stretches over 8.3 and 16.7 ms, memory, and the renderer's own main-thread and parse timings. `-render 0` runs the same harness with the renderer removed, to measure the floor. The demo asks for 120 Hz (`CADisableMinimumFrameDurationOnPhone`), but the simulator runs at 60, so frame rates above that need a device.

`scripts/ui-check.sh <issue> <shots dir>` runs the demo's UI tests on the shared Duo in light and dark appearance (links reach `openURL`, headings carry the header trait, one block holds a selection, formulas read as their TeX, a wide formula scrolls inside the column, Copy reaches the pasteboard, code and tables scroll sideways by touch drag while a vertical drag on them scrolls the answer, table headers stay on one line) and saves screenshots. `ONLY=<class>[/<test>]` runs a subset.

## Tests

`swift test` runs the parser, math, coordinator and builder tests on the Mac, including the math cases from Duoxiv's previous renderer (LIN-2404).

## License

MIT, see [LICENSE](LICENSE).
