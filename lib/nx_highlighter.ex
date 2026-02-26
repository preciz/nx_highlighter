defmodule NxHighlighter do
  @moduledoc """
  Image highlighting using Nx and tensors.

  This library provides a way to highlight multiple rectangular regions in an image.
  It uses:

    * **Nx operations**: Highlights are applied using Nx tensors, which can be
      accelerated by XLA.
    * **Horizontal region merging**: Automatically merges adjacent or nearby horizontal
      highlights of the same color.
    * **Blending formula**: Uses an alpha blending formula to apply highlights.

  The core function `highlight/3` handles different input types (binaries, tensors, StbImage)
  and returns the result in the same format as the input.
  """
  import Nx.Defn

  @default_alpha 0.4

  @type region :: %{
          x: integer(),
          y: integer(),
          w: integer(),
          h: integer(),
          color: [integer()]
        }

  @doc """
  Highlights the given regions on an image.

  ## Parameters

    * `image_input` - Can be a binary (PNG/JPEG), an `StbImage` struct, or an `Nx.Tensor`.
    * `regions` - A list of maps, each containing:
      * `:x`, `:y` - Top-left coordinates.
      * `:w`, `:h` - Width and height of the highlight.
      * `:color` - A list of 3 integers `[R, G, B]` (0-255).
    * `opts` - A keyword list of options.

  ## Options

    * `:alpha` - The blending alpha value between 0.0 and 1.0 (default: 0.4).

  ## Examples

      iex> tensor = Nx.broadcast(255, {100, 100, 3}) |> Nx.as_type(:u8)
      iex> regions = [%{x: 10, y: 10, w: 10, h: 10, color: [255, 0, 0]}]
      iex> {:ok, result} = NxHighlighter.highlight(tensor, regions, alpha: 0.5)
      iex> Nx.shape(result)
      {100, 100, 3}
  """
  @spec highlight(binary() | struct() | Nx.Tensor.t(), [region()], keyword()) ::
          {:ok, binary() | struct() | Nx.Tensor.t()} | {:error, term()}
  def highlight(image_input, regions, opts \\ []) do
    alpha = Keyword.get(opts, :alpha, @default_alpha)
    tensor = to_tensor(image_input)

    case highlight_tensor(tensor, regions, alpha: alpha) do
      {:ok, result_tensor} ->
        from_tensor(result_tensor, image_input)

      {:error, _} = error ->
        error
    end
  rescue
    exception ->
      {:error, exception}
  end

  @doc """
  Highlights the given regions on an Nx tensor.

  Returns `{:ok, tensor}` or `{:error, term}`.
  """
  @spec highlight_tensor(Nx.Tensor.t(), [region()], keyword()) ::
          {:ok, Nx.Tensor.t()} | {:error, term()}
  def highlight_tensor(tensor, regions, opts \\ []) do
    alpha = Keyword.get(opts, :alpha, @default_alpha)
    {height, width, _} = Nx.shape(tensor)

    if regions == [] do
      {:ok, tensor}
    else
      optimized_regions = optimize_regions(regions)

      max_h = Enum.map(optimized_regions, & &1.h) |> Enum.max()
      max_w = Enum.map(optimized_regions, & &1.w) |> Enum.max()

      starts =
        optimized_regions
        |> Enum.map(&[&1.y, &1.x])
        |> Nx.tensor(type: :s64)

      masks =
        optimized_regions
        |> Enum.map(fn %{h: h, w: w} ->
          Nx.broadcast(1, {h, w})
          |> Nx.pad(0, [{0, max_h - h, 0}, {0, max_w - w, 0}])
        end)
        |> Nx.stack()

      batch_colors =
        optimized_regions
        |> Enum.map(& &1.color)
        |> Nx.tensor(type: :u8)

      padded_image =
        tensor
        |> Nx.pad(0, [{0, max_h, 0}, {0, max_w, 0}, {0, 0, 0}])

      result =
        apply_batch_highlights(padded_image, starts, masks, batch_colors, alpha)
        |> Nx.slice([0, 0, 0], [height, width, 3])

      {:ok, result}
    end
  rescue
    exception ->
      {:error, exception}
  end

  defp optimize_regions(regions) do
    regions
    |> Enum.group_by(& &1.color)
    |> Enum.flat_map(fn {_color, group} ->
      merge_horizontal_regions(group)
    end)
  end

  defp merge_horizontal_regions(regions) do
    regions
    |> Enum.sort_by(&{&1.y, &1.x})
    |> Enum.reduce([], &merge_or_append/2)
    |> Enum.reverse()
  end

  defp merge_or_append(region, []), do: [region]

  defp merge_or_append(region, [prev | rest] = acc) do
    if can_merge?(prev, region) do
      [merge(prev, region) | rest]
    else
      [region | acc]
    end
  end

  defp can_merge?(r1, r2) do
    vertical_aligned = r1.y == r2.y and r1.h == r2.h
    horizontal_near = r2.x <= r1.x + r1.w + 10
    vertical_aligned and horizontal_near
  end

  defp merge(r1, r2) do
    new_w = max(r1.x + r1.w, r2.x + r2.w) - r1.x
    %{r1 | w: new_w}
  end

  defp to_tensor(binary) when is_binary(binary) do
    binary
    |> StbImage.read_binary!()
    |> StbImage.to_nx()
  end

  defp to_tensor(%StbImage{} = image), do: StbImage.to_nx(image)
  defp to_tensor(%Nx.Tensor{} = tensor), do: tensor

  defp from_tensor(tensor, binary) when is_binary(binary) do
    tensor
    |> StbImage.from_nx()
    |> StbImage.to_binary(:png)
    |> then(&{:ok, &1})
  end

  defp from_tensor(tensor, %StbImage{}), do: {:ok, StbImage.from_nx(tensor)}
  defp from_tensor(tensor, %Nx.Tensor{}), do: {:ok, tensor}

  defn apply_batch_highlights(padded_image, starts, masks, colors, alpha) do
    count = Nx.axis_size(starts, 0)
    ph = Nx.axis_size(masks, 1)
    pw = Nx.axis_size(masks, 2)

    {final_image, _, _, _, _, _, _} =
      while {canvas = padded_image, original = padded_image, i = 0, starts, masks, colors, alpha},
            i < count do
        start_y = starts[i][0]
        start_x = starts[i][1]
        mask = masks[i]
        color = colors[i]

        patch = Nx.slice(original, [start_y, start_x, 0], [ph, pw, 3])
        mask_3d = Nx.broadcast(Nx.new_axis(mask, -1), {ph, pw, 3})
        color_3d = Nx.broadcast(color, {ph, pw, 3})

        patch_f32 = Nx.as_type(patch, :f32)
        mask_f32 = Nx.as_type(mask_3d, :f32)
        color_f32 = Nx.as_type(color_3d, :f32)

        blended =
          patch_f32
          |> Nx.add(color_f32 |> Nx.subtract(patch_f32) |> Nx.multiply(mask_f32) |> Nx.multiply(alpha))
          |> Nx.as_type(:u8)

        updated_canvas = Nx.put_slice(canvas, [start_y, start_x, 0], blended)

        {updated_canvas, original, i + 1, starts, masks, colors, alpha}
      end

    final_image
  end
end
