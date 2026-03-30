defmodule OrchidIntervention.KeyBuilder do
  @type key_type :: binary()

  @hash_algo :md5

  @spec intervention_key(atom(), Orchid.Step.io_key(), term()) :: key_type()
  def intervention_key(intervention_mod, io_key_name, data_digest) do
    type_bin = Atom.to_string(intervention_mod)
    key_bin = normalize_step_key(io_key_name)

    digest_bin = if is_binary(data_digest), do: data_digest, else: :erlang.term_to_binary(data_digest)

    hash_term = {type_bin, key_bin, digest_bin}

    :crypto.hash(@hash_algo, :erlang.term_to_binary(hash_term))
  end

  @spec merge_result_key(module(), key_type(), any()) :: binary()
  def merge_result_key(intervention_mod, intervention_key, inner_result_key) do
    {use_inner?, use_interv?} = intervention_mod.data_enable()

    components = []
    components = if use_interv?, do: [intervention_key | components], else: components
    components = if use_inner?, do: [inner_result_key | components], else: components

    :crypto.hash(@hash_algo, :erlang.term_to_binary(components))
  end

  # --- Helper ---

  defp normalize_step_key(key) when is_binary(key), do: key
  defp normalize_step_key(key) when is_atom(key), do: Atom.to_string(key)
  defp normalize_step_key([key]), do: normalize_step_key(key)
  defp normalize_step_key({key}), do: normalize_step_key(key)
end
