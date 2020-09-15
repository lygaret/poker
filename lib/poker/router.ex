defmodule Poker.Router do
  use Plug.Router

  require Plug.Conn
  require EEx

  plug(Plug.Static, at: "/", from: :poker)
  plug(:match)
  plug(:dispatch)

  EEx.function_from_file(:defp, :application_html, "priv/views/application.html.eex", [:room_id])

  get "/" do
    case Poker.Application.start_room do
      {:ok, room} ->
        conn
        |> put_resp_header("location", "/#{room["id"]}")
        |> send_resp(302, "room created, redirecting...")

      error ->
        conn |> send_resp(500, inspect(error, pretty: true))
    end
  end

  get "/*args" do
    [room_id] = args
    case Poker.Application.fetch_room(room_id) do
      {:ok, _room} ->
        send_resp(conn, 200, application_html(room_id))

      {:error, :not_found} ->
        conn |> send_resp(404, "room not found")
    end
  end

  match _ do
    send_resp(conn, 404, "404")
  end
end
