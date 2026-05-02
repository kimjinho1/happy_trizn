defmodule HappyTrizn.Rooms do
  @moduledoc """
  멀티게임 방 시스템.

  - DB rooms 테이블 = 방 메타데이터 (호스트, 비번 해시, max_players, status).
  - 실제 in-game state 는 별도 GenServer (Sprint 3 GameBehaviour).
  - 강퇴 ban (5분) 은 ETS in-memory (재배포 OK, 짧은 기간).

  PubSub:
    - "rooms:lobby" — 방 생성/종료 broadcast (방 리스트 LiveView 가 subscribe).
    - "room:<id>" — 방 내부 이벤트 (강퇴, 상태 변화).
  """

  import Ecto.Query, warn: false

  alias HappyTrizn.Repo
  alias HappyTrizn.Accounts.User
  alias HappyTrizn.Rooms.Room

  @pubsub HappyTrizn.PubSub
  @kick_ban_table :rooms_kick_bans
  @kick_ban_seconds 300

  # =========================================================================
  # CRUD
  # =========================================================================

  def create(%User{id: host_id}, attrs) when is_map(attrs) do
    full_attrs = Map.put(attrs, "host_id", host_id) |> normalize_keys()

    case %Room{} |> Room.create_changeset(full_attrs) |> Repo.insert() do
      {:ok, room} ->
        broadcast_lobby({:room_created, room})
        {:ok, room}

      err ->
        err
    end
  end

  def get(id) when is_binary(id), do: Repo.get(Room, id)

  def get!(id) when is_binary(id), do: Repo.get!(Room, id)

  def list_open(opts \\ []) do
    game_type = Keyword.get(opts, :game_type)
    limit = Keyword.get(opts, :limit, 50)

    Room
    |> where([r], r.status == "open")
    |> maybe_filter_game(game_type)
    |> order_by([r], desc: r.inserted_at)
    |> limit(^limit)
    |> Repo.all()
  end

  defp maybe_filter_game(query, nil), do: query
  defp maybe_filter_game(query, game), do: where(query, [r], r.game_type == ^game)

  @doc """
  open / playing 상태 방 전부 (cleanup sweep 용 — 진행 중인 방까지 포함해서 GameSession
  존재 여부 검사 가능).
  """
  def list_alive do
    Room
    |> where([r], r.status in ["open", "playing"])
    |> Repo.all()
  end

  # =========================================================================
  # Join / Kick / Close
  # =========================================================================

  @doc """
  방 입장. 비번 검증 + 강퇴 ban 검사.

  Returns:
    - {:ok, room}
    - {:error, :wrong_password}
    - {:error, :kicked} — 5분 ban 안 풀림
    - {:error, :closed}
    - {:error, :not_found}
  """
  def join(%User{id: user_id}, room_id, password) when is_binary(room_id) do
    cond do
      kicked?(room_id, user_id) ->
        {:error, :kicked}

      true ->
        case get(room_id) do
          nil ->
            {:error, :not_found}

          %Room{status: "closed"} ->
            {:error, :closed}

          %Room{} = room ->
            if Room.verify_password(room, password) do
              {:ok, room}
            else
              {:error, :wrong_password}
            end
        end
    end
  end

  @doc """
  호스트 강퇴. target_user 를 방에서 제거 + 5분 ban.
  Returns {:ok, :kicked} 또는 {:error, :not_host} | {:error, :not_found}
  """
  def kick(%User{id: host_id}, room_id, target_user_id) when is_binary(room_id) do
    case get(room_id) do
      nil ->
        {:error, :not_found}

      %Room{host_id: ^host_id} ->
        record_kick(room_id, target_user_id)
        broadcast_room(room_id, {:kicked, target_user_id})
        {:ok, :kicked}

      _ ->
        {:error, :not_host}
    end
  end

  @doc """
  방 강제 종료 (호스트 검증 없이) — GameSession terminate / 빈 방 cleanup 용.

  Returns {:ok, room} | {:ok, :not_found} | {:error, changeset}
  """
  def close_by_id(room_id) when is_binary(room_id) do
    case get(room_id) do
      nil ->
        {:ok, :not_found}

      %Room{status: "closed"} = room ->
        {:ok, room}

      %Room{} = room ->
        case room |> Room.status_changeset(%{status: "closed"}) |> Repo.update() do
          {:ok, updated} ->
            broadcast_lobby({:room_closed, updated})
            broadcast_room(room_id, {:room_closed, updated})
            {:ok, updated}

          err ->
            err
        end
    end
  end

  @doc "방 종료 (호스트만)."
  def close(%User{id: host_id}, room_id) when is_binary(room_id) do
    case get(room_id) do
      nil ->
        {:error, :not_found}

      %Room{host_id: ^host_id} = room ->
        case room |> Room.status_changeset(%{status: "closed"}) |> Repo.update() do
          {:ok, updated} ->
            broadcast_lobby({:room_closed, updated})
            broadcast_room(room_id, {:room_closed, updated})
            {:ok, updated}

          err ->
            err
        end

      _ ->
        {:error, :not_host}
    end
  end

  # =========================================================================
  # Kick ban (5min, ETS)
  # =========================================================================

  def init_kick_ban_table do
    if :ets.whereis(@kick_ban_table) == :undefined do
      :ets.new(@kick_ban_table, [:set, :public, :named_table])
    end

    :ok
  end

  defp record_kick(room_id, user_id) do
    init_kick_ban_table()
    expires_at = System.system_time(:second) + @kick_ban_seconds
    :ets.insert(@kick_ban_table, {{room_id, user_id}, expires_at})
  end

  def kicked?(room_id, user_id) do
    init_kick_ban_table()

    case :ets.lookup(@kick_ban_table, {room_id, user_id}) do
      [{_, expires_at}] ->
        if System.system_time(:second) < expires_at do
          true
        else
          :ets.delete(@kick_ban_table, {room_id, user_id})
          false
        end

      [] ->
        false
    end
  end

  @doc "테스트 / admin 용 강퇴 ban clear."
  def clear_kick_bans do
    init_kick_ban_table()
    :ets.delete_all_objects(@kick_ban_table)
    :ok
  end

  # =========================================================================
  # PubSub
  # =========================================================================

  def subscribe_lobby, do: Phoenix.PubSub.subscribe(@pubsub, "rooms:lobby")
  def subscribe_room(room_id), do: Phoenix.PubSub.subscribe(@pubsub, "room:" <> room_id)

  defp broadcast_lobby(msg), do: Phoenix.PubSub.broadcast(@pubsub, "rooms:lobby", msg)

  defp broadcast_room(room_id, msg),
    do: Phoenix.PubSub.broadcast(@pubsub, "room:" <> room_id, msg)

  defp normalize_keys(map) do
    Map.new(map, fn
      {k, v} when is_atom(k) -> {Atom.to_string(k), v}
      {k, v} -> {k, v}
    end)
  end
end
