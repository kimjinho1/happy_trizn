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
