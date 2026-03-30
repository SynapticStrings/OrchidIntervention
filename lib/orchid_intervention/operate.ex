defmodule OrchidIntervention.Operate do
  @moduledoc """
  Declara how interventions that from outside take effect to
  Orchid DAG's specific Param.
  """

  @type stage :: :prelude | :postlude

  @doc """
  Declare at which stage the intervention will be performed:

  - `:prelude`: Before the Step is executed.
      Typically used to overwrite (:override) data.
  - `:postlude`: After the Step is executed.
      Typically used to modify calculation results (e.g., :offset, :mask).
  """
  @callback stage() :: stage()

  @callback short_circuit?() :: boolean()

  @doc """
  Defines the enabling state of the data. Used for subsequent calculations of merged cache keys.

  Returns `{Use_internal_data?, Use_intervening_data?}`.

  For example, `:override` returns `{false, true}`, while `:offset` returns `{true, true}`.
  """
  @callback data_enable() :: {boolean(), boolean()}

  @doc """
  Perform the actual merge or overwrite logic.

  - For `:prelude`, `inner_data` is nil.
  - For `:postlude`, `inner_data` is the original result calculated by Step.
  """
  @callback merge(
              inner_data :: Orchid.Param.payload() | nil,
              intervention_data :: Orchid.Param.payload()
            ) :: {:ok, Orchid.Param.payload()} | {:error, term()}
end
