defmodule X3m.System.AggregateGroup do
  use Supervisor
  alias X3m.System.{AggregatePidFacade, AggregatePidManager}

  def start_link(prefix, aggregate_mod),
    do: Supervisor.start_link(__MODULE__, {prefix, aggregate_mod}, name: name(aggregate_mod))

  def init({prefix, aggregate_mod}) do
    children = [
      supervisor(AggregatePidManager, [prefix, aggregate_mod]),
      worker(AggregatePidFacade, [aggregate_mod])
    ]

    supervise(children, strategy: :one_for_one)
  end

  def name(aggregate_mod),
    do: Module.concat(aggregate_mod, Group)
end