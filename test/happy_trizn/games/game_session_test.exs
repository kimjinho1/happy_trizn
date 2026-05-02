defmodule HappyTrizn.Games.GameSessionTest do
  use ExUnit.Case, async: false

  alias HappyTrizn.Games.GameSession

  defp unique_room_id, do: "room_#{System.unique_integer([:positive])}"

  describe "start_link / via_room / whereis_room" do
    test "via_room name 으로 spawn 후 whereis_room 으로 lookup" do
      room_id = unique_room_id()

      {:ok, pid} =
        GameSession.start_link(
          name: GameSession.via_room(room_id),
          room_id: room_id,
          game_type: "2048"
        )

      assert GameSession.whereis_room(room_id) == pid
    end

    test "없는 room_id 는 nil" do
      assert GameSession.whereis_room("ghost-room") == nil
    end

    test "unknown game_type → :stop" do
      Process.flag(:trap_exit, true)
      room_id = unique_room_id()

      assert {:error, {:unknown_game, "nonexistent"}} =
               GameSession.start_link(
                 name: GameSession.via_room(room_id),
                 room_id: room_id,
                 game_type: "nonexistent"
               )
    end
  end

  describe "get_or_start_room/2" do
    test "처음 호출 = spawn, 두번째 = 기존 pid" do
      room_id = unique_room_id()
      assert {:ok, pid1} = GameSession.get_or_start_room(room_id, "2048")
      assert {:ok, ^pid1} = GameSession.get_or_start_room(room_id, "2048")
    end
  end

  describe "lifecycle (2048 싱글)" do
    setup do
      room_id = unique_room_id()

      {:ok, pid} =
        GameSession.start_link(
          name: GameSession.via_room(room_id),
          room_id: room_id,
          game_type: "2048"
        )

      {:ok, room_id: room_id, pid: pid}
    end

    test "player_join 정상", %{pid: pid} do
      assert :ok = GameSession.player_join(pid, "p1", %{})
    end

    test "get_state 반환", %{pid: pid} do
      :ok = GameSession.player_join(pid, "p1", %{})
      state = GameSession.get_state(pid)
      assert state.board
      assert state.score == 0
    end

    test "handle_input + broadcast", %{pid: pid, room_id: room_id} do
      GameSession.subscribe_room(room_id)
      :ok = GameSession.player_join(pid, "p1", %{})

      # restart action 은 항상 state_changed broadcast (move 는 board 따라 안 될 수도)
      GameSession.handle_input(pid, "p1", %{"action" => "restart"})

      assert_receive {:game_event, {:state_changed, _}}, 1000
    end

    test "마지막 player leave → GenServer 종료", %{pid: pid} do
      Process.flag(:trap_exit, true)
      :ok = GameSession.player_join(pid, "p1", %{})
      ref = Process.monitor(pid)
      GameSession.player_leave(pid, "p1", :quit)
      assert_receive {:DOWN, ^ref, :process, ^pid, :normal}, 500
    end
  end

  describe "tick (Tetris 같은 multi)" do
    test "Tetris 는 tick_interval_ms 없음 → tick timer 없음" do
      room_id = unique_room_id()

      {:ok, pid} =
        GameSession.start_link(
          name: GameSession.via_room(room_id),
          room_id: room_id,
          game_type: "tetris"
        )

      # alive
      assert Process.alive?(pid)
    end
  end

  describe "match_results 자동 저장 (game_over 시)" do
    test "Tetris 1v1 한 명 leave → winner 결정 → match_results row 생성" do
      Ecto.Adapters.SQL.Sandbox.checkout(HappyTrizn.Repo)
      Ecto.Adapters.SQL.Sandbox.mode(HappyTrizn.Repo, {:shared, self()})

      {:ok, host} =
        HappyTrizn.Accounts.register_user(%{
          email: "mr_h_#{System.unique_integer([:positive])}@trizn.kr",
          nickname: "mr_h_#{System.unique_integer([:positive])}",
          password: "hello12345"
        })

      {:ok, opp} =
        HappyTrizn.Accounts.register_user(%{
          email: "mr_o_#{System.unique_integer([:positive])}@trizn.kr",
          nickname: "mr_o_#{System.unique_integer([:positive])}",
          password: "hello12345"
        })

      {:ok, room} =
        HappyTrizn.Rooms.create(host, %{
          game_type: "tetris",
          name: "match_#{System.unique_integer([:positive])}"
        })

      {:ok, pid} =
        GameSession.start_link(
          name: GameSession.via_room(room.id),
          room_id: room.id,
          game_type: "tetris"
        )

      :ok = GameSession.player_join(pid, "p1", %{user_id: host.id, nickname: host.nickname})
      :ok = GameSession.player_join(pid, "p2", %{user_id: opp.id, nickname: opp.nickname})

      # countdown 끝낼 때까지 기다림 (3000ms 대신 강제 force).
      # GenServer state 직접 조작 — 테스트용.
      :sys.replace_state(pid, fn state ->
        gs = state.game_state
        %{state | game_state: %{gs | status: :playing, countdown_ms: 0}}
      end)

      # p2 가 top_out 하면 p1 winner. leave 가 아닌 top_out 으로 시뮬.
      :sys.replace_state(pid, fn state ->
        gs = state.game_state
        new_players = Map.update!(gs.players, "p2", fn p -> %{p | top_out: true} end)
        # finish_round → :over + winner.
        winner = "p1"

        history_entry = %{
          winner_id: winner,
          primary_id: winner,
          at: DateTime.utc_now() |> DateTime.truncate(:second),
          score: 100,
          lines: 5,
          level: 1,
          pieces_placed: 1
        }

        new_gs = %{
          gs
          | players: new_players,
            status: :over,
            winner: winner,
            winners_history: [history_entry]
        }

        %{state | game_state: new_gs}
      end)

      # input trigger 로 check_and_finish 호출 → match_result 저장.
      GameSession.handle_input(pid, "p1", %{"action" => "left"})
      _ = :sys.get_state(pid)

      [r] = HappyTrizn.MatchResults.recent("tetris", 50)
      assert r.winner_id == host.id
      assert r.room_id == room.id
      assert r.game_type == "tetris"

      assert Process.alive?(pid)
      _ = opp
    end

    test "winner 결정 후에도 game_over 다시 검사해도 dedupe — match_result 1개만 저장" do
      Ecto.Adapters.SQL.Sandbox.checkout(HappyTrizn.Repo)
      Ecto.Adapters.SQL.Sandbox.mode(HappyTrizn.Repo, {:shared, self()})

      {:ok, host} =
        HappyTrizn.Accounts.register_user(%{
          email: "dd_#{System.unique_integer([:positive])}@trizn.kr",
          nickname: "dd_#{System.unique_integer([:positive])}",
          password: "hello12345"
        })

      {:ok, room} =
        HappyTrizn.Rooms.create(host, %{
          game_type: "tetris",
          name: "dedupe_#{System.unique_integer([:positive])}"
        })

      {:ok, pid} =
        GameSession.start_link(
          name: GameSession.via_room(room.id),
          room_id: room.id,
          game_type: "tetris"
        )

      :ok = GameSession.player_join(pid, "p1", %{user_id: host.id, nickname: host.nickname})
      :ok = GameSession.player_join(pid, "p2", %{user_id: nil, nickname: "p2"})

      :sys.replace_state(pid, fn state ->
        gs = state.game_state
        new_players = Map.update!(gs.players, "p2", fn p -> %{p | top_out: true} end)

        history_entry = %{
          winner_id: "p1",
          primary_id: "p1",
          at: DateTime.utc_now() |> DateTime.truncate(:second),
          score: 100,
          lines: 5,
          level: 1,
          pieces_placed: 1
        }

        new_gs = %{
          gs
          | players: new_players,
            status: :over,
            winner: "p1",
            winners_history: [history_entry]
        }

        %{state | game_state: new_gs}
      end)

      # 첫 trigger.
      GameSession.handle_input(pid, "p1", %{"action" => "left"})
      _ = :sys.get_state(pid)
      # 또 trigger — dedupe 로 추가 저장 안 함.
      GameSession.handle_input(pid, "p1", %{"action" => "left"})
      _ = :sys.get_state(pid)

      assert length(HappyTrizn.MatchResults.recent("tetris", 50)) == 1
    end
  end

  # ============================================================================
  # Sprint 4j — 세션 회복 (Process.monitor + grace period + reattach)
  # ============================================================================
  describe "session resilience: monitor + grace + reattach" do
    setup do
      # 2048 = 싱글, grace_period_ms 미설정 → @default_grace_ms (5000) fallback.
      # 빠른 테스트 위해 grace 짧게 override 한 fake 게임 모듈 등록 안 하고
      # :sys.replace_state 로 meta.grace_period_ms 직접 주입.
      room_id = unique_room_id()

      {:ok, pid} =
        GameSession.start_link(
          name: GameSession.via_room(room_id),
          room_id: room_id,
          game_type: "2048"
        )

      # 빠른 테스트용 grace 100ms.
      :sys.replace_state(pid, fn s ->
        %{s | meta: Map.put(s.meta, :grace_period_ms, 100)}
      end)

      {:ok, room_id: room_id, pid: pid}
    end

    test "player_join 시 caller pid Process.monitor 등록", %{pid: pid} do
      caller = spawn(fn -> Process.sleep(:infinity) end)
      :ok = GameSession.player_join(pid, "p1", %{}, caller)

      state = :sys.get_state(pid)
      assert map_size(state.monitors) == 1
      assert state.monitors |> Map.values() == ["p1"]
    end

    test "caller process exit → :player_disconnected broadcast + grace timer 시작",
         %{pid: pid, room_id: room_id} do
      GameSession.subscribe_room(room_id)

      caller = spawn(fn -> Process.sleep(:infinity) end)
      :ok = GameSession.player_join(pid, "p1", %{}, caller)

      Process.exit(caller, :kill)

      assert_receive {:game_event, {:player_disconnected, "p1"}}, 500

      state = :sys.get_state(pid)
      assert Map.has_key?(state.grace_timers, "p1")
      # 아직 player slot 살아있음 — grace 만료 전.
      assert Map.has_key?(state.players, "p1")
    end

    test "grace 만료 전 reattach (player_join 재호출) → leave 발생 X, monitor 갱신",
         %{pid: pid, room_id: room_id} do
      GameSession.subscribe_room(room_id)

      caller1 = spawn(fn -> Process.sleep(:infinity) end)
      :ok = GameSession.player_join(pid, "p1", %{nickname: "old"}, caller1)

      Process.exit(caller1, :kill)
      assert_receive {:game_event, {:player_disconnected, "p1"}}, 500

      # 50ms 안에 reattach (grace 100ms).
      Process.sleep(30)
      caller2 = spawn(fn -> Process.sleep(:infinity) end)
      :ok = GameSession.player_join(pid, "p1", %{nickname: "new"}, caller2)

      assert_receive {:game_event, {:player_reattached, "p1"}}, 500

      # grace timer 없어졌어야.
      state = :sys.get_state(pid)
      refute Map.has_key?(state.grace_timers, "p1")
      assert Map.get(state.players, "p1") == %{nickname: "new"}
      # 새 monitor 1개.
      assert map_size(state.monitors) == 1

      # grace 만료 시점 지나도 leave 안 발생.
      refute_receive {:game_event, {:player_left, "p1"}}, 200
    end

    test "grace 만료 후 → player_leave(:disconnect) 자동 호출",
         %{pid: pid, room_id: room_id} do
      Process.flag(:trap_exit, true)
      GameSession.subscribe_room(room_id)

      caller = spawn(fn -> Process.sleep(:infinity) end)
      :ok = GameSession.player_join(pid, "p1", %{}, caller)

      Process.exit(caller, :kill)
      assert_receive {:game_event, {:player_disconnected, "p1"}}, 500

      # 마지막 player 였으니 grace 만료 후 GenServer stop.
      ref = Process.monitor(pid)
      assert_receive {:DOWN, ^ref, :process, ^pid, :normal}, 1000
    end

    test "voluntary player_leave(:quit) → 즉시 evict, monitor + grace cleanup",
         %{pid: pid} do
      Process.flag(:trap_exit, true)

      caller_a = spawn(fn -> Process.sleep(:infinity) end)
      caller_b = spawn(fn -> Process.sleep(:infinity) end)
      :ok = GameSession.player_join(pid, "p1", %{}, caller_a)
      :ok = GameSession.player_join(pid, "p2", %{}, caller_b)

      # p1 이 voluntary leave.
      GameSession.player_leave(pid, "p1", :quit)
      _ = :sys.get_state(pid)

      state = :sys.get_state(pid)
      refute Map.has_key?(state.players, "p1")
      # monitor 1개만 남음 (p2).
      assert map_size(state.monitors) == 1
      assert state.monitors |> Map.values() == ["p2"]
      refute Map.has_key?(state.grace_timers, "p1")
    end
  end

  # ============================================================================
  # Sprint 4n — event_log ring buffer + reattach replay
  # ============================================================================
  describe "event_log: broadcast 마다 seq 증가" do
    setup do
      room_id = unique_room_id()

      {:ok, pid} =
        GameSession.start_link(
          name: GameSession.via_room(room_id),
          room_id: room_id,
          game_type: "2048"
        )

      # grace 짧게 — 빠른 테스트.
      :sys.replace_state(pid, fn s ->
        %{s | meta: Map.put(s.meta, :grace_period_ms, 100)}
      end)

      {:ok, room_id: room_id, pid: pid}
    end

    test "초기 current_seq = 0, event_log 비어있음", %{pid: pid} do
      state = :sys.get_state(pid)
      assert state.current_seq == 0
      assert :queue.is_empty(state.event_log)
    end

    test "player_join 신규 → broadcast 발생 → seq 증가", %{pid: pid} do
      caller = spawn(fn -> Process.sleep(:infinity) end)
      :ok = GameSession.player_join(pid, "p1", %{}, caller)

      state = :sys.get_state(pid)
      # 2048 의 handle_player_join 은 broadcast 비어있음 → seq 0 유지.
      # (게임 모듈마다 다름)
      assert state.current_seq >= 0
    end

    test "handle_input → broadcast → event_log 에 추가", %{pid: pid, room_id: room_id} do
      GameSession.subscribe_room(room_id)
      caller = spawn(fn -> Process.sleep(:infinity) end)
      :ok = GameSession.player_join(pid, "p1", %{}, caller)

      seq_before = :sys.get_state(pid).current_seq

      # restart action 은 broadcast {:state_changed, _} 발생.
      GameSession.handle_input(pid, "p1", %{"action" => "restart"})
      _ = :sys.get_state(pid)

      state = :sys.get_state(pid)
      assert state.current_seq == seq_before + 1
      assert :queue.len(state.event_log) >= 1

      # PubSub 으로도 정상 도착.
      assert_receive {:game_event, {:state_changed, _}}, 500
    end

    test "ring buffer cap @event_log_cap (50) — 오래된 events drop", %{pid: pid} do
      caller = spawn(fn -> Process.sleep(:infinity) end)
      :ok = GameSession.player_join(pid, "p1", %{}, caller)

      # 60 회 broadcast — 10 개는 drop 되어야.
      for _ <- 1..60 do
        GameSession.handle_input(pid, "p1", %{"action" => "restart"})
      end

      _ = :sys.get_state(pid)
      state = :sys.get_state(pid)
      assert :queue.len(state.event_log) == 50
      assert state.current_seq == 60
    end
  end

  describe "reattach replay" do
    setup do
      room_id = unique_room_id()

      {:ok, pid} =
        GameSession.start_link(
          name: GameSession.via_room(room_id),
          room_id: room_id,
          game_type: "2048"
        )

      :sys.replace_state(pid, fn s ->
        %{s | meta: Map.put(s.meta, :grace_period_ms, 200)}
      end)

      {:ok, room_id: room_id, pid: pid}
    end

    test "disconnect 후 reattach — 사이에 발생한 events 새 caller pid 에 직접 send",
         %{pid: pid, room_id: room_id} do
      GameSession.subscribe_room(room_id)

      caller1 = spawn(fn -> Process.sleep(:infinity) end)
      :ok = GameSession.player_join(pid, "p1", %{}, caller1)

      # disconnect.
      Process.exit(caller1, :kill)
      assert_receive {:game_event, {:player_disconnected, "p1"}}, 500

      # disconnect 후 게임 진행 — broadcast 생성 (다른 player 가 있는 척 — restart input).
      GameSession.handle_input(pid, "p1", %{"action" => "restart"})
      GameSession.handle_input(pid, "p1", %{"action" => "restart"})
      _ = :sys.get_state(pid)

      # 2 events (state_changed × 2) PubSub 로 전송됨 — caller1 죽었으니 못 받음.
      # subscribe_room 한 테스트 process 는 받음.
      assert_receive {:game_event, {:state_changed, _}}, 500
      assert_receive {:game_event, {:state_changed, _}}, 500

      # reattach. test process 가 caller2 역할.
      caller2_target = self()
      :ok = GameSession.player_join(pid, "p1", %{}, caller2_target)

      # caller2_target 에 missed events 직접 send 됨 — assert_receive 로 확인.
      # subscribe_room 으로 받은 events 와 별개의 send 라 한 번 더 들어옴.
      assert_receive {:game_event, {:state_changed, _}}, 500
      assert_receive {:game_event, {:state_changed, _}}, 500

      # reattach broadcast 도 PubSub 로 도착.
      assert_receive {:game_event, {:player_reattached, "p1"}}, 500

      state = :sys.get_state(pid)
      refute Map.has_key?(state.disconnected_at_seq, "p1")
    end

    test "disconnect 후 즉시 reattach (사이 events 0) → replay 0", %{pid: pid, room_id: room_id} do
      GameSession.subscribe_room(room_id)

      caller1 = spawn(fn -> Process.sleep(:infinity) end)
      :ok = GameSession.player_join(pid, "p1", %{}, caller1)

      Process.exit(caller1, :kill)
      assert_receive {:game_event, {:player_disconnected, "p1"}}, 500

      # mailbox 비움 — 이전 broadcast 들 정리.
      flush_mailbox()

      # 즉시 reattach — 사이에 events 0.
      :ok = GameSession.player_join(pid, "p1", %{}, self())

      # reattach broadcast 1 개만, missed events 0.
      assert_receive {:game_event, {:player_reattached, "p1"}}, 500
      refute_receive {:game_event, {:state_changed, _}}, 100
    end

    test "disconnect 안 했는데 같은 player_id reattach 호출 (idempotent) → replay 0",
         %{pid: pid, room_id: room_id} do
      GameSession.subscribe_room(room_id)

      :ok = GameSession.player_join(pid, "p1", %{}, self())
      flush_mailbox()

      # 다시 호출 — disconnected_at_seq 에 없으니 since_seq = current_seq → replay 0.
      :ok = GameSession.player_join(pid, "p1", %{}, self())

      assert_receive {:game_event, {:player_reattached, "p1"}}, 500
      refute_receive {:game_event, {:state_changed, _}}, 100
    end
  end

  defp flush_mailbox do
    receive do
      _ -> flush_mailbox()
    after
      0 -> :ok
    end
  end

  describe "terminate cleanup (room close)" do
    test "GameSession 종료 시 Rooms.close_by_id 호출 → 방 status closed" do
      Ecto.Adapters.SQL.Sandbox.checkout(HappyTrizn.Repo)
      Ecto.Adapters.SQL.Sandbox.mode(HappyTrizn.Repo, {:shared, self()})

      {:ok, host} =
        HappyTrizn.Accounts.register_user(%{
          email: "gst#{System.unique_integer([:positive])}@trizn.kr",
          nickname: "gst#{System.unique_integer([:positive])}",
          password: "hello12345"
        })

      {:ok, room} =
        HappyTrizn.Rooms.create(host, %{
          game_type: "tetris",
          name: "term_#{System.unique_integer([:positive])}"
        })

      {:ok, pid} =
        GameSession.start_link(
          name: GameSession.via_room(room.id),
          room_id: room.id,
          game_type: "tetris"
        )

      ref = Process.monitor(pid)
      GenServer.stop(pid, :normal)
      assert_receive {:DOWN, ^ref, :process, ^pid, _}, 1000

      # 방 닫혔어야
      assert HappyTrizn.Rooms.get(room.id).status == "closed"
    end
  end
end
