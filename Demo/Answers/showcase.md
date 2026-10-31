# Every prose block

This answer exercises each block the core renders. Body text is *emphasised*, **strong**, ***both***, ~~struck through~~, and `inline code` sits in a monospaced face. A [link](https://arxiv.org/abs/2106.09685) goes through the host's `openURL`, as does a [reference link][lora] whose definition comes at the end, and an autolink: <https://huggingface.co/papers>.

A soft break
joins these lines with a space, while a hard break  
starts a new line in the same paragraph.

## Lists

- A bulleted item
- Another, with a nested list:
  - second level
    - third level, which wraps onto a second line to show the hanging indent under its marker
  - back to the second level
- Last top-level item

7. An ordered list starting at seven
8. keeps counting
9. past nine
10. into two digits, with the markers right-aligned

A list that follows another of the same kind continues it, so this paragraph separates the next one.

1. A loose list item with two paragraphs.

   Its second paragraph sits at the item's text indent.
2. The next item

### Tasks

- [x] Read the abstract
- [x] Skim the method
- [ ] Check the ablations
- [ ] Try the code

## Quotes

> A block quote is a bar beside its own blocks.
>
> - It can hold a list
> - with **strong** text
>
> > and a nested quote.

#### A fourth-level heading

---

Text after a thematic break. 中文段落也应当正确换行，不会溢出到屏幕之外。Arabic and Hebrew stay in their own direction: مرحبا بالعالم.

[lora]: https://arxiv.org/abs/2106.09685 "LoRA: Low-Rank Adaptation"
