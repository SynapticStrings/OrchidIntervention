defmodule OrchidIntervention.Operate do
  @moduledoc """
  Declara how interventions that from outside take effect to
  Orchid DAG's specific Param.

  For some custome type/module. like mask, overlap, etc.
  """

  @callback short_circuit?() :: boolean()

  @doc """
  Defines the enabling state of the data. Used for subsequent calculations of merged cache keys.

  Returns `{Use_internal_data?, Use_intervening_data?}`.

  For example, `:override` returns `{false, true}`, while `:offset` returns `{true, true}`.
  """
  @callback data_enable() :: {boolean(), boolean()}

  @doc """
  Perform the actual merge or overwrite logic.

  - If `short_circuit?` is true, `inner_data` is nil.
  - Else, `inner_data` is the original result calculated by Step.
  """
  @callback merge(
              inner_data :: Orchid.Param.payload() | nil,
              intervention_data :: Orchid.Param.payload()
            ) :: {:ok, Orchid.Param.payload()} | {:error, term()}
end
