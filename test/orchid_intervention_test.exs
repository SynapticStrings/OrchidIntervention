defmodule OrchidInterventionTest.ConcatOp do
  @moduledoc false
  @behaviour OrchidIntervention.Operate

  @impl true
  def data_enable, do: {true, true}

  @impl true
  def merge(inner, intervention), do: {:ok, inner <> intervention}
end

defmodule OrchidInterventionTest do
  use ExUnit.Case
  doctest OrchidIntervention

  alias OrchidInterventionTest.ConcatOp
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

  setup do
    :telemetry.attach(
      "orchid-step-exception-logger",
      [:orchid, :step, :exception],
      &Orchid.Runner.Hooks.Telemetry.error_handler/4,
      %{}
    )

    :ok
  end

  describe "input will be repalced" do
    test "all inputs from intervention" do
      steps = [
        {S.DummyStep1, "in1", "out1"},
        {S.DummyStep2, "in2", "out2"}
      ]

      interventions = %{
        "in1" => {:input, Orchid.Param.new("in1", :binary, "In1")},
        "in2" => {:input, Orchid.Param.new("in1", :binary, "In2")},
        # Will be ignored
        "out3" => {:override, "Foo"}
      }

      {:ok, results1} =
        Orchid.run(
          steps,
          nil,
          operons_stack: [Orchid.Operon.ApplyInputs],
          baggage: %{interventions: interventions}
        )

      assert results1["out2"].payload == "In2 -> DummyStep2"

      Orchid.run(
        steps,
        [],
        operons_stack: [Orchid.Operon.ApplyInputs],
        baggage: %{interventions: interventions}
      )
    end

    test "partial inputs from intervention" do
      steps = [
        {S.DummyStep1, "in1", "out1"},
        {S.DummyStep2, "in2", "out2"}
      ]

      interventions = %{
        "in2" => {:input, Orchid.Param.new("in1", :binary, "In2")}
      }

      {:ok, results} =
        Orchid.run(
          steps,
          [Orchid.Param.new("in1", :binary, "In1")],
          operons_stack: [Orchid.Operon.ApplyInputs],
          baggage: %{interventions: interventions}
        )

      assert results["out1"].payload == "In1 -> DummyStep1"
    end

    test "no intervention will execute normally" do
      steps = [{S.DummyStep1, "in1", "out1"}]

      {:ok, results} =
        Orchid.run(
          steps,
          Orchid.Param.new("in1", :binary, "In1"),
          operons_stack: [Orchid.Operon.ApplyInputs]
        )

      assert results["out1"].payload == "In1 -> DummyStep1"
    end
  end

  describe "override is the default behaviour" do
    test "override can change data" do
      graph = complex_graph()
      input = Orchid.Param.new("entry", :binary, "Entry")

      interventions = %{
        # Inject as partial
        "f3" => {:override, Orchid.Param.new("non-F3", :binary, "FIII")},
        "f2out" => {:override, Orchid.Param.new("f3", :binary, "F2OUT")}
      }

      {:ok, results} =
        Orchid.run(graph, input,
          global_hooks_stack: [Orchid.Hook.ApplyInterventions],
          baggage: %{interventions: interventions}
        )

      assert results["f3"].payload == "FIII"
      assert String.contains?(results["merged1"].payload, "F2OUT")
    end

    test "partial intervention: 3 outputs, 2 overridden, 1 passes through" do
      steps = [{S.FanoutStep, "entry", ["f1", "f2", "f3"]}]
      input = Orchid.Param.new("entry", :binary, "Entry")

      interventions = %{
        "f1" => {:override, Orchid.Param.new("f1", :binary, "OVER_F1")},
        "f3" => {:override, Orchid.Param.new("f3", :binary, "OVER_F3")}
        # f2 intentionally left out — should pass through unchanged
      }

      {:ok, results} =
        Orchid.run(steps, input,
          global_hooks_stack: [Orchid.Hook.ApplyInterventions],
          baggage: %{interventions: interventions}
        )

      # f1 and f3 replaced by intervention
      assert results["f1"].payload == "OVER_F1"
      assert results["f3"].payload == "OVER_F3"

      # f2: no intervention → original step output passes through
      assert results["f2"].payload == "Fanout(Entry)_2"
    end

    test "heavy merge on a multi-output step receives the matching inner output" do
      # Regression: `normalize_result_to_map/2` used to zip out_keys
      # (MapSet-normalized, order destroyed) with the positional result
      # list, mis-pairing inner data whenever the two orders differed.
      # ":override" never noticed — it discards the inner value. Out
      # keys here are chosen so set order ("a2" < "z1") differs from
      # declaration order.
      steps = [{S.FanoutStep, "entry", ["z1", "a2"]}]
      input = Orchid.Param.new("entry", :binary, "Entry")

      interventions = %{
        "a2" => {ConcatOp, Orchid.Param.new("a2", :binary, "+X")}
      }

      {:ok, results} =
        Orchid.run(steps, input,
          global_hooks_stack: [Orchid.Hook.ApplyInterventions],
          baggage: %{interventions: interventions}
        )

      # The merge must see a2's own output, not z1's.
      assert results["a2"].payload == "Fanout(Entry)_2+X"
      assert results["z1"].payload == "Fanout(Entry)_1"
    end
  end
end
