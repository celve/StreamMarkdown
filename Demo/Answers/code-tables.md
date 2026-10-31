# Code and tables

A code block gets a header with its language and a copy button, and its long lines scroll sideways instead of wrapping.

```python
import torch
from torch import nn

@torch.no_grad()
def merge(layer):
    layer.base.weight += layer.B @ layer.A * layer.scale  # fold the update into W0 before serving

class LoRALinear(nn.Module):
    """A frozen linear layer plus a trainable low-rank update B @ A, scaled by alpha / r as in Section 4.1 of the paper; only A and B ever receive gradients."""
    def __init__(self, base: nn.Linear, r: int = 8, alpha: float = 16.0):
        super().__init__()
        self.base = base.requires_grad_(False)
        self.A = nn.Parameter(torch.randn(r, base.in_features) * 0.01)
        self.B = nn.Parameter(torch.zeros(base.out_features, r))
        self.scale = alpha / r

    def forward(self, x: torch.Tensor) -> torch.Tensor:
        return self.base(x) + (x @ self.A.T) @ self.B.T * self.scale
```

Fine-tuning from the shell:

```bash
export HF_HOME="$HOME/.cache/hf"  # model cache
python train.py --model meta-llama/Llama-3.1-8B --lora-r 16 --lora-alpha 32 --target-modules q_proj,v_proj --epochs 3
```

A table keeps its header on one line, follows each column's alignment, and scrolls when it is wider than the screen:

| Method | Trainable parameters | GPU memory | Extra inference latency | WikiSQL | MNLI-m | SAMSum R1 / R2 / RL | Paper |
|:--|--:|--:|:--|:-:|:-:|:-:|:--|
| Full fine-tuning | 175,255.8M | 1.2 TB | none | 73.8 | 89.5 | 52.0 / 28.0 / 44.5 | [GPT-3](https://arxiv.org/abs/2005.14165) |
| Adapter | 40.1M | 350 GB | up to 30% at batch size 1 | 73.2 | 91.5 | 53.2 / 29.0 / 45.1 | [Houlsby et al.](https://arxiv.org/abs/1902.00751) |
| Prefix tuning | 20.2M | 350 GB | longer sequences | 63.1 | 88.6 | 48.3 / 24.2 / 40.5 | — |
| **LoRA** | **4.7M** | **350 GB** | **none once merged** | **73.4** | **91.7** | **53.8 / 29.8 / 45.9** | [Hu et al.](https://arxiv.org/abs/2106.09685) |

Long cells wrap at the column's width instead of stretching the table:

| Choice | Why it matters |
|---|---|
| Rank `r` | Small ranks (1 to 8) already match full fine-tuning on most GLUE tasks, because the update has a low intrinsic rank. |
| Which matrices | Adapting *both* `W_q` and `W_v` beats putting the same budget into `W_q` alone. |
| ~~Dropout~~ | Barely matters at these ranks. |

Steps in a list keep their code blocks:

1. Install the libraries:

   ```sh
   pip install peft transformers accelerate
   ```
2. Wrap the model and train only the adapters:

   ```swift
   let config = LoraConfig(rank: 16, alpha: 32, targets: ["q_proj", "v_proj"])
   let model = try await Model.load("llama-3.1-8b").adapted(with: config)
   print("trainable: \(model.trainableParameters.formatted())")
   ```
3. Merge the adapter back before serving, so inference costs nothing extra.

A diff, a JSON config and a block with no language:

```diff
--- a/config.yaml
+++ b/config.yaml
@@ -1,3 +1,3 @@
-lora_r: 8
+lora_r: 16
 lora_alpha: 32
```

```json
{"r": 16, "lora_alpha": 32, "target_modules": ["q_proj", "v_proj"], "bias": "none", "task_type": "CAUSAL_LM", "lora_dropout": 0.05}
```

```
epoch 1/3   loss 1.842   lr 2.0e-4   ████████░░░░░░░░  48%   eta 00:12:31
```
