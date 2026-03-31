defmodule OrchidIntervention.MixProject do
  use Mix.Project

  @version "0.1.0"
  @source_url "https://github.com/SynapticStrings/OrchidIntervention"

  def project do
    [
      app: :orchid_intervention,
      version: @version,
      elixir: "~> 1.17",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      description: description(),
      elixirc_paths: elixirc_paths(Mix.env()),
      package: package(),
      docs: docs(),
      test_coverage: [
        ignore_modules: [
          ~r/.*Test.*/,
          # OrchidIntervention.Operate.Override
        ]
      ]
    ]
  end

  def application do
    [
      extra_applications: [:logger]
    ]
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  defp description do
    """
    Result = DAG + Intervention.
    Declaratively inject, override, and short-circuit step outputs in Orchid workflows.
    """
  end

  defp deps do
    [
      {:orchid, "~> 0.6"},
      {:ex_doc, "~> 0.40", only: :dev, runtime: false}
    ]
  end

  defp package do
    [
      name: "orchid_intervention",
      files: ~w(lib .formatter.exs mix.exs README.md LICENSE),
      licenses: ["MIT"],
      links: %{
        "GitHub" => @source_url,
        "Orchid Core" => "https://hex.pm/packages/orchid"
      }
    ]
  end

  defp docs do
    [
      main: "readme",
      extras: ["README.md"],
      source_ref: "v#{@version}",
      source_url: @source_url
    ]
  end
end
