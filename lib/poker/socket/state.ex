defmodule Poker.Socket.State do
  @moduledoc """
  Consumes parsed commands, and produces new state.
  Used by the socket to implement a stateful room.
  """

  @derive Jason.Encoder
  defstruct [:room_id, :participant_id]

  @typedoc """
  State held by a websocket representing a single connection.

  :room_id the id of the room for this socket
  :participant_id the id of the participont for this socket, if joined
  """
  @type t :: %__MODULE__{
          room_id: String.t(),
          participant_id: nil | String.t()
        }

  @typedoc """
  Tuples representing valid operations to be run with the execute methods.
  """
  @type op ::
          {:fetch}
          | {:join, String.t()}
          | {:leave}
          | {:add_item, String.t()}
          | {:vote_item, String.t()}

  @doc """
  Parse the given input into an operation we can act on, or return an error.

  ## Example

      iex> Poker.Socket.State.parse(~s({"op": "join", "nick": "Jon"}))
      {:ok, {:join, "Jon"}}

      # requires fields
      iex> Poker.Socket.State.parse(~s({"op": "join"}))
      {:error, :unknown_command}
  """
  @spec parse(iodata) :: {:ok, op} | {:error, term}
  def parse(json) do
    case Jason.decode(json) do
      {:error, e} ->
        {:error, e}

      {:ok, data} ->
        case data do
          %{"op" => "fetch"} ->
            {:ok, {:fetch}}

          %{"op" => "join", "nick" => nick} ->
            {:ok, {:join, nick}}

          %{"op" => "leave"} ->
            {:ok, {:leave}}

          %{"op" => "addItem", "label" => label} ->
            {:ok, {:add_item, label}}

          %{"op" => "voteItem", "id" => item_id, "score" => score} ->
            {:ok, {:vote_item, item_id, score}}

          _ ->
            {:error, :unknown_operation}
        end
    end
  end

  @doc """
  Execute the given operation upon the room, in the context of the connection, and
  return the room, the list of operations, and the new connection state.
  """
  @spec execute(__MODULE__.t(), map, op) :: {:ok, map, list, __MODULE__.t()} | {:error, term}
  def execute(state, room, op)

  @doc false
  ## fetch just returns the room as it exists
  def execute(state, room, {:fetch}), do: {:ok, room, [], state}

  @doc false
  ## sets the current connection's participant, if the participant isn't present
  ## sets the current connection's participant active if the participant _is_ set already
  def execute(state, room, {:join, nick}) do
    if state.participant_id != nil do
      with {:ok, participant} <- Poker.Data.Participant.fetch(room: room, id: state.participant_id),
           {:ok, room, ops} <- Poker.Data.Participant.deidle(room: room, participant: participant) do
        {:ok, room, ops, state}
      end
    else
      # joining and there's no participant id, we must be new here
      with participant = Poker.Data.Participant.new(nick: nick),
           {:ok, room, ops} <- Poker.Data.Participant.join(room: room, participant: participant) do
        {:ok, room, ops, %{state | participant_id: participant["id"]}}
      end
    end
  end

  @doc false
  ## idles the participant
  def execute(state, room, {:leave}) do
    with {:ok, participant_id} <- ensure_participant(state),
         {:ok, participant} <- Poker.Data.Participant.fetch(room: room, id: participant_id),
         {:ok, room, ops} <- Poker.Data.Participant.idle(room: room, participant: participant) do
      {:ok, room, ops, state}
    end
  end

  @doc false
  ## change the participant's nick
  def execute(state, room, {:renick, nick}) do
    with {:ok, participant_id} <- ensure_participant(state),
         {:ok, participant} <- Poker.Data.Participant.fetch(room: room, id: participant_id),
         {:ok, room, ops} <- Poker.Data.Participant.rename(room: room, participant: participant, nick: nick) do
      {:ok, room, ops, state}
    end
  end

  @doc false
  ## add the labeled item to the voting set
  def execute(state, room, {:add_item, label}) do
    with item = Poker.Data.Item.new(label: label),
         {:ok, room, ops} <- Poker.Data.Item.add(room: room, item: item) do
      {:ok, room, ops, state}
    end
  end

  @doc false
  ## vote on the labeled item already present in the voting set
  def execute(state, room, {:vote_item, id, score}) do
    with {:ok, item} <- Poker.Data.Item.fetch(room: room, id: id),
         {:ok, room, ops} <- Poker.Data.Item.vote(room: room, item: item, part_id: state.participant_id, score: score) do
      {:ok, room, ops, state}
    end
  end

  defp ensure_participant(state) do
    if state.participant_id != nil do
      {:ok, participan_id: state.participant_id}
    else
      {:error, :no_participant}
    end
  end
end
