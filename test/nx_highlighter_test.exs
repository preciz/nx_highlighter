defmodule NxHighlighterTest do
  use ExUnit.Case
  doctest NxHighlighter

  setup do
    # Create a simple 100x100 white image
    tensor = Nx.broadcast(255, {100, 100, 3}) |> Nx.as_type(:u8)
    png_bin = StbImage.from_nx(tensor) |> StbImage.to_binary(:png)
    {:ok, png_bin: png_bin, tensor: tensor}
  end

  describe "input formats" do
    test "highlights using binary input (PNG)", %{png_bin: png_bin} do
      regions = [%{x: 10, y: 10, w: 10, h: 10, color: [255, 0, 0]}]
      assert {:ok, result_png} = NxHighlighter.highlight(png_bin, regions)
      assert is_binary(result_png)
      assert <<137, 80, 78, 71, _::binary>> = result_png
    end

    test "highlights using StbImage input" do
      tensor = Nx.broadcast(255, {10, 10, 3}) |> Nx.as_type(:u8)
      stb_image = StbImage.from_nx(tensor)
      regions = [%{x: 2, y: 2, w: 2, h: 2, color: [0, 255, 0]}]
      assert {:ok, result} = NxHighlighter.highlight(stb_image, regions)
      assert %StbImage{} = result
    end

    test "highlights using Tensor input", %{tensor: tensor} do
      regions = [%{x: 0, y: 0, w: 5, h: 5, color: [0, 0, 255]}]
      assert {:ok, result} = NxHighlighter.highlight(tensor, regions)
      assert %Nx.Tensor{} = result
      assert Nx.shape(result) == {100, 100, 3}
    end

    test "returns error on invalid binary input" do
      assert {:error, _} =
               NxHighlighter.highlight("not an image", [
                 %{x: 0, y: 0, w: 1, h: 1, color: [0, 0, 0]}
               ])
    end

    test "returns error on nil input" do
      assert {:error, _} = NxHighlighter.highlight(nil, [])
    end

    test "returns error when internal logic fails", %{tensor: tensor} do
      # Passing invalid regions to trigger rescue in highlight_tensor
      # which is then handled by the error branch in highlight
      assert {:error, _} = NxHighlighter.highlight(tensor, :invalid_regions)
    end

    test "handles empty regions list", %{png_bin: png_bin} do
      assert {:ok, result_png} = NxHighlighter.highlight(png_bin, [])
      assert is_binary(result_png)
    end
  end

  describe "highlight_tensor/3" do
    test "directly highlights a tensor", %{tensor: tensor} do
      regions = [%{x: 0, y: 0, w: 1, h: 1, color: [255, 0, 0]}]
      assert {:ok, result_tensor} = NxHighlighter.highlight_tensor(tensor, regions)
      assert result_tensor[0][0] |> Nx.to_flat_list() == [255, 153, 153]
    end
  end

  describe "blending correctness" do
    test "correctly blends colors at default (0.4) alpha", %{png_bin: png_bin} do
      regions = [%{x: 0, y: 0, w: 1, h: 1, color: [255, 0, 0]}]
      {:ok, result_png} = NxHighlighter.highlight(png_bin, regions)

      result_tensor = StbImage.read_binary!(result_png) |> StbImage.to_nx()
      pixel = result_tensor[0][0] |> Nx.to_flat_list()

      # Formula: New = Base * (1 - Alpha) + Highlight * Alpha
      # Base: [255, 255, 255], Alpha: 0.4, Highlight: [255, 0, 0]
      # R: 255 * 0.6 + 255 * 0.4 = 153 + 102 = 255
      # G: 255 * 0.6 + 0 * 0.4 = 153
      # B: 255 * 0.6 + 0 * 0.4 = 153
      assert pixel == [255, 153, 153]
    end

    test "correctly blends colors at custom (1.0) alpha", %{png_bin: png_bin} do
      regions = [%{x: 0, y: 0, w: 1, h: 1, color: [255, 0, 0]}]
      {:ok, result_png} = NxHighlighter.highlight(png_bin, regions, alpha: 1.0)

      result_tensor = StbImage.read_binary!(result_png) |> StbImage.to_nx()
      pixel = result_tensor[0][0] |> Nx.to_flat_list()

      # Alpha 1.0 means full override
      assert pixel == [255, 0, 0]
    end

    test "correctly blends colors at custom (0.0) alpha", %{png_bin: png_bin} do
      regions = [%{x: 0, y: 0, w: 1, h: 1, color: [255, 0, 0]}]
      {:ok, result_png} = NxHighlighter.highlight(png_bin, regions, alpha: 0.0)

      result_tensor = StbImage.read_binary!(result_png) |> StbImage.to_nx()
      pixel = result_tensor[0][0] |> Nx.to_flat_list()

      # Alpha 0.0 means no change
      assert pixel == [255, 255, 255]
    end

    test "highlights correctly on non-white background" do
      # Create a black image
      tensor = Nx.broadcast(0, {10, 10, 3}) |> Nx.as_type(:u8)
      regions = [%{x: 0, y: 0, w: 1, h: 1, color: [255, 255, 255]}]
      {:ok, result_tensor} = NxHighlighter.highlight(tensor, regions)

      pixel = result_tensor[0][0] |> Nx.to_flat_list()

      # Base: [0, 0, 0], Alpha: 0.4, Highlight: [255, 255, 255]
      # 0 * 0.6 + 255 * 0.4 = 102
      assert pixel == [102, 102, 102]
    end
  end

  describe "region optimization (merging)" do
    test "merges adjacent horizontal regions of same color", %{png_bin: png_bin} do
      regions = [
        %{x: 10, y: 10, w: 10, h: 10, color: [255, 0, 0]},
        %{x: 20, y: 10, w: 10, h: 10, color: [255, 0, 0]}
      ]

      {:ok, result_png} = NxHighlighter.highlight(png_bin, regions)
      result_tensor = StbImage.read_binary!(result_png) |> StbImage.to_nx()

      # Check pixel at x=19 (end of first) and x=20 (start of second)
      assert result_tensor[15][19] |> Nx.to_flat_list() == [255, 153, 153]
      assert result_tensor[15][20] |> Nx.to_flat_list() == [255, 153, 153]
    end

    test "merges regions with a small gap (<= 10px)", %{png_bin: png_bin} do
      regions = [
        %{x: 10, y: 10, w: 10, h: 10, color: [255, 0, 0]},
        # 5px gap
        %{x: 25, y: 10, w: 10, h: 10, color: [255, 0, 0]}
      ]

      {:ok, result_png} = NxHighlighter.highlight(png_bin, regions)
      result_tensor = StbImage.read_binary!(result_png) |> StbImage.to_nx()

      # Pixel in the gap (x=22) should be highlighted
      assert result_tensor[15][22] |> Nx.to_flat_list() == [255, 153, 153]
    end

    test "does NOT merge regions with gap > 10px", %{png_bin: png_bin} do
      regions = [
        %{x: 10, y: 10, w: 10, h: 10, color: [255, 0, 0]},
        # 11px gap
        %{x: 31, y: 10, w: 10, h: 10, color: [255, 0, 0]}
      ]

      {:ok, result_png} = NxHighlighter.highlight(png_bin, regions)
      result_tensor = StbImage.read_binary!(result_png) |> StbImage.to_nx()

      # Pixel in the middle of gap (x=25) should NOT be highlighted
      assert result_tensor[15][25] |> Nx.to_flat_list() == [255, 255, 255]
    end

    test "does NOT merge regions with different colors", %{png_bin: png_bin} do
      regions = [
        %{x: 10, y: 10, w: 10, h: 10, color: [255, 0, 0]},
        %{x: 20, y: 10, w: 10, h: 10, color: [0, 255, 0]}
      ]

      {:ok, result_png} = NxHighlighter.highlight(png_bin, regions)
      result_tensor = StbImage.read_binary!(result_png) |> StbImage.to_nx()

      # Red part
      assert result_tensor[15][15] |> Nx.to_flat_list() == [255, 153, 153]
      # Green part
      assert result_tensor[15][25] |> Nx.to_flat_list() == [153, 255, 153]
    end

    test "does NOT merge regions on different Y coordinates", %{png_bin: png_bin} do
      regions = [
        %{x: 10, y: 10, w: 10, h: 10, color: [255, 0, 0]},
        %{x: 10, y: 20, w: 10, h: 10, color: [255, 0, 0]}
      ]

      {:ok, result_png} = NxHighlighter.highlight(png_bin, regions)
      result_tensor = StbImage.read_binary!(result_png) |> StbImage.to_nx()

      assert result_tensor[19][15] |> Nx.to_flat_list() == [255, 153, 153]
      assert result_tensor[20][15] |> Nx.to_flat_list() == [255, 153, 153]
    end
  end

  describe "complex scenarios" do
    test "handles overlapping regions of same color", %{png_bin: png_bin} do
      regions = [
        %{x: 10, y: 10, w: 20, h: 20, color: [255, 0, 0]},
        %{x: 15, y: 15, w: 20, h: 20, color: [255, 0, 0]}
      ]

      {:ok, result_png} = NxHighlighter.highlight(png_bin, regions)
      result_tensor = StbImage.read_binary!(result_png) |> StbImage.to_nx()

      assert result_tensor[17][17] |> Nx.to_flat_list() == [255, 153, 153]
    end

    test "handles overlapping regions of different colors", %{png_bin: png_bin} do
      regions = [
        %{x: 10, y: 10, w: 20, h: 20, color: [255, 0, 0]},
        %{x: 15, y: 15, w: 20, h: 20, color: [0, 255, 0]}
      ]

      {:ok, result_png} = NxHighlighter.highlight(png_bin, regions)
      result_tensor = StbImage.read_binary!(result_png) |> StbImage.to_nx()

      pixel = result_tensor[17][17] |> Nx.to_flat_list()
      assert pixel in [[255, 153, 153], [153, 255, 153]]
    end

    test "handles regions exceeding image boundaries", %{png_bin: png_bin} do
      # Image is 100x100
      regions = [%{x: 90, y: 90, w: 20, h: 20, color: [255, 0, 0]}]
      assert {:ok, result_png} = NxHighlighter.highlight(png_bin, regions)
      result_tensor = StbImage.read_binary!(result_png) |> StbImage.to_nx()
      assert Nx.shape(result_tensor) == {100, 100, 3}
      assert result_tensor[95][95] |> Nx.to_flat_list() == [255, 153, 153]
    end

    test "handles very small regions", %{png_bin: png_bin} do
      regions = [%{x: 5, y: 5, w: 1, h: 1, color: [255, 0, 0]}]
      {:ok, result_png} = NxHighlighter.highlight(png_bin, regions)
      result_tensor = StbImage.read_binary!(result_png) |> StbImage.to_nx()
      assert result_tensor[5][5] |> Nx.to_flat_list() == [255, 153, 153]
      assert result_tensor[5][6] |> Nx.to_flat_list() == [255, 255, 255]
    end

    test "handles many regions (batch stress test)", %{png_bin: png_bin} do
      regions =
        for i <- 0..20, j <- 0..20 do
          %{
            x: i * 4,
            y: j * 4,
            w: 2,
            h: 2,
            color: [Enum.random(0..255), Enum.random(0..255), Enum.random(0..255)]
          }
        end

      assert {:ok, _} = NxHighlighter.highlight(png_bin, regions)
    end
  end
end
