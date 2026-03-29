defmodule OrchidIntervention.KeyBuilder do
  # Key = Hash(InterventionType, StepKeyName, ContentDegistOrAbstract)
  # e.g. File(ContentDegistOrAbstract) => Metadata; Link => {URI, AccessTime when dynamic or Abstract}
  # For specific DAG Graph(Orchid steps), the step key should be unique

  @type key_type :: binary()

  @hash_algo :md5

  def intervention_key() do
    # ...

    :crypto.hash(@hash_algo, :erlang.term_to_binary("Any"))
  end

  # --- Helper ---

  # defp normalize_step_key(key) when is_binary(key), do: key
  # defp normalize_step_key(key) when is_atom(key), do: Atom.to_string(key)
  # defp normalize_step_key([key]), do: normalize_step_key(key)
  # defp normalize_step_key({key}), do: normalize_step_key(key)
end
