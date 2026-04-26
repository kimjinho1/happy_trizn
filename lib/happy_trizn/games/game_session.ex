defmodule HappyTrizn.Games.GameSession do
  @moduledoc """
  방 1개 = GenServer 1개. GameBehaviour 구현 모듈을 위임 받아 state 관리.

  Lifecycle:
    1. start_link/1 — 방 만들 때 (멀티) 또는 싱글 게임 시작 시 spawn.
    2. handle_player_join/3 — 플레이어 입장.
    3. handle_input/3 — 입력 처리 + broadcast.
    4. handle_player_leave/3 — 이탈 처리.
    5. tick (실시간 게임만, 게임별 interval).
    6. game_over? → terminate + match_results 저장.

  Naming:
    - 멀티 게임: Registry 등록 키 = `{:game, room_id}` (방 1개당 한 process)
    - 싱글 게임: Registry 키 = `{:game, user_id, game_type}` 또는 spawn unnamed.

  PubSub broadcast:
    - "game:<room_id>" — 멀티 게임 이벤트.
  """

  use GenServer

  alias HappyTrizn.Games.Registry, as: GameRegistry

  @pubsub HappyTrizn.PubSub

  # ============================================================================
  # Public API
  # ============================================================================

  def start_link(opts) do
    name = Keyword.get(opts, :name)

    if name do
      GenServer.start_link(__MODULE__, opts, name: name)
    else
      GenServer.start_link(__MODULE__, opts)
    end
  end

  def via_room(room_id),
    do: {:via, Registry, {HappyTrizn.Games.SessionRegistry, {:room, room_id}}}

  @doc "특정 방의 GameSession 가져오기 (없으면 nil)."
  def whereis_room(room_id) do
    case Registry.lookup(HappyTrizn.Games.SessionRegistry, {:room, room_id}) do
      [{pid, _}] -> pid
      [] -> nil
    end
  end

  @doc "방 GameSession 시작 또는 가져오기."
  def get_or_start_room(room_id, game_type) do
    case whereis_room(room_id) do
      nil -> start_link(name: via_room(room_id), room_id: room_id, game_type: game_type)
      pid -> {:ok, pid}
    end
  end

  def player_join(pid, player_id, meta \\ %{}),
    do: GenServer.call(pid, {:player_join, player_id, meta})

  def player_leave(pid, player_id, reason \\ :quit),
    do: GenServer.cast(pid, {:player_leave, player_id, reason})

  def handle_input(pid, player_id, input), do: GenServer.cast(pid, {:input, player_id, input})

  def get_state(pid), do: GenServer.call(pid, :get_state)

  def subscribe_room(room_id),
    do: Phoenix.PubSub.subscribe(@pubsub, "game:" <> room_id)

  # ============================================================================
  # GenServer callbacks
  # ============================================================================

  @impl true
  def init(opts) do
    room_id = Keyword.fetch!(opts, :room_id)
    game_type = Keyword.fetch!(opts, :game_type)
    config = Keyword.get(opts, :config, %{})

    case GameRegistry.get_module(game_type) do
      nil ->
        {:stop, {:unknown_game, game_type}}

      module ->
        {:ok, game_state} = module.init(config)
        meta = module.meta()

        state = %{
          room_id: room_id,
          game_type: game_type,
          module: module,
          game_state: game_state,
          players: %{},
          meta: meta,
          tick_ref: maybe_start_tick(meta),
          # 한 라운드 한 번만 match_results 저장 — game_over 가 매 mutation 마다
          # :yes 반환하므로 dedupe 필요. restart 시 false 로 reset.
          match_recorded: false
        }

        {:ok, state}
    end
  end

  @impl true
  def handle_call({:player_join, player_id, meta}, _from, state) do
    case state.module.handle_player_join(player_id, meta, state.game_state) do
      {:ok, new_game_state, broadcast} ->
        new_players = Map.put(state.players, player_id, meta)
        broadcast_messages(state.room_id, broadcast)
        {:reply, :ok, %{state | game_state: new_game_state, players: new_players}}

      {:reject, reason} ->
        {:reply, {:reject, reason}, state}
    end
  end

  def handle_call(:get_state, _from, state) do
    {:reply, state.game_state, state}
  end

  @impl true
  def handle_cast({:input, player_id, input}, state) do
    {:ok, new_game_state, broadcast} =
      state.module.handle_input(player_id, input, state.game_state)

    broadcast_messages(state.room_id, broadcast)
    new_state = %{state | game_state: new_game_state}
    check_and_finish(new_state)
  end

  def handle_cast({:player_leave, player_id, reason}, state) do
    {:ok, new_game_state, broadcast} =
      state.module.handle_player_leave(player_id, reason, state.game_state)

    new_players = Map.delete(state.players, player_id)
    broadcast_messages(state.room_id, broadcast)
    new_state = %{state | game_state: new_game_state, players: new_players}

    cond do
      # 마지막 player 떠남 → GenServer 종료 + room close.
      map_size(new_players) == 0 ->
        {:stop, :normal, new_state}

      true ->
        # game_over (winner 결정) 면 결과 broadcast + match_result 저장.
        # GenServer 는 유지 — 남은 player 가 "다시 하기" 가능.
        check_and_finish(new_state)
    end
  end

  @impl true
  def handle_info(:tick, state) do
    if function_exported?(state.module, :tick, 1) do
      {:ok, new_game_state, broadcast} = state.module.tick(state.game_state)
      broadcast_messages(state.room_id, broadcast)
      new_state = %{state | game_state: new_game_state}
      check_and_finish(new_state)
    else
      {:noreply, state}
    end
  end

  def handle_info(_, state), do: {:noreply, state}

  @impl true
  def terminate(reason, state) do
    if function_exported?(state.module, :terminate, 2) do
      state.module.terminate(reason, state.game_state)
    end

    # GameSession 종료 = 방도 닫기. 0명 leave / game_over / 비정상 종료 모두 cleanup.
    # 멀티 게임 only (room_id 있을 때).
    if state.room_id do
      try do
        HappyTrizn.Rooms.close_by_id(state.room_id)
      rescue
        _ -> :ok
      end
    end

    :ok
  end

  # ============================================================================
  # Helpers
  # ============================================================================

  defp maybe_start_tick(%{tick_interval_ms: ms}) when is_integer(ms) and ms > 0 do
    {:ok, ref} = :timer.send_interval(ms, self(), :tick)
    ref
  end

  defp maybe_start_tick(_), do: nil

  defp broadcast_messages(_room_id, []), do: :ok

  defp broadcast_messages(room_id, msgs) do
    Enum.each(msgs, &Phoenix.PubSub.broadcast(@pubsub, "game:" <> room_id, {:game_event, &1}))
  end

  # game_over? 검사 — 라운드 결과 한 번만 저장 + broadcast.
  # GenServer 는 stop 안 함 — 사용자가 "다시 하기" 누르면 restart action 으로 재진입.
  # 모든 player leave 시에만 stop (handle_cast :player_leave 에서 처리).
  defp check_and_finish(state) do
    case state.module.game_over?(state.game_state) do
      {:yes, results} ->
        if state.match_recorded do
          {:noreply, state}
        else
          maybe_record_match(state, results)
          # 저장 직후 summary 재조회 — 닉네임 누적 우승 횟수.
          # Tetris module 외 게임에도 동일 적용 (방 단위 winner counts).
          summary = HappyTrizn.MatchResults.winners_summary(state.room_id || "")
          enriched = Map.put(results, :winners_summary, summary)
          broadcast_messages(state.room_id, [{:game_over, enriched}])
          {:noreply, %{state | match_recorded: true}}
        end

      :no ->
        # restart 등으로 :over 벗어남 → 다음 라운드 결과 저장 가능하도록 flag reset.
        {:noreply, %{state | match_recorded: false}}
    end
  end

  # match_results 저장 — 멀티 게임만, room_id 있을 때.
  # winner_id 는 results.winner (player_id) → state.players[player_id].user_id 매핑.
  # 추가로 personal_records (참가자 모두) 갱신.
  defp maybe_record_match(state, results) do
    duration = duration_ms(results)
    winner_user_id = winner_user_id(state, results)

    HappyTrizn.MatchResults.record(%{
      game_type: state.game_type,
      room_id: state.room_id,
      winner_id: winner_user_id,
      duration_ms: duration,
      stats: results |> stringify_keys()
    })

    update_personal_records(state, results, winner_user_id)
  rescue
    e ->
      require Logger
      Logger.warning("[game_session] match_result save failed: #{inspect(e)}")
      :ok
  end

  # results.players 의 stats 를 사용자별 PersonalRecords 에 반영.
  defp update_personal_records(state, %{players: result_players}, winner_user_id)
       when is_map(result_players) do
    Enum.each(result_players, fn {player_id, stats} ->
      case Map.get(state.players, player_id) do
        %{user_id: uid} when is_binary(uid) ->
          metadata = %{
            "max_pps" => Map.get(stats, :pps, 0),
            "max_apm" => Map.get(stats, :apm, 0),
            "max_kpp" => Map.get(stats, :kpp, 0),
            "max_pieces" => Map.get(stats, :pieces_placed, 0)
          }

          HappyTrizn.PersonalRecords.apply_stats(%{id: uid}, state.game_type, %{
            score: Map.get(stats, :score, 0),
            lines: Map.get(stats, :lines, 0),
            won: uid == winner_user_id,
            metadata: metadata
          })

        _ ->
          :ok
      end
    end)
  end

  defp update_personal_records(_, _, _), do: :ok

  defp duration_ms(%{players: ps}) when is_map(ps) do
    ps
    |> Map.values()
    |> Enum.map(fn p -> Map.get(p, :duration_ms, 0) end)
    |> Enum.max(fn -> 0 end)
  end

  defp duration_ms(_), do: 0

  defp winner_user_id(state, %{winner: w}) when is_binary(w) do
    case Map.get(state.players, w) do
      %{user_id: uid} -> uid
      _ -> nil
    end
  end

  defp winner_user_id(_, _), do: nil

  # JSON 저장 시 atom key 자동 처리 안 되는 어댑터 대비.
  defp stringify_keys(m) when is_map(m) do
    Map.new(m, fn {k, v} ->
      key = if is_atom(k), do: Atom.to_string(k), else: k
      {key, stringify_value(v)}
    end)
  end

  defp stringify_keys(other), do: other

  defp stringify_value(%{} = m) when not is_struct(m), do: stringify_keys(m)

  defp stringify_value(v) when is_atom(v) and not is_boolean(v) and not is_nil(v),
    do: Atom.to_string(v)

  defp stringify_value(v) when is_list(v), do: Enum.map(v, &stringify_value/1)
  defp stringify_value(v), do: v
end
