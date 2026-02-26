# NxHighlighter

Image highlighting using Nx and tensors.

## Features

- **XLA Accelerated:** Uses Nx operations for efficiency.
- **Blending Formula:** Custom formula for highlight transparency.
- **Region Merging:** Automatically merges horizontal highlights of the same color that are close to each other.
- **Configurable Alpha:** Global alpha blending (default 0.4).
- **Flexible I/O:** Accepts and returns PNG/JPEG binaries, `StbImage` structs, or `Nx.Tensor`.

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

The library handles image loading and saving via [stb_image](https://hex.pm/packages/stb_image). It preserves the input format: if you pass a binary, you get a binary; if you pass a tensor, you get a tensor.

### High-level API

```elixir
image_bin = File.read!("image.png")
regions = [
  %{x: 10, y: 10, w: 100, h: 20, color: [255, 0, 0]},
  %{x: 120, y: 10, w: 50, h: 20, color: [255, 0, 0]}
]

# Returns {:ok, png_binary}
{:ok, highlighted_png} = NxHighlighter.highlight(image_bin, regions, alpha: 0.5)
File.write!("highlighted.png", highlighted_png)
```

### Tensor API

If you are already working with tensors, you can use `highlight_tensor/3` to avoid encoding/decoding overhead.

```elixir
{:ok, result_tensor} = NxHighlighter.highlight_tensor(my_tensor, regions)
```
