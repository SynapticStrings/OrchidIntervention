defmodule OrchidInterventionTest do
  use ExUnit.Case
  doctest OrchidIntervention

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
  end
end
