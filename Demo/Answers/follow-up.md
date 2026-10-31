I searched arXiv for work that builds on this paper. Here are the most relevant follow-ups, grouped by what they change.

## Making it cheaper

- **[QLoRA][qlora]** (Dettmers et al., 2023) quantises the frozen base model to 4 bits and trains LoRA adapters on top, so a 65B model fine-tunes on one 48 GB GPU.
- **[DoRA][dora]** (Liu et al., 2024) splits each weight into a magnitude and a direction and applies LoRA to the direction only, which closes much of the gap to full fine-tuning.
- **[LoRA+][loraplus]** (Hayou et al., 2024) gives the two adapter matrices different learning rates, a one-line change that speeds training up.

## Choosing the rank

- **[AdaLoRA][adalora]** (Zhang et al., 2023) prunes and reallocates rank across layers during training, spending the budget where it helps most.
- *Intrinsic dimensionality* work by [Aghajanyan et al.][intrinsic] is the theory LoRA's low-rank assumption leans on.

## Worth reading first

1. QLoRA, if you want to try fine-tuning on your own hardware.
2. DoRA, if you care about matching full fine-tuning quality.
3. AdaLoRA, if you are tuning ranks by hand today.

Want me to open any of these in the reader?

[qlora]: https://arxiv.org/abs/2305.14314
[dora]: https://arxiv.org/abs/2402.09353
[loraplus]: https://arxiv.org/abs/2402.12354
[adalora]: https://arxiv.org/abs/2303.10512
[intrinsic]: https://arxiv.org/abs/2012.13255
