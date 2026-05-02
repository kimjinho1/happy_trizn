defmodule HappyTrizn.Rooms.CleanupTest do
  use HappyTrizn.DataCase, async: false

  alias HappyTrizn.Games.GameSession
  alias HappyTrizn.Rooms
  alias HappyTrizn.Rooms.Cleanup

  defp register!(suffix) do
    {:ok, u} =
      HappyTrizn.Accounts.register_user(%{
        email: "cu#{suffix}@trizn.kr",
        nickname: "cu#{suffix}",
        password: "hello12345"
      })

    u
  end

  setup do
    Rooms.clear_kick_bans()
    host = register!(System.unique_integer([:positive]))
    # Application 이 enabled=false 로 이미 Cleanup 띄움 — sweep_now/1 직접 호출.
    {:ok, host: host}
  end

  describe "sweep_now/1" do
    test "GameSession nil + grace 만료 open 방 → closed", %{host: host} do
      {:ok, room} =
        Rooms.create(host, %{
          game_type: "tetris",
          name: "orphan_#{System.unique_integer([:positive])}"
        })

      assert room.status == "open"
      assert GameSession.whereis_room(room.id) == nil

      assert {:closed_count, n} = Cleanup.sweep_now(grace_seconds: 0)
      assert n >= 1
      assert Rooms.get(room.id).status == "closed"
    end

    test "GameSession 살아있는 방 → 보존", %{host: host} do
      {:ok, room} =
        Rooms.create(host, %{
          game_type: "tetris",
          name: "alive_#{System.unique_integer([:positive])}"
        })

      {:ok, _gs_pid} =
        GameSession.start_link(
          name: GameSession.via_room(room.id),
          room_id: room.id,
          game_type: "tetris"
        )

      assert GameSession.whereis_room(room.id) != nil

      _ = Cleanup.sweep_now(grace_seconds: 0)
      assert Rooms.get(room.id).status == "open"
    end

    test "grace 안 지난 신생 방 → 보존", %{host: host} do
      {:ok, room} =
        Rooms.create(host, %{
          game_type: "tetris",
          name: "fresh_#{System.unique_integer([:positive])}"
        })

      assert GameSession.whereis_room(room.id) == nil

      # grace 9999s — 새로 만든 방은 전부 보존되어야.
      _ = Cleanup.sweep_now(grace_seconds: 9999)
      assert Rooms.get(room.id).status == "open"
    end

    test "이미 closed 인 방 → skip (count 안 늘어남)", %{host: host} do
      {:ok, room} =
        Rooms.create(host, %{
          game_type: "tetris",
          name: "closed_#{System.unique_integer([:positive])}"
        })

      {:ok, _} = Rooms.close_by_id(room.id)
      assert Rooms.get(room.id).status == "closed"

      # closed 만 있는 상태에서 sweep — count 0.
      assert {:closed_count, 0} = Cleanup.sweep_now(grace_seconds: 0)
    end

    test "여러 방 mix — orphan 만 close, 살아있는 / 신생 / closed 보존", %{host: host} do
      # orphan
      {:ok, orphan} =
        Rooms.create(host, %{
          game_type: "tetris",
          name: "mix_orphan_#{System.unique_integer([:positive])}"
        })

      # alive — GameSession spawn
      {:ok, alive} =
        Rooms.create(host, %{
          game_type: "tetris",
          name: "mix_alive_#{System.unique_integer([:positive])}"
        })

      {:ok, _} =
        GameSession.start_link(
          name: GameSession.via_room(alive.id),
          room_id: alive.id,
          game_type: "tetris"
        )

      # already closed
      {:ok, closed} =
        Rooms.create(host, %{
          game_type: "tetris",
          name: "mix_closed_#{System.unique_integer([:positive])}"
        })

      {:ok, _} = Rooms.close_by_id(closed.id)

      assert {:closed_count, n} = Cleanup.sweep_now(grace_seconds: 0)
      assert n >= 1

      assert Rooms.get(orphan.id).status == "closed"
      assert Rooms.get(alive.id).status == "open"
      assert Rooms.get(closed.id).status == "closed"
    end
  end

  # auto-sweep on boot: init/1 에서 enabled=true 면 send(self(), :sweep) 호출 →
  # handle_info(:sweep) 가 sweep_orphans/1 + Process.send_after 등록.
  # sweep_now/1 가 같은 sweep_orphans/1 을 검증하므로 중복 테스트 생략.
  # interval 동작은 GenServer 표준 동작이라 별도 검증 불필요.
end
