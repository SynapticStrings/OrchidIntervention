defmodule Orchid.Hook.ApplyInterventions do
  @moduledoc """
  Runner hook that applies non-input interventions to step outputs.

  ## Execution Model

  For each step that has matching interventions on its output keys:

  1. **Short-circuit check** — if *every* output key is covered by an
     intervention whose `short_circuit?/0` returns `true`, the step body
     is bypassed entirely and intervention data is returned as the result.

  2. **Normal execution + merge** — otherwise the step runs normally, then
     each output key with an intervention is post-processed via the
     intervention's `merge/2` callback. Keys without interventions are
     passed through unchanged.

  ## Output Format

  Always returns `{:ok, %{key => Param}}` (map format).
  """
  @behaviour Orchid.Runner.Hook

  alias OrchidIntervention.{Operate, Resolver}

  @impl true
  def call(ctx, next_fn) do
    interventions =
      Orchid.WorkflowCtx.get_baggage(ctx.workflow_ctx, :interventions, %{})

    active =
      ctx.out_keys
      |> extract_step_interventions(interventions)
      |> Map.reject(fn {_k, {type, _v}} -> OrchidIntervention.operon_type?(type) end)

    if map_size(active) == 0 do
      next_fn.(ctx)
    else
      apply_interventions(ctx, next_fn, active)
    end
  end

  # ── Core Logic ──

  defp apply_interventions(ctx, next_fn, interventions) do
    out_keys = normalize_out_keys(ctx.out_keys)

    case maybe_short_circuit(out_keys, interventions) do
      {:short_circuit, result_lists} ->
        {:ok, result_lists}

      :execute ->
        case next_fn.(ctx) do
          {:ok, result} ->
            merge_results(result, out_keys, interventions)

          error ->
            error
        end
    end
  end

  # ── Short-circuit Decision ──

  defp maybe_short_circuit(out_keys, interventions) do
    # TODO: Combine with OrchidIntervention.Storage
    # if cache match => short_circuit_related_key
    all_covered? = Enum.all?(out_keys, &Map.has_key?(interventions, &1))

    all_short_circuitable? =
      all_covered? and
        Enum.all?(interventions, fn {_key, {type, _val}} ->
          Operate.resolve_module(type).short_circuit?()
        end)

    if all_short_circuitable? do
      result_list =
        Enum.map(out_keys, fn key ->
          {type, payload} = Map.fetch!(interventions, key)
          mod = Operate.resolve_module(type)
          resolved = Resolver.resolve(payload)

          case mod.merge(nil, Orchid.Param.get_payload(resolved)) do
            {:ok, merged_payload} ->
              # Make sure key is overrided
              %{resolved | payload: merged_payload, name: key}

            {:error, reason} ->
              throw({:intervention_merge_error, key, reason})
          end
        end)

      {:short_circuit, result_list}
    else
      :execute
    end
  catch
    {:intervention_merge_error, key, reason} ->
      {:error, {:intervention_failed, key, reason}}
  end

  # ── Post-execution Merge ──

  defp merge_results(result, out_keys, interventions) do
    result_map = normalize_result_to_map(result, out_keys)

    merged_result =
      Enum.reduce_while(out_keys, {:ok, []}, fn key, {:ok, acc} ->
        param = Map.fetch!(result_map, key)

        case Map.get(interventions, key) do
          nil ->
            {:cont, {:ok, [param | acc]}}

          {type, intervention_payload} ->
            mod = Operate.resolve_module(type)
            resolved = Resolver.resolve(intervention_payload)

            case mod.merge(Orchid.Param.get_payload(param), Orchid.Param.get_payload(resolved)) do
              {:ok, merged_payload} ->
                {:cont, {:ok, [%{param | payload: merged_payload} | acc]}}

              {:error, reason} ->
                {:halt, {:error, {:intervention_failed, key, reason}}}
            end
        end
      end)

    case merged_result do
      {:ok, maybe_list} ->
        # Order doesn't matter.
        # Only need ensure the name and param's relationship.
        {:ok, maybe_list |> format_output()}

      error ->
        error
    end
  end

  # ── Helpers ──

  defp extract_step_interventions(out_keys, all_interventions) do
    keys = Orchid.Step.ID.normalize_keys_to_set(out_keys) |> MapSet.to_list()
    Map.take(all_interventions, keys)
  end

  defp normalize_out_keys(out_keys) do
    Orchid.Step.ID.normalize_keys_to_set(out_keys) |> MapSet.to_list()
  end

  defp normalize_result_to_map(%Orchid.Param{} = p, [key]) when is_atom(key) or is_binary(key), do: normalize_result_to_map(p, key)

  defp normalize_result_to_map(params, out_keys) when is_list(params) do
    Enum.zip(out_keys, params) |> Map.new()
  end

  defp normalize_result_to_map(%{} = map, _out_keys), do: map

  defp format_output([single_param]), do: single_param
  defp format_output(multiple_params) when is_list(multiple_params), do: multiple_params
end
