defmodule OrchidInterventionStorageTest do
  use ExUnit.Case

  defmodule InterventionStorage do
    @behaviour Orchid.Repo
    @behaviour Orchid.Repo.ContentAddressable

    def init, do: :ets.new(__MODULE__, [:set, :public])

    @impl true
    def get(ets_ref, key) do
      case :ets.lookup(ets_ref, key) do
        [{^key, val}] -> {:ok, val}
        [] -> :miss
      end
    end

    @impl true
    def put(ets_ref, key, val) do
      :ets.insert(ets_ref, {key, val})

      :ok
    end

    @impl true
    def exists?(ets_ref, key) do
      :ets.member(ets_ref, key)
    end
  end

  defmodule MockIntervention do
    def generate() do
      # ...
    end
  end

  describe "outside can inject interventions via storage" do
    # ...
  end

  describe "storage's data can be fetched within Orchid.Repo" do
    # ...
  end
end
