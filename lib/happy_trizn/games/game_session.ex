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

  require Logger

  alias HappyTrizn.Games.Registry, as: GameRegistry

  @pubsub HappyTrizn.PubSub

  # 재연결 grace period 기본값 (ms). meta[:grace_period_ms] 로 게임별 override.
  # 0 으로 설정하면 grace 없이 즉시 leave.
  @default_grace_ms 5000

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

  @doc """
  플레이어 입장 또는 재연결.

  같은 player_id 가 grace 중에 다시 호출되면 reattach 로 처리 — grace timer 취소,
  caller pid 재 monitor, 새 게임 슬롯 spawn 안 함.

  caller_pid 는 disconnect 감지용으로 monitor 됨. 기본 self() (호출한 LiveView).
  """
  def player_join(pid, player_id, meta \\ %{}, caller_pid \\ self()),
    do: GenServer.call(pid, {:player_join, player_id, meta, caller_pid})

  @doc """
  명시적 voluntary leave — 즉시 evict, grace 없음. (사용자가 "나가기" 클릭 등)
  """
  def player_leave(pid, player_id, reason \\ :quit),
    do: GenServer.cast(pid, {:player_leave, player_id, reason})

  @doc """
  Disconnect 신호 — grace timer 시작 후 만료 시 player_leave(:disconnect).
  LiveView terminate 에서 호출. DOWN 신호로도 같은 경로 진입.
  """
  def player_disconnect(pid, player_id),
    do: GenServer.cast(pid, {:player_disconnect, player_id})

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
          match_recorded: false,
          # Sprint 4j — 세션 회복.
          # monitors: %{ref => player_id} — DOWN 신호로 어떤 player 가 끊겼는지 lookup.
          # grace_timers: %{player_id => timer_ref} — grace 만료 후 leave 호출 위한 timer.
          monitors: %{},
          grace_timers: %{}
        }

        {:ok, state}
    end
  end

  @impl true
  def handle_call({:player_join, player_id, meta, caller_pid}, _from, state) do
    if Map.has_key?(state.players, player_id) do
      # Reattach: 이미 슬롯 있음 → 모듈에는 알리지 않고 monitor 갱신 + grace 취소.
      # meta 는 새로 들어온 값으로 덮어쓰기 (nickname/avatar 변경 가능).
      state =
        state
        |> demonitor_for_player(player_id)
        |> cancel_grace_for_player(player_id)
        |> monitor_caller(player_id, caller_pid)
        |> update_player_meta(player_id, meta)

      broadcast_messages(state.room_id, [{:player_reattached, player_id}])
      {:reply, :ok, state}
    else
      case state.module.handle_player_join(player_id, meta, state.game_state) do
        {:ok, new_game_state, broadcast} ->
          new_players = Map.put(state.players, player_id, meta)

          new_state =
            %{state | game_state: new_game_state, players: new_players}
            |> monitor_caller(player_id, caller_pid)

          broadcast_messages(state.room_id, broadcast)
          {:reply, :ok, new_state}

        {:reject, reason} ->
          {:reply, {:reject, reason}, state}
      end
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

    new_state =
      %{state | game_state: new_game_state, players: new_players}
      |> demonitor_for_player(player_id)
      |> cancel_grace_for_player(player_id)

    broadcast_messages(state.room_id, broadcast)

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

  def handle_cast({:player_disconnect, player_id}, state) do
    {:noreply, start_grace(state, player_id)}
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

  # caller (LiveView) 죽음 — grace timer 시작 (또는 grace 0 이면 즉시 leave).
  def handle_info({:DOWN, ref, :process, _pid, _reason}, state) do
    case Map.pop(state.monitors, ref) do
      {nil, _} ->
        {:noreply, state}

      {player_id, new_monitors} ->
        state = %{state | monitors: new_monitors}
        {:noreply, start_grace(state, player_id)}
    end
  end

  # grace 만료 — 여전히 grace_timers 에 있으면 (= reattach 안 됨) 진짜 leave.
  def handle_info({:grace_expired, player_id}, state) do
    case Map.pop(state.grace_timers, player_id) do
      {nil, _} ->
        # 이미 reattach 또는 leave 처리됨.
        {:noreply, state}

      {_timer_ref, new_timers} ->
        new_state = %{state | grace_timers: new_timers}
        # player_leave 경로 재사용 — 마지막 player 면 GenServer stop 도 처리.
        handle_cast({:player_leave, player_id, :disconnect}, new_state)
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

  # ============================================================================
  # 세션 회복 helpers (Sprint 4j)
  # ============================================================================

  defp monitor_caller(state, _player_id, nil), do: state

  defp monitor_caller(state, player_id, caller_pid) when is_pid(caller_pid) do
    if Process.alive?(caller_pid) do
      ref = Process.monitor(caller_pid)
      %{state | monitors: Map.put(state.monitors, ref, player_id)}
    else
      # caller 이미 죽음 — grace 즉시 시작.
      start_grace(state, player_id)
    end
  end

  # 특정 player_id 의 monitor refs 모두 demonitor.
  defp demonitor_for_player(state, player_id) do
    {to_drop, remaining} =
      Enum.split_with(state.monitors, fn {_ref, pid} -> pid == player_id end)

    Enum.each(to_drop, fn {ref, _} -> Process.demonitor(ref, [:flush]) end)
    %{state | monitors: Map.new(remaining)}
  end

  # 진행 중 grace timer 취소.
  defp cancel_grace_for_player(state, player_id) do
    case Map.pop(state.grace_timers, player_id) do
      {nil, _} ->
        state

      {timer_ref, rest} ->
        if is_reference(timer_ref), do: Process.cancel_timer(timer_ref)
        # send_after 이미 발사됐거나 :immediate 경로로 mailbox 들어와 있을 수 있음 → flush.
        receive do
          {:grace_expired, ^player_id} -> :ok
        after
          0 -> :ok
        end

        %{state | grace_timers: rest}
    end
  end

  defp update_player_meta(state, player_id, meta) do
    %{state | players: Map.put(state.players, player_id, meta)}
  end

  defp grace_period_ms(state) do
    Map.get(state.meta, :grace_period_ms, @default_grace_ms)
  end

  # grace timer 시작. 이미 grace 중이거나 player slot 없으면 noop.
  # grace_ms = 0 이면 즉시 leave 호출.
  defp start_grace(state, player_id) do
    cond do
      not Map.has_key?(state.players, player_id) ->
        state

      Map.has_key?(state.grace_timers, player_id) ->
        # 이미 grace 진행 중 — 새 timer 안 시작.
        state

      true ->
        ms = grace_period_ms(state)
        broadcast_messages(state.room_id, [{:player_disconnected, player_id}])

        if ms == 0 do
          send(self(), {:grace_expired, player_id})
          %{state | grace_timers: Map.put(state.grace_timers, player_id, :immediate)}
        else
          timer_ref = Process.send_after(self(), {:grace_expired, player_id}, ms)
          %{state | grace_timers: Map.put(state.grace_timers, player_id, timer_ref)}
        end
    end
  end

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

    # Sprint 4d — Broadway 비동기 큐로 game_events Mongo 적재 (분석/감사용).
    HappyTrizn.GameEvents.emit(state.game_type, state.room_id, :match_completed, %{
      winner_user_id: winner_user_id,
      duration_ms: duration,
      player_count: map_size(state.players)
    })
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
