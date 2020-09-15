defmodule Poker.Data do
  alias __MODULE__

  import Json.Patch
  import Json.Pointer

  @id_length 8

  ## generates a random id, of length @id_length bytes, with the given `prefix`
  def generate_id(prefix) do
    :crypto.strong_rand_bytes(@id_length)
    |> Base.encode32(case: :lower, padding: false)
    |> generate_id_prefix(prefix)
  end

  # can't pipe to &-functions, so need defp for above
  def generate_id_prefix(id, prefix) do
    "#{prefix}#{id}"
  end

  defmodule Room do
    def new(label: label) do
      %{
        "id" => Data.generate_id("room"),
        "label" => label,
        "version" => 1,
        "participants" => %{},
        "items" => %{}
      }
    end

    def rename(room: room, label: label) do
      evaluate_with_ops(room, [
        replace("/label", label),
        replace("/version", room["version"] + 1)
      ])
    end
  end

  defmodule Participant do
    def new(nick: nick) do
      %{
        "id" => Data.generate_id("part"),
        "nick" => nick,
        "state" => "inactive"
      }
    end

    def fetch(room: room, id: id) do
      fetch(room, "/participants/#{id}")
    end

    def join(room: room, participant: participant) do
      evaluate_with_ops(room, [
        add("/participants/#{participant["id"]}", participant),
        replace("/participants/#{participant["id"]}/state", "active"),
        replace("/version", room["version"] + 1)
      ])
    end

    def rename(room: room, participant: participant, nick: nick) do
      evaluate_with_ops(room, [
        replace("/participants/#{participant["id"]}/nick", nick),
        replace("/version", room["version"] + 1)
      ])
    end

    def leave(room: room, participant: participant) do
      evaluate_with_ops(room, [
        replace("/participants/#{participant["id"]}/state", "inactive"),
        replace("/version", room["version"] + 1)
      ])
    end

    def idle(room: room, participant: participant) do
      evaluate_with_ops(room, [
        replace("/participants/#{participant["id"]}/state", "idle"),
        replace("/version", room["version"] + 1)
      ])
    end

    def deidle(room: room, participant: participant) do
      evaluate_with_ops(room, [
        replace("/participants/#{participant["id"]}/state", "active"),
        replace("/version", room["version"] + 1)
      ])
    end
  end

  defmodule Item do
    def new(label: label) do
      %{
        "id" => Data.generate_id("item"),
        "label" => label,
        "state" => "pending",
        "votes" => %{}
      }
    end

    def fetch(room: room, id: id) do
      fetch(room, "/items/#{id}")
    end

    def add(room: room, item: item) do
      evaluate_with_ops(room, [
        add("/items/#{item["id"]}", item),
        replace("/version", room["version"] + 1)
      ])
    end

    def rename(room: room, item: item, label: label) do
      evaluate_with_ops(room, [
        replace("/items/#{item["id"]}/label", label),
        replace("/version", room["version"] + 1)
      ])
    end

    def archive(room: room, item: item) do
      archive_op =
        if item["state"] == "pending" do
          remove("/items/#{item["id"]}")
        else
          replace("/items/#{item["id"]}/state", "archived")
        end

      evaluate_with_ops(room, [
        archive_op,
        replace("/version", room["version"] + 1)
      ])
    end

    def vote(room: room, item: item, part_id: part_id, score: score) do
      with {:ok, room, vote_ops} <- vote_score(room, item, part_id, score),
          {:ok, room, state_ops} <- vote_state(room, item),
          {:ok, room, version_ops} <- vote_version(room) do
        {:ok, room, vote_ops ++ state_ops ++ version_ops}
      end
    end

    defp vote_score(room, item, part_id, score) do
      evaluate_with_ops(room, [
        add("/items/#{item["id"]}/votes/#{part_id}", score)
      ])
    end

    defp vote_state(room, item) do
      votes = Map.values(item["votes"])
      count = length(votes)

      ops =
        cond do
          count > 1 and consensus?(votes) ->
            [replace("/items/#{item["id"]}/state", "consensus")]

          count > 0 ->
            [replace("/items/#{item["id"]}/state", "active")]

          true ->
            []
        end

      evaluate_with_ops(room, ops)
    end

    defp consensus?(votes) do
      votes |> Enum.uniq() |> length == 1
    end

    defp vote_version(room) do
      evaluate_with_ops(room, [
        replace("/version", room["version"] + 1)
      ])
    end
  end
end
