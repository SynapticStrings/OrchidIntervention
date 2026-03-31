defmodule OrchidInterventionTest.OrchidSteps do
  defmodule DummyStep1 do
    use Orchid.Step

    def run(%Orchid.Param{payload: input}, _opts) do
      {:ok, Orchid.Param.new(:dummy1, :binary, input <> " -> DummyStep1")}
    end
  end

  defmodule DummyStep2 do
    use Orchid.Step

    def run(%Orchid.Param{payload: input}, _opts) do
      {:ok, Orchid.Param.new(:dummy2, :binary, input <> " -> DummyStep2")}
    end
  end

  defmodule FaninStep do
    use Orchid.Step

    def run([%Orchid.Param{payload: input1}, %Orchid.Param{payload: input2}], _opts) do
      {:ok, Orchid.Param.new(:merged, :binary, "Merge<#{input1}, #{input2}>")}
    end
  end

  defmodule FanoutStep do
    use Orchid.Step

    def run(%Orchid.Param{payload: input}, _opts) do
      {:ok,
       [
         Orchid.Param.new(:out1, :binary, "Fanout(" <> input <> ")_1"),
         Orchid.Param.new(:out1, :binary, "Fanout(" <> input <> ")_2"),
         Orchid.Param.new(:out1, :binary, "Fanout(" <> input <> ")_3")
       ]}
    end
  end
end
