defmodule OrchidInterventionStorageTest do
  use ExUnit.Case

  defmodule InterventionStorage do
    @behaviour Orchid.Repo

    def init(session_name),
      do: :ets.new(session_to_table(session_name), [:set, :public, :named_table])

    @impl Orchid.Repo
    def get(session_name, key) do
      case :ets.lookup(session_to_table(session_name), key) do
        [{^key, val}] -> {:ok, val}
        [] -> :miss
      end
    end

    @impl Orchid.Repo
    def put(session_name, key, val) do
      :ets.insert(session_to_table(session_name), {key, val})
      :ok
    end

    defp session_to_table(session_name), do: :"#{session_name}_Intervention"
  end

  defmodule MockIntervention do
    # Generate raw 
  end

  describe "outside can inject interventions via storage" do
    # ...
  end

  describe "storage's data can be fetched within Orchid.Repo" do
    # ...
  end
end
