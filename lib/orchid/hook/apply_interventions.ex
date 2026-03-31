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
      interv_cfg = Orchid.WorkflowCtx.get_baggage(ctx.workflow_ctx, :interv_cache)
      merge_cfg = Orchid.WorkflowCtx.get_baggage(ctx.workflow_ctx, :merge_cache)

      apply_interventions(ctx, next_fn, active, {interv_cfg, merge_cfg})
    end
  end

  # ── Core Logic ──

  defp apply_interventions(ctx, next_fn, interventions, {interv_cfg, merge_cfg}) do
    out_keys = normalize_out_keys(ctx.out_keys)

    case maybe_short_circuit(out_keys, interventions, interv_cfg) do
      {:short_circuit, result_lists} ->
        {:ok, result_lists}

      :execute ->
        case next_fn.(ctx) do
          {:ok, result} ->
            merge_results(result, out_keys, interventions, {interv_cfg, merge_cfg})

          error ->
            error
        end
    end
  end

  # ── Short-circuit Decision ──

  defp maybe_short_circuit(out_keys, interventions, interv_cfg) do
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
          resolved_param = Resolver.resolve(payload)

          maybe_put_interv_cache(interv_cfg, type, key, resolved_param)

          case mod.merge(nil, Orchid.Param.get_payload(resolved_param)) do
            {:ok, merged_payload} ->
              # Make sure key is overrided
              %{resolved_param | payload: merged_payload, name: key}

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

  defp merge_results(result, out_keys, interventions, {interv_cfg, merge_cfg}) do
    result_map = normalize_result_to_map(result, out_keys)

    merged_result =
      Enum.reduce_while(out_keys, {:ok, []}, fn key, {:ok, acc} ->
        inner_param = Map.fetch!(result_map, key)

        with {type, intervention_payload} <- Map.get(interventions, key),
             mod = Operate.resolve_module(type),
             inter_param = Resolver.resolve(intervention_payload),
             :miss <- try_cache_lookup(merge_cfg, mod, key, inner_param, inter_param),
             {:ok, merged_payload} <-
               mod.merge(
                 Orchid.Param.get_payload(inner_param),
                 Orchid.Param.get_payload(inter_param)
               ) do
          maybe_put_caches(
            {interv_cfg, merge_cfg},
            mod,
            key,
            inner_param,
            inter_param,
            merged_payload
          )

          {:cont, {:ok, [%{inner_param | payload: merged_payload} | acc]}}
        else
          nil ->
            {:cont, {:ok, [inner_param | acc]}}

          {:ok, cached_payload} ->
            {:cont, {:ok, [%{inner_param | payload: cached_payload} | acc]}}

          {:error, reason} ->
            {:halt, {:error, {:intervention_failed, key, reason}}}
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

  defp try_cache_lookup(nil, _mod, _key, _inner, _inter), do: :miss

  defp try_cache_lookup(merge_cfg, mod, key, inner, inter) do
    case mod.data_enable() do
      {true, true} ->
        i_key = OrchidIntervention.KeyBuilder.intervention_key(mod, key, get_digest(inter))
        inner_key = get_digest(inner)
        OrchidIntervention.Storage.get_merge_result(merge_cfg, mod, i_key, inner_key)

      {false, true} ->
        # True is inter side
        inter
    end
  end

  defp maybe_put_caches({interv, merge}, mod, key, inner, inter, result_payload) do
    maybe_put_interv_cache(interv, mod, key, inter)

    if merge && mod.data_enable() == {true, true} do
      i_key = OrchidIntervention.KeyBuilder.intervention_key(mod, key, get_digest(inter))
      inner_key = get_digest(inner)
      OrchidIntervention.Storage.put_merge_result(merge, mod, i_key, inner_key, result_payload)
    end

    :ok
  end

  defp maybe_put_interv_cache(nil, _mod, _key, _inter), do: :ok

  defp maybe_put_interv_cache(cfg, mod, key, inter) do
    digest = get_digest(inter)

    OrchidIntervention.Storage.put_intervention(
      cfg,
      mod,
      key,
      digest,
      Orchid.Param.get_payload(inter)
    )
  end

  defp get_digest(%Orchid.Param{metadata: %{cache_key: key}}) when is_binary(key), do: key

  defp get_digest(%Orchid.Param{payload: payload}) do
    :crypto.hash(:md5, :erlang.term_to_binary(payload))
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

  defp normalize_result_to_map(%{} = map, _out_keys), do: map

  defp format_output([single_param]), do: single_param
  defp format_output(multiple_params) when is_list(multiple_params), do: multiple_params
end
