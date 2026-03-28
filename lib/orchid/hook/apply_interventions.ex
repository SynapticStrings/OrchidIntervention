defmodule Orchid.Hook.ApplyInterventions do
  @behaviour Orchid.Runner.Hook

  alias Orchid.Runner.Context

  def call(ctx, next_fn) do
    _interventions = Orchid.WorkflowCtx.get_baggage(ctx.workflow_ctx, :interventions, %{})

    next_fn.(ctx)
  end

  def prelude(%Context{} = _ctx, _interventions) do
    # 决定最终的 OP
    # 输出均为 :override? =>
    # 跳过计算，直接输出结果 => 失败? 返回错误，因为这个 override 是用户期望介入的数据
    # 如果不是 :override （有 rawOutput + override 或是其他形式的） => 需要计算
  end

  def postlude(_result, _interventions) do
    # 这是【经过了计算后】的结果与输入的绑定
    # 主要包含几种情况：
    # partial override（模型存在数个输出，其中的一或多个需要 :override）
    # mixed calculate（模型的输出需要和 intervention 进行交互处理）
  end

  # defp resolve_nil

  # defp resolve_override

  # defp resolve_mixture
end
