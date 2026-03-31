defmodule Orchid.Operon.ApplyInputs do
  @moduledoc """
  Operon middleware that injects `:input`-typed interventions as initial parameters.  

  Only keys that are **not produced by any step** in the DAG are eligible.  
  This mirrors how a user would pass `inputs` to `Orchid.run/3`, but sourced  
  from the intervention map instead.  

  Explicit `initial_params` passed by the caller take precedence over  
  injected interventions (interventions fill gaps, they don't overwrite).  
  """
  @behaviour Orchid.Operon

  @impl true
  def call(request, next_func) do
    interventions =
      Orchid.WorkflowCtx.get_baggage(request.workflow_ctx, :interventions, %{})

    input_interventions = filter_input_interventions(request.recipe.steps, interventions)

    if map_size(input_interventions) == 0 do
      next_func.(request)
    else
      injected_params =
        Map.new(input_interventions, fn {key, {:input, payload}} ->
          {key, OrchidIntervention.Resolver.resolve(payload)}
        end)

      existing_params = normalize_initial_params(request.initial_params)

      # Explicit params win over injected ones  
      merged = Map.merge(injected_params, existing_params)

      next_func.(%{request | initial_params: merged})
    end
  end

  defp filter_input_interventions(steps, interventions) do
    produced_keys =
      steps
      |> Enum.flat_map(fn step ->
        {_, _, out_keys, _} = Orchid.Step.ensure_full_step(step)
        Orchid.Step.ID.normalize_keys_to_set(out_keys) |> MapSet.to_list()
      end)
      |> MapSet.new()

    interventions
    |> Enum.filter(fn
      {key, {:input, _val}} ->
        key
        |> Orchid.Step.ID.normalize_keys_to_set()
        |> MapSet.disjoint?(produced_keys)

      _ ->
        false
    end)
    |> Map.new()
  end

  defp normalize_initial_params(nil), do: %{}
  defp normalize_initial_params([]), do: %{}
  defp normalize_initial_params(%Orchid.Param{} = p), do: %{p.name => p}

  defp normalize_initial_params(list) when is_list(list) do
    Map.new(list, fn p -> {p.name, p} end)
  end

  defp normalize_initial_params(%{} = map), do: map
end
