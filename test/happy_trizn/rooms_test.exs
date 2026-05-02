defmodule HappyTrizn.RoomsTest do
  use HappyTrizn.DataCase, async: false
  # async: false — ETS kick ban table 격리

  alias HappyTrizn.Rooms
  alias HappyTrizn.Rooms.Room

  defp register!(suffix) do
    {:ok, u} =
      HappyTrizn.Accounts.register_user(%{
        email: "u#{suffix}@trizn.kr",
        nickname: "u#{suffix}",
        password: "hello12345"
      })

    u
  end

  setup do
    Rooms.clear_kick_bans()
    host = register!(System.unique_integer([:positive]))
    {:ok, host: host}
  end

  describe "close_by_id/1 (empty room cleanup)" do
    test "open 방 → closed 상태", %{host: host} do
      {:ok, room} =
        Rooms.create(host, %{
          game_type: "tetris",
          name: "cleanup_#{System.unique_integer([:positive])}"
        })

      assert room.status == "open"

      assert {:ok, updated} = Rooms.close_by_id(room.id)
      assert updated.status == "closed"
      assert Rooms.get(room.id).status == "closed"
    end

    test "이미 닫힌 방 → 그대로 returns ok", %{host: host} do
      {:ok, room} =
        Rooms.create(host, %{
          game_type: "tetris",
          name: "double_close_#{System.unique_integer([:positive])}"
        })

      {:ok, _} = Rooms.close_by_id(room.id)
      assert {:ok, %Rooms.Room{status: "closed"}} = Rooms.close_by_id(room.id)
    end

    test "없는 방 → :not_found" do
      assert {:ok, :not_found} = Rooms.close_by_id("00000000-0000-0000-0000-000000000000")
    end

    test "list_open 에서 사라짐", %{host: host} do
      {:ok, room} =
        Rooms.create(host, %{
          game_type: "tetris",
          name: "vis_#{System.unique_integer([:positive])}"
        })

      assert Enum.any?(Rooms.list_open(), &(&1.id == room.id))

      {:ok, _} = Rooms.close_by_id(room.id)
      refute Enum.any?(Rooms.list_open(), &(&1.id == room.id))
    end
  end

  describe "create/2" do
    test "비번 없는 방 생성", %{host: host} do
      assert {:ok, %Room{} = room} =
               Rooms.create(host, %{game_type: "tetris", name: "테스트방", max_players: 2})

      assert room.host_id == host.id
      assert room.password_hash == nil
      assert room.password_salt == nil
      assert room.status == "open"
    end

    test "비번 있는 방 생성 → password_hash/salt 채워짐", %{host: host} do
      assert {:ok, room} =
               Rooms.create(host, %{
                 game_type: "bomberman",
                 name: "비밀방",
                 password: "secret123",
                 max_players: 4
               })

      assert room.password_hash != nil
      assert byte_size(room.password_hash) == 32
      assert room.password_salt != nil
      assert byte_size(room.password_salt) == 16
      # 평문은 DB 저장 안 됨
      reloaded = Rooms.get!(room.id)
      assert reloaded.password == nil
    end

    test "빈 비번 = 비번 없는 방", %{host: host} do
      assert {:ok, room} =
               Rooms.create(host, %{
                 game_type: "snake_io",
                 name: "공개",
                 password: "",
                 max_players: 8
               })

      assert room.password_hash == nil
    end

    test "max_players 초과 거부", %{host: host} do
      assert {:error, cs} = Rooms.create(host, %{game_type: "tetris", name: "x", max_players: 99})
      assert "must be less than or equal to 16" in errors_on(cs).max_players
    end

    test "name 필수", %{host: host} do
      assert {:error, cs} = Rooms.create(host, %{game_type: "tetris", max_players: 2})
      assert "can't be blank" in errors_on(cs).name
    end
  end

  describe "list_open/1" do
    setup ctx do
      {:ok, r1} = Rooms.create(ctx.host, %{game_type: "tetris", name: "t1"})
      {:ok, r2} = Rooms.create(ctx.host, %{game_type: "bomberman", name: "b1"})
      {:ok, t1: r1, b1: r2}
    end

    test "전체 open 방", %{t1: t1, b1: b1} do
      ids = Rooms.list_open() |> Enum.map(& &1.id)
      assert t1.id in ids
      assert b1.id in ids
    end

    test "game_type 필터", %{t1: t1} do
      results = Rooms.list_open(game_type: "tetris")
      assert Enum.all?(results, &(&1.game_type == "tetris"))
      assert t1.id in Enum.map(results, & &1.id)
    end

    test "closed 방은 안 보임", %{host: host, t1: t1} do
      {:ok, _} = Rooms.close(host, t1.id)
      ids = Rooms.list_open() |> Enum.map(& &1.id)
      refute t1.id in ids
    end
  end

  describe "join/3" do
    setup ctx do
      {:ok, room} = Rooms.create(ctx.host, %{game_type: "tetris", name: "open_room"})

      {:ok, secret_room} =
        Rooms.create(ctx.host, %{game_type: "tetris", name: "secret", password: "pw1234"})

      {:ok, room: room, secret_room: secret_room}
    end

    test "비번 없는 방 누구나 입장", %{room: room} do
      visitor = register!(System.unique_integer([:positive]))
      assert {:ok, ^room} = Rooms.join(visitor, room.id, nil)
    end

    test "비번 맞으면 입장", %{secret_room: secret_room} do
      visitor = register!(System.unique_integer([:positive]))
      assert {:ok, ^secret_room} = Rooms.join(visitor, secret_room.id, "pw1234")
    end

    test "비번 틀리면 wrong_password", %{secret_room: secret_room} do
      visitor = register!(System.unique_integer([:positive]))
      assert {:error, :wrong_password} = Rooms.join(visitor, secret_room.id, "wrong")
    end

    test "비번 nil 인데 비번 방 입장 = wrong_password", %{secret_room: secret_room} do
      visitor = register!(System.unique_integer([:positive]))
      assert {:error, :wrong_password} = Rooms.join(visitor, secret_room.id, nil)
    end

    test "없는 방 = not_found" do
      visitor = register!(System.unique_integer([:positive]))
      assert {:error, :not_found} = Rooms.join(visitor, Ecto.UUID.generate(), nil)
    end

    test "closed 방 = closed", %{host: host, room: room} do
      {:ok, _} = Rooms.close(host, room.id)
      visitor = register!(System.unique_integer([:positive]))
      assert {:error, :closed} = Rooms.join(visitor, room.id, nil)
    end
  end

  describe "kick/3 + 5분 ban" do
    setup ctx do
      {:ok, room} = Rooms.create(ctx.host, %{game_type: "tetris", name: "kick_test"})
      target = register!(System.unique_integer([:positive]))
      {:ok, room: room, target: target}
    end

    test "호스트 강퇴 → 대상 join 거부", %{host: host, room: room, target: target} do
      assert {:ok, _} = Rooms.join(target, room.id, nil)
      assert {:ok, :kicked} = Rooms.kick(host, room.id, target.id)
      assert {:error, :kicked} = Rooms.join(target, room.id, nil)
    end

    test "호스트 아닌 사람 강퇴 시도 = not_host", %{room: room, target: target} do
      not_host = register!(System.unique_integer([:positive]))
      assert {:error, :not_host} = Rooms.kick(not_host, room.id, target.id)
    end

    test "다른 방엔 영향 없음", %{host: host, room: room, target: target} do
      {:ok, other_room} = Rooms.create(host, %{game_type: "tetris", name: "other"})
      {:ok, :kicked} = Rooms.kick(host, room.id, target.id)
      # other room 은 입장 OK
      assert {:ok, _} = Rooms.join(target, other_room.id, nil)
    end

    test "kicked? helper 동작", %{host: host, room: room, target: target} do
      refute Rooms.kicked?(room.id, target.id)
      {:ok, :kicked} = Rooms.kick(host, room.id, target.id)
      assert Rooms.kicked?(room.id, target.id)
    end
  end

  describe "close/2" do
    setup ctx do
      {:ok, room} = Rooms.create(ctx.host, %{game_type: "tetris", name: "close_test"})
      {:ok, room: room}
    end

    test "호스트 close → status=closed", %{host: host, room: room} do
      assert {:ok, %Room{status: "closed"}} = Rooms.close(host, room.id)
    end

    test "호스트 아닌 사람 close 거부", %{room: room} do
      not_host = register!(System.unique_integer([:positive]))
      assert {:error, :not_host} = Rooms.close(not_host, room.id)
    end
  end

  describe "Room.verify_password/2" do
    test "nil hash = 누구나 OK" do
      assert Room.verify_password(%Room{password_hash: nil, password_salt: nil}, nil)
      assert Room.verify_password(%Room{password_hash: nil, password_salt: nil}, "anything")
    end

    test "올바른 평문" do
      salt = :crypto.strong_rand_bytes(16)
      hash = :crypto.hash(:sha256, salt <> "secret")
      assert Room.verify_password(%Room{password_hash: hash, password_salt: salt}, "secret")
    end

    test "잘못된 평문" do
      salt = :crypto.strong_rand_bytes(16)
      hash = :crypto.hash(:sha256, salt <> "secret")
      refute Room.verify_password(%Room{password_hash: hash, password_salt: salt}, "wrong")
    end
  end

  describe "list_open_with_counts/1 (Sprint 4o)" do
    test "GameSession 없는 방 → count 0", %{host: host} do
      {:ok, room} = Rooms.create(host, %{game_type: "tetris", name: "wc_#{System.unique_integer([:positive])}"})

      result = Rooms.list_open_with_counts(limit: 100)
      assert {^room, 0} = Enum.find(result, fn {r, _} -> r.id == room.id end)
    end

    test "GameSession 살아있고 player N 명 → count N", %{host: host} do
      {:ok, room} = Rooms.create(host, %{game_type: "tetris", name: "wcn_#{System.unique_integer([:positive])}"})

      {:ok, pid} =
        HappyTrizn.Games.GameSession.start_link(
          name: HappyTrizn.Games.GameSession.via_room(room.id),
          room_id: room.id,
          game_type: "tetris"
        )

      caller = spawn(fn -> Process.sleep(:infinity) end)
      :ok = HappyTrizn.Games.GameSession.player_join(pid, "p1", %{nickname: "x"}, caller)

      result = Rooms.list_open_with_counts(limit: 100)
      assert {_room, 1} = Enum.find(result, fn {r, _} -> r.id == room.id end)
    end
  end
end
