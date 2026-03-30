defmodule OrchidIntervention do
  @moduledoc """
  Documentation for `OrchidIntervention`.
  """

  @type intervention_type :: :input | :override | atom()

  @type payload :: (-> Orchid.Param.t()) | Orchid.Param.t() | term()

  @type interventions :: %{Orchid.Step.io_key() => %{intervention_type => payload} | {intervention_type, payload}}
end
