## Display math after inline code

Use `$$` for display math:

$$
- x^2
$$

## Bracket display math

\[
- x^2
\]

## Blank lines and environments

$$
\begin{aligned}
x &= 1

\\ y &= 2
\end{aligned}
$$

## Currency and escapes

Prices: $5 and $10, between $5-$10, or US$20. An escaped \$x\$ stays text, and so does `$y$` in code.

```python
cost = "$5"  # $$ not math $$
```

## What SwiftMath cannot draw

Inline, an unknown command shows its source: $\mathscr{L} \circledast x$.

$$
\begin{array}{cc} a & b \\ c & d \end{array}
$$

Commands it lacks are rewritten: $\dfrac{a}{b}$, $\operatorname*{arg\,max}_x f(x)$, $\lVert x \rVert$, $a \implies b$.

## Math in other blocks

### The bound $O(n \log n)$

> Quoted: $e^{i\pi} + 1 = 0$, and
>
> $$
> \int_0^\infty e^{-x^2} \, dx = \frac{\sqrt{\pi}}{2}
> $$

- [x] A task with $x^2$
- A wide formula inside a list item scrolls sideways:

  $$
  \mathcal{L}_{\text{total}} = \mathcal{L}_{\text{CE}} + \lambda_1 \lVert \theta \rVert_2^2 + \lambda_2 \sum_{l=1}^{L} \lVert W_l \rVert_F^2 + \lambda_3 \sum_{i=1}^{n} \mathrm{KL}\left(p_i \,\|\, q_i\right)
  $$
- [See $\alpha$](https://en.wikipedia.org/wiki/Alpha) links still open.

| Symbol | Meaning |
|---|---|
| $\alpha$ | learning rate |
