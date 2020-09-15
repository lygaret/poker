defmodule Poker.Application do
  use Application

  @pubsub Poker.RoomPubSub
  @registry Poker.RoomRegistry
  @supervisor Poker.RoomSupervisor

  def start(_type, _args) do
    children = [
      {Registry, keys: :unique, name: @registry},
      {Registry, keys: :duplicate, name: @pubsub},
      {DynamicSupervisor, name: @supervisor, strategy: :one_for_one},
      {Plug.Cowboy, scheme: :http, plug: nil, options: [dispatch: dispatch(), port: 4000]}
    ]

    opts = [strategy: :one_for_one, name: __MODULE__]
    Supervisor.start_link(children, opts)
  end

  defp dispatch do
    [
      {:_,
       [
         {"/ws/[...]", Poker.Socket, []},
         {:_, Plug.Cowboy.Handler, {Poker.Router, []}}
       ]}
    ]
  end

  def start_room do
    room = Poker.Data.Room.new(label: "Pointing Room")
    name = {:via, Registry, {@registry, room["id"]}}

    spec = %{
      id: Agent,
      start: {Agent, :start_link, [fn -> room end, [name: name]]}
    }

    case DynamicSupervisor.start_child(@supervisor, spec) do
      {:ok, _} -> {:ok, room}
      error -> error
    end
  end

  def fetch_room(id) do
    case Registry.lookup(@registry, id) do
      [{pid, _}] -> {:ok, Agent.get(pid, fn r -> r end)}
      [] -> {:error, :not_found}
    end
  end

  def update_room(id, room) do
    case Registry.lookup(@registry, id) do
      [{pid, _}] -> Agent.update(pid, fn _ -> room end)
      [] -> {:error, :not_found}
    end
  end

  def subscribe_room(id, cookie) do
    Registry.register(@pubsub, id, cookie)
  end

  def broadcast_room(id, message) do
    Registry.dispatch(@pubsub, id, fn entries ->
      for {pid, _} <- entries, do: send(pid, message)
    end)
  end
end
