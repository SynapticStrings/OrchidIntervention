defmodule OrchidIntervention.Resolver do
  @spec resolve(OrchidIntervention.payload()) :: Orchid.Param.payload() | no_return()
  def resolve(thunk_or_value) do
    # 1. Lazy Evaluation (Thunk)
    val = if is_function(thunk_or_value, 0), do: thunk_or_value.(), else: thunk_or_value

    # 2. Hydration from Repo
    case val do
      {:ref, repo_conf, key} ->
        unpack_ref_payload({:ref, repo_conf, key})

      %Orchid.Param{} = p ->
        p.payload

      raw_data ->
        raw_data
    end
  end

  defp unpack_ref_payload({:ref, repo_conf, key}) do
    case Orchid.Repo.dispatch_store(repo_conf, :get, [key]) do
          {:ok, raw_data} ->
            raw_data

          :miss ->
            raise "Intervention hydration failed! Key #{inspect(key)} missing in Repo."
        end
  end

  # defp unpack_ref_payload(res), do: res
end
