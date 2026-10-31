## How attention is computed

Each token's query $q_i \in \mathbb{R}^{d_k}$ is compared with every key $k_j$, and the scores weight the values:

$$
\operatorname{Attention}(Q, K, V) = \operatorname{softmax}\left(\frac{QK^\top}{\sqrt{d_k}}\right) V
$$

The scaling by \(\sqrt{d_k}\) keeps the dot products from growing with the dimension: if the entries of $q$ and $k$ are independent with mean $0$ and variance $1$, then $q \cdot k = \sum_{i=1}^{d_k} q_i k_i$ has variance $d_k$.

### Multi-head attention

The model runs $h$ heads in parallel, each with its own projections:

\[
\begin{aligned}
\mathrm{head}_i &= \operatorname{Attention}(Q W_i^Q, K W_i^K, V W_i^V) \\
\operatorname{MultiHead}(Q, K, V) &= \operatorname{Concat}(\mathrm{head}_1, \ldots, \mathrm{head}_h) W^O
\end{aligned}
\]

1. **Projections:** $W_i^Q, W_i^K \in \mathbb{R}^{d_{\text{model}} \times d_k}$ and $W^O \in \mathbb{R}^{h d_v \times d_{\text{model}}}$.
2. **Cost:** with $d_k = d_v = d_{\text{model}} / h$, all heads together cost about as much as one head at full width.
   - Self-attention is $O(n^2 \cdot d)$ per layer, against $O(n \cdot d^2)$ for a recurrent layer.
   - The masked decoder sets scores to $-\infty$ where $j > i$:

     $$
     M_{ij} = \begin{cases} 0 & j \le i \\ -\infty & j > i \end{cases}
     $$
3. **Positions:** sinusoidal encodings, $PE_{(pos, 2i)} = \sin\left(pos / 10000^{2i / d_{\text{model}}}\right)$.

### The training objective

The loss over a batch of $N$ sequences is the mean token-level cross-entropy, written out in full here so it is wider than the screen:

$$
\mathcal{L}(\theta) = -\frac{1}{N} \sum_{n=1}^{N} \frac{1}{T_n} \sum_{t=1}^{T_n} \log p_\theta\left(y^{(n)}_t \mid y^{(n)}_{<t}, x^{(n)}\right) + \lambda \lVert \theta \rVert_2^2
$$

> With label smoothing $\epsilon_{ls} = 0.1$ the target puts $1 - \epsilon_{ls}$ on the true token and spreads $\epsilon_{ls}$ over the rest of the vocabulary.

A rotation by $\theta$ acts on each pair of query dimensions as
$$\begin{pmatrix} \cos\theta & -\sin\theta \\ \sin\theta & \cos\theta \end{pmatrix}$$
which is how RoPE encodes relative position.

Training the base model took 12 hours on 8 P100 GPUs; at about $1.50 an hour per GPU, that is roughly $150 of compute.
