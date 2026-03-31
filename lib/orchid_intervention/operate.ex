defmodule OrchidIntervention.Operate do
  @moduledoc """
  Declares how an intervention type merges external data into a DAG step's output.  

  Every intervention type (`:override`, custom modules like `MyApp.Operate.Offset`)  
  must implement this behaviour. The callbacks inform the Hook whether the step  
  can be short-circuited and how caching keys should be derived.  

  ## Built-in Implementations  

  - `OrchidIntervention.Operate.Override` — replaces step output entirely,  
    supports short-circuit.  

  ## Custom Implementations  

  Pass the module atom directly as the intervention type:

      %{"signal" => {MyApp.Operate.Offset, offset_param}}

  The module must implement all callbacks in this behaviour.
  """

  @doc """
  Whether this intervention type allows bypassing step execution entirely.  

  When `true` and **all** output keys of a step are covered by short-circuit-capable  
  interventions, the step body is never called.  
  """
  @callback short_circuit?() :: boolean()

  @doc """
  Declares which data sources are relevant for cache key derivation.  

  Returns `{use_inner_result?, use_intervention_data?}`.  

  Examples:  
  - `:override` → `{false, true}` — inner data changes don't invalidate cache  
  - A hypothetical `:offset` → `{true, true}` — both matter  
  """
  @callback data_enable() :: {boolean(), boolean()}

  @doc """
  Performs the actual merge of step output with intervention data.  

  - `inner_data` is the step's computed payload (or `nil` when short-circuiting).  
  - `intervention_data` is the resolved intervention payload.

  Must return `{:ok, merged_payload}` or `{:error, reason}`.
  """
  @callback merge(
              inner_data :: Orchid.Param.payload() | nil,
              intervention_data :: Orchid.Param.payload()
            ) :: {:ok, Orchid.Param.payload()} | {:error, term()}

  @doc """
  Resolves an intervention type atom to its Operate implementation module.  

  Built-in atoms are mapped internally; any other atom is assumed to be  
  a module that implements this behaviour directly.
  """
  @spec resolve_module(OrchidIntervention.intervention_type()) :: module()
  def resolve_module(:override), do: OrchidIntervention.Operate.Override
  def resolve_module(mod) when is_atom(mod), do: mod
end
