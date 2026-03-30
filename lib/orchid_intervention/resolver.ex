defmodule OrchidIntervention.Resolver do
  @spec resolve(OrchidIntervention.payload()) :: Orchid.Param.t() | no_return()
  def resolve(thunk_or_value) do
    val = if is_function(thunk_or_value, 0), do: thunk_or_value.(), else: thunk_or_value

    unpack_ref_payload(val)
  end

  defp unpack_ref_payload(%Orchid.Param{payload: {:ref, repo_conf, key}} = p) do
    case Orchid.Repo.dispatch_store(repo_conf, :get, [key]) do
      {:ok, raw_data} ->
        %{p | payload: raw_data}

      :miss ->
        raise "Intervention hydration failed! Key #{inspect(key)} missing in Repo<#{repo_conf}>."
    end
  end

  defp unpack_ref_payload(res), do: res
end
