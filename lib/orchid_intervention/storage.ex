defmodule OrchidIntervention.Storage do
  @moduledoc """
  Stores the results of computationally expensive interventions (e.g. Image Masking).
  Simple O(1) interventions like :override are not cached here.
  """

  @doc "Fetches a merged payload from the cache."
  def get(nil, _key), do: :miss

  def get(store_conf, cache_key) do
    Orchid.Repo.dispatch_store(store_conf, :get, [cache_key])
  end

  @doc "Persists a computed merged payload into the cache."
  def put(nil, _key, _value), do: :ok

  def put(store_conf, cache_key, value) do
    Orchid.Repo.dispatch_store(store_conf, :put, [cache_key, value])
  end
end
