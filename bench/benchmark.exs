# Benchmark script for NxHighlighter
# Run with: mix run bench/benchmark.exs

# Ensure we use EXLA for hardware acceleration if available
Nx.global_default_backend(EXLA.Backend)

# Create a 1000x1000 white image
height = 1000
width = 1000
tensor = Nx.broadcast(255, {height, width, 3}) |> Nx.as_type(:u8)

# Generate varied region counts
generate_regions = fn count ->
  for _ <- 1..count do
    %{
      x: Enum.random(0..740),
      y: Enum.random(0..740),
      w: Enum.random(10..200),
      h: Enum.random(10..200),
      color: [Enum.random(0..255), Enum.random(0..255), Enum.random(0..255)]
    }
  end
end

inputs = %{
  "10 regions" => generate_regions.(10),
  "50 regions" => generate_regions.(50),
  "100 regions" => generate_regions.(100)
}

Benchee.run(
  %{
    "NxHighlighter (V1)" => fn regions ->
      {:ok, _} = NxHighlighter.highlight(tensor, regions)
    end,
    "NxHighlighterV4 (Tiled)" => fn regions ->
      {:ok, _} = NxHighlighterV4.highlight(tensor, regions)
    end
  },
  inputs: inputs,
  time: 10,
  warmup: 2,
  memory_time: 2
)
