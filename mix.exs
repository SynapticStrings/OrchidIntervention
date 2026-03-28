defmodule OrchidIntervention.MixProject do
  use Mix.Project

  def project do
    [
      app: :orchid_intervention,
      version: "0.1.0",
      elixir: "~> 1.17",
      start_permanent: Mix.env() == :prod,
      deps: deps()
    ]
  end

  def application do
    [
      extra_applications: [:logger]
    ]
  end

  defp deps do
    [
      {:orchid, "~> 0.5"},
      # {:orchid_stratum, "~> 0.1", optional: true}
    ]
  end
end
