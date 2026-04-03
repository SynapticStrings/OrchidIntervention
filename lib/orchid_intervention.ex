defmodule OrchidIntervention do
  @moduledoc """
  Documentation for `OrchidIntervention`.
  """

  @type intervention_type :: :input | :override | module()
  @type payload :: (-> Orchid.Param.t()) | mfa() | Orchid.Param.t() | term()
  @type intervention_spec :: {intervention_type(), payload()}
  @type t :: %{Orchid.Step.io_key() => intervention_spec()}

  @spec filter_by_type(t(), intervention_type()) :: t()
  def filter_by_type(interventions, type) do
    Map.filter(interventions, fn {_key, {t, _val}} -> t == type end)
  end

  @spec get(t(), Orchid.Step.io_key()) :: intervention_spec() | nil
  def get(interventions, key) do
    Map.get(interventions, key)
  end

  @spec operon_type?(intervention_type()) :: boolean()
  def operon_type?(:input), do: true
  def operon_type?(_), do: false

  # TODO: apply_interventions
  # Stratum's outside
  # OrchidIntervention => Stratum => ... => Core
end
