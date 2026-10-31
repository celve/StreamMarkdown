## Summary

**Attention Is All You Need** introduces the *Transformer*, a sequence model built entirely from attention. It drops the recurrence and convolutions that earlier translation models relied on, so every position in a sentence can attend to every other in one step, and training parallelises across the whole sequence.

### How it works

1. **Self-attention.** Each token builds a query, a key and a value. The output for a token is a weighted sum of all values, with weights from how well its query matches each key, scaled by the square root of the key dimension.
2. **Multi-head attention.** Eight heads run attention in parallel on different learned projections, so the model can track several kinds of relation at once, such as syntax in one head and coreference in another.
3. **Positional encoding.** Because attention ignores order, sine and cosine signals of different frequencies are added to the embeddings.
4. **Encoder–decoder stack.** Six layers on each side, each with attention, a feed-forward network, residual connections and layer normalisation.

### Results

- **WMT 2014 English–German:** 28.4 BLEU, more than 2 BLEU above the best previous models, ensembles included.
- **WMT 2014 English–French:** 41.8 BLEU for a single model, after 3.5 days on eight GPUs.
- **Training cost:** a fraction of what the earlier state of the art needed.

### Limitations

- Attention is quadratic in sequence length, which the authors note as a problem for very long inputs.
- The fixed positional encodings were a choice among several; the paper reports that learned ones did about as well.

> The paper's main claim is that attention alone, without recurrence, is enough for state-of-the-art translation, and that it trains much faster.

If you want to go deeper, Section 3.2 explains scaled dot-product attention, and Table 3 compares the model variants.
