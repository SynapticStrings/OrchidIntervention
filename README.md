# OrchidIntervention

Result = DAG + Intervention.

## 1. Background & Motivation
In the [Orchid](https://hex.pm/packages/orchid) workflow engine (and its overarching Quincunx scheduling layer), we frequently need to inject external data or apply user-driven interventions (e.g., overriding a step's output, tweaking a tensor with a mask, or supplying massive static payloads like audio files). 

Modifying the physical DAG (Directed Acyclic Graph) by inserting "dummy DataProvider nodes" during compilation pollutes the graph and complicates the compiler. 

**The Solution:** Use **Late Binding via Orchid's Hook system**. By pushing data intervention and input injection to the runtime Hook layer, we keep the underlying Recipe pure and leverage lazy evaluation.

## 2. Core Architectural Decisions

### A. Separation of Concerns (Intervention vs. Stratum)
*   **`OrchidStratum` (The Memory):** A passive layer. It hashes inputs to find cached outputs, or executes and records them. 
*   **`OrchidIntervention` (The Surgeon):** An active layer. It intercepts the `Orchid.Runner.Context` to force-feed specific inputs, short-circuit execution with overrides, or apply mathematical modifiers to outputs.
*   *Separation Rule:* Interventional constants (user tweaks) **do not** enter the `MetaStorage` cache to avoid polluting the hash space, but they **can** reside in `BlobStorage`.

### B. Storage Synergy & Free Hydration
If an external intervention payload is massive (e.g., a 50MB audio buffer), Quincunx/DataProvider will preemptively sink it into `OrchidStratum.BlobStorage` and pass a lightweight reference: `{:ref, blob_store, hash}` into the Intervention Baggage.
*   **The Magic:** When `OrchidIntervention.Hook` injects this `{:ref, ...}` into `ctx.inputs` and passes it down, `OrchidStratum.BypassHook` will **automatically hydrate** (fetch the raw blob) before the actual Step executes. No redundant storage logic is needed in the Intervention layer.

### C. Lazy Evaluation (Thunks)
Data sources might be remote RPCs, file reads, or frontend state. To prevent blocking the compiler, interventions are passed as thunks (`fn -> fetch_data() end`). They are evaluated precisely at the microsecond the specific Step is reached.

---

## 3. The Hook Pipeline (The Onion Model)

By stacking hooks, we create an elegant data execution pipeline: 
$Result = Intervene_{post}(Stratum_{cache}(Intervene_{pre}(Step)))$

1.  **Global Level Hook (Pre-Graph-Check): Initial Inputs Injection**
    *   *Concept:* Orchid has an outer hook layer that runs before graph integrity validation. We can use this to resolve dynamic/remote "Workflow Inputs" and inject them into the initial payload, cleanly separating Data Provisioning from Orchid's core execution.
2.  **Step Level Hook - Shell 1: `OrchidIntervention.Hook`**
    *   Reads `baggage[:interventions]`.
    *   *Condition Override:* If an output intervention exists, evaluate the thunk, return the value, and **short-circuit** the workflow (bypassing Stratum and the Step entirely).
    *   *Condition Input:* If an input intervention exists, evaluate it, mutate `ctx.inputs`, and call `next_fn`. 
3.  **Step Level Hook - Shell 2: `OrchidStratum.BypassHook`**
    *   Receives the formally mutated inputs. Computes the $StepKey$.
    *   Either serves a Cache Hit or calls `next_fn`.
    *   Dehydrates outputs and updates `MetaStorage`.
4.  **Core Step Execution:** 
    *   Ignorant of the layers above, just executes pure logic.
5.  **Post-Execution (Unwinding the Onion):**
    *   When the result bubbles back up to `OrchidIntervention.Hook`, handle `Modifier` interventions (e.g., applying a mathematical offset or mask to the raw outputs) before returning the final result to the Blackboard.

## 4. Intervention Typology API Draft

Interventions are mapped by output/input keys using deterministic atoms:

```elixir
@type intervention_type :: :input | :override | :offset | :mask | :scale
@type value_thunk :: raw_data() | (-> raw_data())

@type intervention_map :: %{
  Orchid.Step.io_key() => %{intervention_type() => value_thunk()}
}
```

## 5. Usecase

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
}

{:ok, result} = Orchid.run(
  recipe,
  [],  # It doesn't required inputs anymore.
  operons_stack: [Orchid.Operon.ApplyInputs],
  global_hooks_stack: [Orchid.Hook.ApplyInterventions],
  baggage: %{interventions: interventions}
)
```
