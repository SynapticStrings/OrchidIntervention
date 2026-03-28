defmodule Orchid.Operon.ApplyInputs do
  @behaviour Orchid.Operon

  @impl true
  @spec call(Orchid.Operon.Request.t(), (any() -> any())) :: any()
  def call(request, next_func) do
    interventions = Orchid.WorkflowCtx.get_baggage(request.workflow_ctx, :interventions, %{})
    initial_input_interventions = filter_initial_inputs(request.recipe.steps, interventions)

    if map_size(initial_input_interventions) == 0 do
      next_func.(request)
    else
      injected_params =
        initial_input_interventions
        |> Enum.map(fn {key, spec} ->
          case Map.get(spec, :input) do
            nil ->
              nil

            thunk when is_function(thunk, 0) ->
              # value = Intervention.eval_thunk(thunk)
              # hydrated = BlobStorage.hydrate(value)
              ensure_param(thunk.(), key)

            %Orchid.Param{} = p ->
              p
          end
        end)
        |> Enum.reject(&is_nil/1)
        |> Enum.map(fn p -> {p.name, p} end)
        |> Enum.into(%{})

      # Resolve partial inputs
      # request.inital_params

      # After Orchid updated, I'll correct it
      next_func.(%{request | inital_params: injected_params})
    end
  end

  defp ensure_param(value, key, type \\ :raw)
  defp ensure_param(%Orchid.Param{} = p, _key, _type), do: p
  defp ensure_param(value, key, type), do: Orchid.Param.new(key, type, value)

  defp filter_initial_inputs(steps, interventions) do
    produced_keys =
      steps
      |> Enum.flat_map(fn step ->
        {_, _, out_keys, _} = Orchid.Step.ensure_full_step(step)
        Orchid.Step.ID.normalize_keys_to_set(out_keys) |> MapSet.to_list()
      end)
      |> MapSet.new()

    # Only saved the keys that non-produced as inputs
    interventions
    |> Enum.filter(fn {key, _spec} ->
      normalized_key = Orchid.Step.ID.normalize_keys_to_set(key)
      MapSet.disjoint?(normalized_key, produced_keys)
    end)
    |> Enum.reject(fn {_key, spec} ->
      case spec do
        %{} -> not Map.has_key?(spec, :input)
        {:input, _} -> true
        _ -> false
      end
    end)
    |> Map.new()
  end
end
