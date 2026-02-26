defmodule NxHighlighterTest do
  use ExUnit.Case
  doctest NxHighlighter

  setup do
    # Create a simple 100x100 white image
    tensor = Nx.broadcast(255, {100, 100, 3}) |> Nx.as_type(:u8)
    png_bin = StbImage.from_nx(tensor) |> StbImage.to_binary(:png)
    {:ok, png_bin: png_bin, tensor: tensor}
  end

  test "highlights nothing when regions are empty", %{png_bin: png_bin} do
    assert {:ok, result_png} = NxHighlighter.highlight(png_bin, [])
    assert is_binary(result_png)
    # White image should remain white
    result_tensor = StbImage.read_binary!(result_png) |> StbImage.to_nx()
    assert Nx.all(Nx.equal(result_tensor, 255)) |> Nx.to_number() == 1
  end

  test "highlights a single region on binary input", %{png_bin: png_bin} do
    regions = [%{x: 10, y: 10, w: 20, h: 20, color: [255, 0, 0]}]
    assert {:ok, result_png} = NxHighlighter.highlight(png_bin, regions)
    
    result_tensor = StbImage.read_binary!(result_png) |> StbImage.to_nx()
    # Check a pixel inside the highlight
    pixel = result_tensor[15][15] |> Nx.to_flat_list()
    # White (255) blended with Red (255, 0, 0) at alpha 0.4
    # New = 255 * (1 - 0.4) + Target * 0.4
    # Red channel: 255 * 0.6 + 255 * 0.4 = 255
    # Green channel: 255 * 0.6 + 0 * 0.4 = 153
    # Blue channel: 255 * 0.6 + 0 * 0.4 = 153
    assert pixel == [255, 153, 153]
  end

  test "highlights using StbImage input" do
    tensor = Nx.broadcast(255, {10, 10, 3}) |> Nx.as_type(:u8)
    stb_image = StbImage.from_nx(tensor)
    regions = [%{x: 2, y: 2, w: 2, h: 2, color: [0, 255, 0]}]
    assert {:ok, _} = NxHighlighter.highlight(stb_image, regions)
  end

  test "highlights using Tensor input", %{tensor: tensor} do
    regions = [%{x: 0, y: 0, w: 5, h: 5, color: [0, 0, 255]}]
    assert {:ok, _} = NxHighlighter.highlight(tensor, regions)
  end

  test "merges horizontal regions with same color", %{png_bin: png_bin} do
    # Two regions close to each other
    regions = [
      %{x: 10, y: 10, w: 10, h: 10, color: [255, 0, 0]},
      %{x: 25, y: 10, w: 10, h: 10, color: [255, 0, 0]} # 5px gap, should merge
    ]
    # Internal optimization check would be hard from output, but we test functionality
    assert {:ok, result_png} = NxHighlighter.highlight(png_bin, regions)
    result_tensor = StbImage.read_binary!(result_png) |> StbImage.to_nx()
    
    # Check pixel in the gap (x=22) - it should be highlighted if merged
    gap_pixel = result_tensor[15][22] |> Nx.to_flat_list()
    assert gap_pixel == [255, 153, 153]
  end

  test "does not merge regions with different colors", %{png_bin: png_bin} do
    regions = [
      %{x: 10, y: 10, w: 10, h: 10, color: [255, 0, 0]},
      %{x: 22, y: 10, w: 10, h: 10, color: [0, 255, 0]}
    ]
    assert {:ok, result_png} = NxHighlighter.highlight(png_bin, regions)
    result_tensor = StbImage.read_binary!(result_png) |> StbImage.to_nx()
    
    # Gap at x=21 should NOT be highlighted
    gap_pixel = result_tensor[15][21] |> Nx.to_flat_list()
    assert gap_pixel == [255, 255, 255]
  end

  test "handles multiple colors and overlapping regions", %{png_bin: png_bin} do
    regions = [
      %{x: 10, y: 10, w: 50, h: 50, color: [255, 0, 0]},
      %{x: 20, y: 20, w: 50, h: 50, color: [0, 255, 0]}
    ]
    assert {:ok, _} = NxHighlighter.highlight(png_bin, regions)
  end

  test "returns error on invalid input" do
    assert {:error, _} = NxHighlighter.highlight(nil, [])
    assert {:error, _} = NxHighlighter.highlight("not an image", [%{x: 0, y: 0, w: 1, h: 1, color: [0, 0, 0]}])
  end
end
