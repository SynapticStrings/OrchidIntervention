defmodule OrchidIntervention.Storage do
  @moduledoc """
  Independent two-tier caching for intervention data and merge results.

  Deliberately separate from OrchidStratum to avoid GC policy conflicts:
  OrchidStratum caches step-level results with content-addressable blob semantics,
  while this module caches intervention-specific artifacts with different
  lifecycle expectations (interventions are user-controlled, externally mutable).

  ## Architecture

      ┌─────────────────────┐     ┌──────────────────────┐
      │  Intervention Store │     │  MergeResult Store   │
      │  (read-only in DAG) │     │  (read+write in DAG) │
      │  keyed by           │     │  keyed by            │
      │  InterventionKey    │     │  MergeResultKey      │
      └─────────────────────┘     └──────────────────────┘

  Both stores implement `Orchid.Repo`. The MergeResult store additionally
  implements `Orchid.Repo.Deletable` for targeted invalidation.

  ## Usage

      interv_conf = {OrchidIntervention.Storage.EtsAdapter, interv_ref}
      merge_conf  = {OrchidIntervention.Storage.EtsAdapter, merge_ref}

      baggage = %{
        interventions: ...,
        interv_cache: interv_conf,
        merge_cache: merge_conf
      }
  """

  alias OrchidIntervention.KeyBuilder

  @doc """
  Looks up a cached merge result. Returns `{:ok, payload}` or `:miss`.
  """
  @spec get_merge_result(
          {module(), term()},
          module(),
          KeyBuilder.key_type(),
          KeyBuilder.key_type() | nil
        ) :: {:ok, term()} | :miss
  def get_merge_result(merge_store_conf, operate_mod, intervention_key, inner_result_key) do
    cache_key = KeyBuilder.merge_result_key(operate_mod, intervention_key, inner_result_key)
    Orchid.Repo.dispatch_store(merge_store_conf, :get, [cache_key])
  end

  @doc """
  Persists a merge result.
  """
  @spec put_merge_result(
          {module(), term()},
          module(),
          KeyBuilder.key_type(),
          KeyBuilder.key_type() | nil,
          term()
        ) :: :ok
  def put_merge_result(merge_store_conf, operate_mod, intervention_key, inner_result_key, value) do
    cache_key = KeyBuilder.merge_result_key(operate_mod, intervention_key, inner_result_key)
    Orchid.Repo.dispatch_store(merge_store_conf, :put, [cache_key, value])
  end

  @doc """
  Looks up cached intervention data by its key.
  """
  @spec get_intervention(
          {module(), term()},
          OrchidIntervention.intervention_type(),
          Orchid.Step.io_key(),
          term()
        ) :: {:ok, term()} | :miss
  def get_intervention(interv_store_conf, type, io_key, data_digest) do
    cache_key = KeyBuilder.intervention_key(type, io_key, data_digest)
    Orchid.Repo.dispatch_store(interv_store_conf, :get, [cache_key])
  end

  @doc """
  Persists intervention data.
  """
  @spec put_intervention(
          {module(), term()},
          OrchidIntervention.intervention_type(),
          Orchid.Step.io_key(),
          term(),
          term()
        ) :: :ok
  def put_intervention(interv_store_conf, type, io_key, data_digest, value) do
    cache_key = KeyBuilder.intervention_key(type, io_key, data_digest)
    Orchid.Repo.dispatch_store(interv_store_conf, :put, [cache_key, value])
  end
end
