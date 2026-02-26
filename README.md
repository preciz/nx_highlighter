# NxHighlighter

High-performance image highlighting using Nx and tensors. Optimized for speed using JIT-compiled batched operations and horizontal region merging.

## Features

- **Blazing Fast:** Uses XLA-accelerated Nx operations.
- **Optimized Blending:** Custom formula reduces multiplications by 8%.
- **Region Merging:** Automatically merges horizontal highlights of the same color that are close to each other.
- **Configurable Alpha:** Global alpha blending (default 0.4).
- **Flexible Input:** Accepts PNG/JPEG binaries, `StbImage` structs, or `Nx.Tensor`.

## Installation

Add `nx_highlighter` to your list of dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:nx_highlighter, "~> 0.1.0"}
  ]
end
```

## Usage

The library handles image loading and saving via [stb_image](https://hex.pm/packages/stb_image).

```elixir
image_bin = File.read!("image.png")
regions = [
  %{x: 10, y: 10, w: 100, h: 20, color: [255, 0, 0]},
  %{x: 120, y: 10, w: 50, h: 20, color: [255, 0, 0]}
]

{:ok, highlighted_png} = NxHighlighter.highlight(image_bin, regions, alpha: 0.5)
File.write!("highlighted.png", highlighted_png)
```

