enum Samples {
    /// A typical Ask answer, tight lists only, so a cut at any blank line ends a block.
    static let answer = """
    ## What the paper does

    LoRA freezes the pretrained weights and learns a **low-rank** update, so the adapted layer adds `B A x` to its output. \
    It trains *far fewer* parameters than full fine-tuning.

    ### Key results

    1. **Parameters**: 10,000× fewer trainable parameters on GPT-3 175B.
    2. *Memory*: GPU memory drops by about 3×.
       - No extra inference latency, since `BA` merges into the weights.
       - Works on `W_q` and `W_v` alone.
    3. Quality matches or beats fine-tuning.

    > The rank can be as small as 1 or 2.

    - [x] Read the method
    - [ ] Check the ablations

    ---

    See [the paper](https://arxiv.org/abs/2106.09685) or ~~the blog~~ the follow-up [QLoRA](https://arxiv.org/abs/2305.14314).
    """
}
