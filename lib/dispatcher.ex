defmodule X3m.System.Dispatcher do
  alias X3m.System.{Message, Response, Instrumenter, ServiceRegistry}

  def dispatch(%Message{halted?: true} = message), do: message

  def dispatch(%Message{} = message, opts \\ []) do
    timeout = Keyword.get(opts, :timeout, 5_000)
    mono_start = System.monotonic_time()

    Instrumenter.execute(
      :discovering_service,
      %{start: DateTime.utc_now(), mono_start: mono_start},
      %{message: message, caller_node: Node.self()}
    )

    case discover_service(message) do
      {:unavailable, message} ->
        Instrumenter.execute(
          :service_not_found,
          %{time: DateTime.utc_now(), duration: Instrumenter.duration(mono_start)},
          %{message: message, caller_node: Node.self()}
        )

        _unavailable(message)

      {node, mod} ->
        Instrumenter.execute(
          :service_found,
          %{time: DateTime.utc_now(), duration: Instrumenter.duration(mono_start)},
          %{message: message, caller_node: Node.self(), service_node: node}
        )

        _dispatch(node, mod, message, timeout)
    end
  end

  @spec discover_service(Message.t()) :: {:unavailable, Message.t()} | {node | :local, atom}
  def discover_service(%Message{service_name: service} = message) do
    case ServiceRegistry.find_nodes_with_service(service) do
      :not_found -> {:unavailable, message}
      {:local, {mod, _fun}} -> {:local, mod}
      {:remote, nodes} -> Enum.random(nodes)
    end
  end

  defp _dispatch(:local, mod, %Message{} = message, timeout) do
    :ok = apply(mod, message.service_name, [message])
    _wait_for_response(message, timeout)
  end

  defp _dispatch(node, mod, %Message{} = message, timeout) do
    :ok = :rpc.call(node, mod, message.service_name, [message])
    _wait_for_response(message, timeout)
  end

  defp _wait_for_response(message, timeout) do
    receive do
      %Message{} = message -> message
    after
      timeout ->
        response = Response.service_timeout(message.service_name, message.id, timeout)

        Message.return(message, response)
    end
  end

  defp _unavailable(%Message{service_name: service_name} = message) do
    response = Response.service_unavailable(service_name)

    Message.return(message, response)
  end
end
