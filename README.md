# OrchidIntervention

Result = DAG + Intervention.

## Quick Start

### Install

```elixir
[
  {:orchid, "~> 0.6"},
  {:orchid_intervention, "~> 0.1"}
]
```

### Usecase

We use some example in Orchid:

```elixir
defmodule Barista.Grind do
  use Orchid.Step
  alias Orchid.Param

  def run(beans, opts) do
    amount = Param.get_payload(beans)
    IO.puts("Grinding #{amount}g beans...")
    {:ok, Param.new("powder", :solid, amount * Keyword.get(opts, :ratio, 1))}
  end
end

defmodule Barista.Brew do
  use Orchid.Step
  alias Orchid.Param

  def run([powder, water], opts) do
    style = Keyword.get(opts, :style, :espresso)
    
    p_amount = Param.get_payload(powder)
    w_amount = Param.get_payload(water)
    
    IO.puts("Brewing #{style} coffee with #{p_amount}g powder and #{w_amount}ml water...")
    {:ok, Param.new("coffee", :liquid, "Cup of #{style} with #{w_amount}ml")}
  end
end

steps = [
  {Barista.Brew, ["powder", "water"], "coffee", [style: :latte]},
  {Barista.Grind, "beans", "powder"}
]
```

And then:

```elixir
interventions = %{
  "beans" => {:input, Param.new("beans", :raw, 20)},
  "water" => {:input, Param.new("water", :raw, 200)},
  "powder" => {:override, Param.new("powder", :solid, 25)}
}

{:ok, results} = Orchid.run(
  steps,
  [],  # It doesn't required inputs anymore.
  operons_stack: [Orchid.Operon.ApplyInputs],
  global_hooks_stack: [Orchid.Hook.ApplyInterventions],
  baggage: %{interventions: interventions}
)
# => Brewing latte coffee with 25g powder and 200ml water... 
# *Step Grind were short-circuited
```
