## How LoRA works

LoRA freezes the pretrained weights $W_0 \in \mathbb{R}^{d \times k}$ and learns a **low-rank** update, so the adapted layer computes

$$
h = W_0 x + \Delta W x = W_0 x + B A x
$$

where $B \in \mathbb{R}^{d \times r}$, $A \in \mathbb{R}^{r \times k}$ and $r \ll \min(d, k)$ (Section 4.1).

### Key results

1. **Parameters**: 10,000× fewer trainable parameters than full fine-tuning on GPT-3 175B.
2. *Memory*: GPU memory drops by about 3×.
   - No extra inference latency, since $BA$ merges into $W_0$.
   - Works on `W_q` and `W_v` alone.
3. Quality matches or beats fine-tuning on RoBERTa, DeBERTa, GPT-2 and GPT-3.

| Method | Trainable params | WikiSQL | MNLI-m |
|:--|--:|--:|--:|
| Fine-tune | 175B | 73.8 | 89.5 |
| LoRA | 4.7M | **73.4** | **91.7** |

```python
h = x @ W0.T + (x @ A.T) @ B.T * (alpha / r)
```

> The rank $r$ can be as small as 1 or 2 (Section 7.2).

See [the paper](https://arxiv.org/abs/2106.09685) or the follow-up [QLoRA](https://arxiv.org/abs/2305.14314).