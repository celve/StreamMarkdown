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
- [See $\alpha$](https://en.wikipedia.org/wiki/Alpha) links still open.

| Symbol | Meaning |
|---|---|
| $\alpha$ | learning rate |
