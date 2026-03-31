# OrchidIntervention

Inject, override, and short-circuit step outputs in Orchid DAGs — without touching the graph structure.

## Why

Orchid executes DAGs where steps are wired by data keys. Sometimes you need to:

- Replace a step's output with a known value (e.g., cached result, test fixture)
- Provide inputs from a source other than the caller's argument list
- Skip expensive steps entirely when their outputs are already known

Rewiring the DAG for each scenario is tedious and error-prone. **Interventions** let you declaratively alter execution results *from the outside*.

## Concepts

### Intervention Map

A map from IO keys to intervention specs:

```elixir
%{
  "beans" => {:input, Param.new("beans", :raw, 20)},
  "powder" => {:override, Param.new("powder", :solid, 25)}
}
```

Each spec is a `{type, payload}` tuple where `payload` can be a `Param.t()`, a zero-arity function, or any term that resolves to a `Param`.

### Intervention Types

| Type | Behaviour | Short-circuit |
|------|-----------|---------------|
| `:input` | Injects as initial param (via Operon) | N/A |
| `:override` | Replaces step output entirely | ✅ |
| `MyModule` | Custom merge logic (implement `OrchidIntervention.Operate`) | Configurable |

### Short-circuit

When **every** output key of a step is covered by a short-circuit-capable intervention, the step body is never executed. This is how you skip expensive computations.

## Quick Start

### Install

```elixir
# mix.exs
[
  {:orchid, "~> 0.6"},
  {:orchid_intervention, "~> 0.1"}
]
```

### Example

A coffee workflow with two steps:

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
    IO.puts("Brewing #{style} with #{p_amount}g powder and #{w_amount}ml water...")
    {:ok, Param.new("coffee", :liquid, "Cup of #{style} with #{w_amount}ml")}
  end
end

steps = [
  {Barista.Brew, ["powder", "water"], "coffee", [style: :latte]},
  {Barista.Grind, "beans", "powder"}
]
```

Now apply interventions — override `powder` to skip grinding, inject `beans` and `water` as inputs:

```elixir
interventions = %{
  "beans"  => {:input, Param.new("beans", :raw, 20)},
  "water"  => {:input, Param.new("water", :raw, 200)},
  "powder" => {:override, Param.new("powder", :solid, 25)}
}

{:ok, results} = Orchid.run(
  steps,
  [],                                        # no explicit inputs needed
  operons_stack: [Orchid.Operon.ApplyInputs],
  global_hooks_stack: [Orchid.Hook.ApplyInterventions],
  baggage: %{interventions: interventions}
)
# => Brewing latte with 25g powder and 200ml water...
# *Step Grind were short-circuited
```

`Grind` never ran — its output key `"powder"` was fully covered by an `:override` intervention.

## API Summary

| Component | Role |
|-----------|------|
| `Orchid.Hook.ApplyInterventions` | Global hook — applies non-input interventions to step outputs |
| `Orchid.Operon.ApplyInputs` | Operon — injects `:input` interventions as initial params |
| `OrchidIntervention.Operate` | Behaviour for custom intervention merge logic |
| `OrchidIntervention.Operate.Override` | Built-in: replace output, supports short-circuit |
| `OrchidIntervention.Resolver` | Resolves thunks and hydrates `{:ref, ...}` payloads |
| `OrchidIntervention.KeyBuilder` | Deterministic cache key derivation for interventions |
| `OrchidIntervention.Storage` | Two-tier cache (intervention data + merge results) |

## Custom Operate

Implement the behaviour to define your own merge semantics:

```elixir
defmodule MyApp.Operate.Offset do
  @behaviour OrchidIntervention.Operate

  @impl true
  def short_circuit?, do: false

  @impl true
  def data_enable, do: {true, true}  # both inner and intervention affect cache

  @impl true
  def merge(%Orchid.Param{payload: inner_data} = p, %Orchid.Param{payload: intervention_data}) do
    result = Enum.zip(inner_data, intervention_data, &(&1 + &2))

    {:ok, %{p | payload: result}}
  end
end

# Usage
%{"signal" => {MyApp.Operate.Offset, Param.new("signal", :number, 10)}}
```
