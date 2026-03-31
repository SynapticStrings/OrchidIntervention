defmodule OrchidIntervention.KeyBuilder do
  @moduledoc """
  Deterministic key derivation for intervention caching.  

  Two tiers of keys:  

  1. **Intervention Key** — identifies a specific intervention datum  
     (type + target IO key + data digest). Read-only during DAG execution.  

  2. **Merge Result Key** — identifies the outcome of merging step output  
     with intervention data. Derived from the intervention key and optionally  
     the inner result key, controlled by `data_enable/0`. Read + write during  
     DAG execution.  

  ## Key Formulas  

      InterventionKey = MD5(term_to_binary({type_string, io_key_string, digest_binary}))  

      MergeResultKey  = MD5(term_to_binary(  
        [intervention_key | if use_inner? -> [inner_result_key]]  
      ))  

  MD5 is chosen deliberately: these are cache-eviction keys, not security  
  primitives. The 128-bit space is sufficient and faster than SHA-256.  
  """

  @hash_algo :md5

  @type key_type :: binary()

  @doc """
  Derives a cache key for the intervention data itself.  

  `data_digest` is domain-specific:  
  - For files: file metadata (size + mtime)  
  - For network resources: URI + last-modified / etag  
  - For in-memory data: a content hash or user-supplied fingerprint  
  """
  @spec intervention_key(OrchidIntervention.intervention_type(), Orchid.Step.io_key(), term()) ::
          key_type()
  def intervention_key(type, io_key_name, data_digest) do
    type_bin = normalize_type(type)
    key_bin = normalize_io_key(io_key_name)

    digest_bin =
      if is_binary(data_digest),
        do: data_digest,
        else: :erlang.term_to_binary(data_digest)

    :crypto.hash(@hash_algo, :erlang.term_to_binary({type_bin, key_bin, digest_bin}))
  end

  @doc """
  Derives a cache key for the merge result.  

  Uses `data_enable/0` from the Operate module to decide which components  
  participate in the key:  

  - `{false, true}` (`:override`): inner result changes don't invalidate  
  - `{true, true}` (`:offset` etc.): both sources invalidate  
  - `{true, false}`: intervention data changes don't invalidate (unusual)  
  """
  @spec merge_result_key(module(), key_type(), key_type() | nil) :: key_type()
  def merge_result_key(operate_mod, intervention_key, inner_result_key \\ nil) do
    {use_inner?, use_interv?} = operate_mod.data_enable()

    components =
      []
      |> prepend_if(use_interv?, intervention_key)
      |> prepend_if(use_inner? and not is_nil(inner_result_key), inner_result_key)

    :crypto.hash(@hash_algo, :erlang.term_to_binary(components))
  end

  # ── Internal ──  

  defp normalize_type(type) when is_atom(type), do: Atom.to_string(type)

  defp normalize_io_key(key) when is_binary(key), do: key
  defp normalize_io_key(key) when is_atom(key), do: Atom.to_string(key)
  defp normalize_io_key([key]), do: normalize_io_key(key)
  defp normalize_io_key({key}), do: normalize_io_key(key)

  defp prepend_if(list, true, value), do: [value | list]
  defp prepend_if(list, false, _value), do: list
end
