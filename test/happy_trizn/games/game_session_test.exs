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
