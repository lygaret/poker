defmodule Poker.Socket do
  @behaviour :cowboy_websocket

  # if the room exists, initialize a Socket
  # if it doesn't, 404 the socket request
  def init(request, state) do
    [id] = request.path_info

    case Poker.Application.fetch_room(id) do
      {:ok, _} ->
        {:cowboy_websocket, request, %Poker.Socket.State{room_id: id}}

      {:error, :not_found} ->
        {:ok, :cowboy_req.reply(404, request), state}
    end
  end

  # initialize the socket by subscribing to room notifications
  # and sending the full state to the client
  def websocket_init(state) do
    with {:ok, _} <- Poker.Application.subscribe_room(state.room_id, :ok),
         {:ok, room} <- Poker.Application.fetch_room(state.room_id) do
      reply(room: room, state: state)
    else
      error ->
        reply(error: error, state: state)
    end
  end

  # incoming heartbeat (idle disconnect, cleanup half open connections)
  def websocket_handle({:text, "ok"}, state), do: {:ok, state}

  # incoming command from client
  def websocket_handle({:text, json}, state) do
    with {:ok, op} <- Poker.Socket.State.parse(json),
         {:ok, room} <- Poker.Application.fetch_room(state.room_id),
         {:ok, _room, ops, state} <- Poker.Socket.State.execute(state, room, op) do
      Poker.Application.broadcast_room(state.room_id, {:patch, ops})
      reply(:ack, state: state)
    else
      error ->
        reply(error: error, state: state)
    end
  end

  # mark the client inactive if they drop-off
  # TODO: should this care about the reason? normal vs. crash?
  def terminate(_reason, _req, state) do
    if state.participant_id != nil do
      with {:ok, room} <- Poker.Application.fetch_room(state.room_id),
           {:ok, _room, ops, state} <- Poker.Socket.State.execute(state, room, {:leave}) do
        Poker.Application.broadcast_room(state.room_id, {:patch, ops})
      end

      # ignore errors, we're shutting down anyway
    end

    :ok
  end

  # send patches from pubsub to the client
  def websocket_info({:patch, ops}, state), do: reply(patch: ops, state: state)

  # acknowledge process messages we don't handle explicitly
  def websocket_info(_, state), do: {:ok, state}

  defp reply(:ack, state: state) do
    text = Jason.encode!(state)
    {:reply, {:text, text}, state}
  end

  defp reply(error: error, state: state) do
    text = Jason.encode!(%{error: inspect(error, pretty: true)})
    {:reply, {:text, text}, state}
  end

  defp reply(room: room, state: state) do
    text = Jason.encode!(%{room: room})
    {:reply, {:text, text}, state}
  end

  defp reply(patch: patch, state: state) do
    text = Jason.encode!(%{patch: patch})
    {:reply, {:text, text}, state}
  end
end
