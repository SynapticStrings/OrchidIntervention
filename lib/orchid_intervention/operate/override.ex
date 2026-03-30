defmodule OrchidIntervention.Operate.Override do
  @behaviour OrchidIntervention.Operate

  @impl true
  def short_circuit?, do: true

  @impl true
  def data_enable, do: {false, true}

  @impl true
  def merge(_inner_data, intervention_data) do
    {:ok, intervention_data}
  end
end
