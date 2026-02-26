defmodule NxHighlighter.MixProject do
  use Mix.Project

  def project do
    [
      app: :nx_highlighter,
      version: "0.1.0",
      elixir: "~> 1.15",
      start_permanent: Mix.env() == :prod,
      deps: deps()
    ]
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      extra_applications: [:logger]
    ]
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      {:nx, "~> 0.10"},
      {:exla, "~> 0.10"},
      {:stb_image, "~> 0.6"}
    ]
  end
end
