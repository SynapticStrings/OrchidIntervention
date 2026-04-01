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

  Always returns `{:ok, [Param]}` (list format).
  """
  @behaviour Orchid.Runner.Hook

  alias OrchidIntervention.{Operate, Resolver, KeyBuilder}

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
      merge_cfg = Orchid.WorkflowCtx.get_baggage(ctx.workflow_ctx, :merge_cache)

      apply_interventions(ctx, next_fn, active, merge_cfg)
    end
  end

  # ── Core Logic ──

  defp apply_interventions(ctx, next_fn, interventions, merge_cfg) do
    out_keys = normalize_out_keys(ctx.out_keys)

    case maybe_short_circuit(out_keys, interventions) do
      {:short_circuit, result_lists} ->
        {:ok, result_lists}

      :execute ->
        case next_fn.(ctx) do
          {:ok, result} ->
            merge_results(result, out_keys, interventions, merge_cfg)

          error ->
            error
        end
    end
  end

  # ── Short-circuit Decision ──

  defp maybe_short_circuit(out_keys, interventions) do
    all_covered? = Enum.all?(out_keys, &Map.has_key?(interventions, &1))

    all_short_circuitable? =
      all_covered? and
        Enum.all?(interventions, fn {_key, {type, _val}} ->
          Operate.resolve_module(type).short_circuit?()
        end)

    if all_short_circuitable? do
      result_list =
        Enum.map(out_keys, fn key ->
          {_type, param} = Map.fetch!(interventions, key)

          %{Resolver.resolve(param, false) | name: key}
        end)

      {:short_circuit, result_list}
    else
      :execute
    end
  end

  # ── Post-execution Merge ──

  defp merge_results(result, out_keys, interventions, cache_cfg) do
    result_map = normalize_result_to_map(result, out_keys)

    merged_result =
      Enum.reduce_while(out_keys, {:ok, []}, fn key, {:ok, acc} ->
        inner_param = Map.fetch!(result_map, key)

        case Map.get(interventions, key) do
          nil ->
            {:cont, {:ok, [inner_param | acc]}}

          {type, intervention_payload} ->
            mod = Operate.resolve_module(type)
            inter_param = Resolver.resolve(intervention_payload)

            case mod.data_enable() do
              {false, true} ->
                {:cont,
                 {:ok, [%{Resolver.resolve(intervention_payload, false) | name: key} | acc]}}

              {true, true} ->
                process_heavy_merge(mod, key, inner_param, inter_param, cache_cfg, acc)
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

  defp process_heavy_merge(mod, key, inner_param, inter_param, cache_cfg, acc) do
    # 1. 算 Hash
    inner_digest = KeyBuilder.get_digest(inner_param)
    inter_digest = KeyBuilder.get_digest(inter_param)
    cache_key = KeyBuilder.merge_result_key(mod, key, inner_digest, inter_digest)

    # 2. 查 Cache
    case OrchidIntervention.Storage.get(cache_cfg, cache_key) do
      {:ok, cached_payload} ->
        {:cont, {:ok, [%{inner_param | payload: cached_payload} | acc]}}

      :miss ->
        # 3. 没命中，做昂贵的数学计算
        case mod.merge(
               Orchid.Param.get_payload(inner_param),
               Orchid.Param.get_payload(inter_param)
             ) do
          {:ok, merged_payload} ->
            # 4. 回写 Cache
            OrchidIntervention.Storage.put(cache_cfg, cache_key, merged_payload)
            {:cont, {:ok, [%{inner_param | payload: merged_payload} | acc]}}

          {:error, reason} ->
            {:halt, {:error, {:intervention_failed, key, reason}}}
        end
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

  defp normalize_result_to_map(%Orchid.Param{} = p, [key]) when is_atom(key) or is_binary(key),
    do: normalize_result_to_map(p, key)

  defp normalize_result_to_map(params, out_keys) when is_list(params) do
    Enum.zip(out_keys, params) |> Map.new()
  end

  defp normalize_result_to_map(%Orchid.Param{} = p, key) when is_atom(key) or is_binary(key),
    do: %{key => p}

  defp normalize_result_to_map(%{} = map, _out_keys) when not is_struct(map), do: map

  defp format_output([single_param]), do: single_param
  defp format_output(multiple_params) when is_list(multiple_params), do: multiple_params
end
