defmodule OrchidInterventionStorageTest do
  use ExUnit.Case

  alias OrchidInterventionTest.OrchidSteps, as: S

  defp complex_graph do
    [
      {S.FanoutStep, "entry", ["f1", "f2", "f3"]},
      {S.DummyStep1, "f1", "f1out"},
      {S.DummyStep2, "f2", "f2out"},
      {S.FaninStep, ["f1out", "f2out"], "merged1"},
      {S.FaninStep, ["f3", "merged1"], "fin"}
    ]
  end

  defmodule InterventionStorage do
    @behaviour Orchid.Repo
    @behaviour Orchid.Repo.ContentAddressable

    def init, do: :ets.new(__MODULE__, [:set, :public])

    @impl true
    def get(ets_ref, key) do
      case :ets.lookup(ets_ref, key) do
        [{^key, val}] -> {:ok, val}
        [] -> :miss
      end
    end

    @impl true
    def put(ets_ref, key, val) do
      :ets.insert(ets_ref, {key, val})

      :ok
    end

    @impl true
    def exists?(ets_ref, key) do
      :ets.member(ets_ref, key)
    end
  end

  defmodule HeavyMergeOp do
    @behaviour OrchidIntervention.Operate
    def short_circuit?, do: false
    def data_enable, do: {true, true}

    def merge(inner_data, intervention_data) do
      {:ok, inner_data <> " | Merged with: " <> intervention_data}
    end
  end

  setup do
    :telemetry.attach(
      "orchid-step-exception-logger",
      [:orchid, :step, :exception],
      &Orchid.Runner.Hooks.Telemetry.error_handler/4,
      %{}
    )

    :ok
  end

  defmodule FetchBlobAndMerge do
    def call(store_conf, key) do
      {:ok, payload} = Orchid.Repo.dispatch_store(store_conf, :get, [key])

      Orchid.Param.new("f3", :binary, payload)
    end
  end

  describe "outside can inject interventions via storage" do
    test "hydrates :ref payload using Resolver successfully" do
      ets = InterventionStorage.init()
      repo_conf = {InterventionStorage, ets}

      InterventionStorage.put(ets, "secret_key", "secret_value")

      # 通过 thunk 函数和直接传值分别测试 Resolver
      param_direct = Orchid.Param.new("f1", :binary, {:ref, repo_conf, "secret_key"})
      param_thunk = fn -> Orchid.Param.new("f2", :binary, {:ref, repo_conf, "secret_key"}) end
      param_mfa = {FetchBlobAndMerge, :call, [repo_conf, "secret_key"]}

      assert %Orchid.Param{payload: "secret_value"} =
               OrchidIntervention.Resolver.resolve(param_direct)

      assert %Orchid.Param{payload: "secret_value"} =
               OrchidIntervention.Resolver.resolve(param_thunk)

      assert %Orchid.Param{payload: "secret_value"} =
               OrchidIntervention.Resolver.resolve(param_mfa)
    end

    test "raises error when hydration fails due to cache miss" do
      ets = InterventionStorage.init()
      repo_conf = {InterventionStorage, ets}

      param = Orchid.Param.new("f1", :binary, {:ref, repo_conf, "missing_key"})

      assert_raise RuntimeError, ~r/Intervention hydration failed/, fn ->
        OrchidIntervention.Resolver.resolve(param)
      end
    end
  end

  describe "storage's data can be fetched within Orchid.Repo" do
    test "heavy merge utilizes cache properly (process_heavy_merge)" do
      ets = InterventionStorage.init()
      repo_conf = {InterventionStorage, ets}

      interventions = %{
        "f1out" => {HeavyMergeOp, Orchid.Param.new("f1out", :binary, "HeavyData")}
      }

      run_opts = [
        operons_stack: [Orchid.Operon.ApplyInputs],
        global_hooks_stack: [Orchid.Hook.ApplyInterventions],
        baggage: %{interventions: interventions, merge_cache: repo_conf}
      ]

      # First run (Cache Miss -> Computes and Puts to Cache)
      {:ok, res1} =
        Orchid.run(
          complex_graph(),
          [Orchid.Param.new("entry", :binary, "START")],
          run_opts
        )

      # 验证结果被修改
      {_, f1out_param} = Enum.find(res1, fn {k, _} -> k == "f1out" end)
      assert f1out_param.payload =~ "HeavyData"

      # 验证 Cache 中已存入数据
      assert :ets.info(ets, :size) > 0

      # Second run (Cache Hit -> Fetches directly from Cache)
      {:ok, res2} =
        Orchid.run(
          complex_graph(),
          [Orchid.Param.new("entry", :binary, "START")],
          run_opts
        )

      # 结果应该和第一次完全一致
      assert res1 == res2
    end
  end

  describe "KeyBuilder and pure utilities coverage" do
    test "KeyBuilder normalizes inputs properly" do
      alias OrchidIntervention.KeyBuilder

      # get_digest
      assert "custom_hash" ==
               KeyBuilder.get_digest(%Orchid.Param{metadata: %{cache_key: "custom_hash"}})

      assert is_binary(KeyBuilder.get_digest(%Orchid.Param{payload: "actual_data"}))

      # intervention_key combinations
      k1 = KeyBuilder.intervention_key(:override, "k_str", "digest_str")
      k2 = KeyBuilder.intervention_key(DummyOverrideModule, :k_atom, %{complex: "term"})
      k3 = KeyBuilder.intervention_key(:override, ["k_list"], "digest")
      k4 = KeyBuilder.intervention_key(:override, {"k_tuple"}, "digest")

      assert is_binary(k1) and is_binary(k2) and is_binary(k3) and is_binary(k4)

      # merge_result_key prepends conditionally based on `data_enable`
      # Override is {false, true}
      res_key_override =
        KeyBuilder.merge_result_key(OrchidIntervention.Operate.Override, "k", k1, "inner_k")

      assert is_binary(res_key_override)

      # HeavyMergeOp is {true, true}
      res_key_heavy = KeyBuilder.merge_result_key(HeavyMergeOp, "k", k1, "inner_k")
      assert is_binary(res_key_heavy)
    end

    test "Storage fallback behavior when conf is nil" do
      alias OrchidIntervention.Storage

      assert :miss == Storage.get(nil, "any_key")
      assert :ok == Storage.put(nil, "any_key", "any_val")
    end

    test "OrchidIntervention core helpers" do
      interventions = %{
        "in_key" => {:input, "val1"},
        "ov_key" => {:override, "val2"}
      }

      assert %{"in_key" => {:input, "val1"}} ==
               OrchidIntervention.filter_by_type(interventions, :input)

      assert {:input, "val1"} == OrchidIntervention.get(interventions, "in_key")
      assert nil == OrchidIntervention.get(interventions, "non_existent")

      assert true == OrchidIntervention.operon_type?(:input)
      assert false == OrchidIntervention.operon_type?(:override)
      assert false == OrchidIntervention.operon_type?(HeavyMergeOp)
    end

    test "OrchidIntervention.Operate.Override callbacks" do
      alias OrchidIntervention.Operate.Override

      assert Override.short_circuit?() == true
      assert Override.data_enable() == {false, true}
      assert {:ok, "inter"} == Override.merge("inner", "inter")
    end
  end
end
