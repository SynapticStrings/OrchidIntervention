defmodule Orchid.Hook.ApplyInterventions do
  @behaviour Orchid.Runner.Hook

  alias Orchid.Runner.Context

  def call(ctx, next_fn) do
    _interventions = Orchid.WorkflowCtx.get_baggage(ctx.workflow_ctx, :interventions, %{})

    next_fn.(ctx)
  end

  def prelude(%Context{} = _ctx, _interventions) do
    # Determine the final OP
    # All outputs are :override? =>
    # Skip the calculation and output the result directly => Failure? Return an error because this override is the data the user expects to intervene in.
    # If it is not :override (with rawOutput + override or other forms) => Calculation is required.
  end

  def postlude(_result, _interventions) do
    # This is the binding of the calculated result to the input.
    # This mainly includes several cases:
    # Partial override (The model has several outputs, one or more of which need to be overridden)
    # Mixed calculation (The model's output needs to interact with the intervention)
  end

  # defp resolve_nil

  # defp resolve_override

  # defp resolve_mixture
end
