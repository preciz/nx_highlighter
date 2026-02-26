defmodule NxHighlighter.MixProject do
  use Mix.Project

  @version "0.1.0"
  @description "Image highlighting using Nx and tensors."

  def project do
    [
      app: :nx_highlighter,
      version: @version,
      elixir: "~> 1.18",
      start_permanent: Mix.env() == :prod,
      description: @description,
      package: package(),
      deps: deps(),
      name: "NxHighlighter",
      source_url: "https://github.com/preciz/nx_highlighter",
      docs: [
        main: "NxHighlighter",
        extras: ["README.md"]
      ]
    ]
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      extra_applications: [:logger]
    ]
  end

  defp package do
    [
      maintainers: ["Barna Kovacs"],
      licenses: ["MIT"],
      links: %{"GitHub" => "https://github.com/preciz/nx_highlighter"}
    ]
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      {:nx, "~> 0.10"},
      {:exla, "~> 0.10"},
      {:stb_image, "~> 0.6"},
      {:ex_doc, "~> 0.34", only: :dev, runtime: false},
      {:benchee, "~> 1.3", only: [:dev, :test]}
    ]
  end
end
