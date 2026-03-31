defmodule OrchidIntervention.Resolver do
  @moduledoc "A helper to resolve orchid param."

  @spec resolve(OrchidIntervention.payload(), boolean()) :: Orchid.Param.t() | no_return()
  def resolve(thunk_or_value, hydrate? \\ true) do
    val = if is_function(thunk_or_value, 0), do: thunk_or_value.(), else: thunk_or_value

    if hydrate? do
      hydrate_if_ref(val)
    else
      val
    end
  end

  defp hydrate_if_ref(%Orchid.Param{payload: {:ref, repo_conf, key}} = param) do
    case Orchid.Repo.dispatch_store(repo_conf, :get, [key]) do
      {:ok, raw_data} ->
        %{param | payload: raw_data}

      :miss ->
        raise "Intervention hydration failed: key #{inspect(key)} missing in #{inspect(repo_conf)}"
    end
  end

  defp hydrate_if_ref(val), do: val
end
