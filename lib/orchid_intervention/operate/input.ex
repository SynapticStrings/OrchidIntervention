defmodule OrchidIntervention.Operate.Input do
  @behaviour OrchidIntervention.Operate

  @impl true
  def stage, do: :prelude

  @impl true
  def short_circuit?, do: false

  @impl true
  def data_enable, do: {false, true}

  @impl true
  def merge(_inner_data, intervention_data) do
    {:ok, intervention_data}
  end
end
