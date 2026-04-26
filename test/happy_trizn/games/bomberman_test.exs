defmodule HappyTrizn.Games.BombermanTest do
  use ExUnit.Case, async: true

  alias HappyTrizn.Games.Bomberman

  defp init_with(n) do
    {:ok, state} = Bomberman.init(%{})

    Enum.reduce(1..n, state, fn i, acc ->
      {:ok, ns, _} = Bomberman.handle_player_join("p#{i}", %{nickname: "P#{i}"}, acc)
      ns
    end)
  end

  defp start_game(state) do
    [first | _] = Map.keys(state.players)
    {:ok, ns, _} = Bomberman.handle_input(first, %{"action" => "start_game"}, state)
    ns
  end

  describe "meta + init" do
    test "multi 2~4인" do
      m = Bomberman.meta()
      assert m.slug == "bomberman"
      assert m.mode == :multi
      assert m.max_players == 4
      assert m.min_players == 2
      assert m.tick_interval_ms == 50
    end

    test "init 기본 상태" do
      {:ok, s} = Bomberman.init(%{})
      assert s.status == :waiting
      assert s.players == %{}
      assert s.bombs == %{}
      assert s.explosions == []
    end
  end

  describe "join / leave" do
    test "1~4명 join — 4명까지 OK" do
      s = init_with(4)
      assert map_size(s.players) == 4
    end

    test "5번째 거부 :full" do
      s = init_with(4)
      assert {:reject, :full} = Bomberman.handle_player_join("p5", %{}, s)
    end

    test "spawn corner 4 위치 분배" do
      s = init_with(4)
      positions = s.players |> Map.values() |> Enum.map(fn p -> {p.row, p.col} end) |> Enum.sort()
      assert positions == [{1, 1}, {1, 11}, {9, 1}, {9, 11}]
    end

    test ":playing 중 join 거부" do
      s = init_with(2) |> start_game()
      assert {:reject, :in_progress} = Bomberman.handle_player_join("late", %{}, s)
    end

    test "playing 중 leave → 1명 남으면 game_finished" do
      s = init_with(2) |> start_game()
      {:ok, ns, broadcasts} = Bomberman.handle_player_leave("p1", :disconnect, s)
      assert ns.status == :over
      assert ns.winner_id == "p2"
      assert Enum.any?(broadcasts, fn {tag, _} -> tag == :game_finished end)
    end

    test ":over 상태에서 leave → 1명 남으면 :waiting 리셋 (stuck modal 회피)" do
      # 게임 종료 후 (:over) 한 명이 나가면 남은 사람은 :waiting 으로 빠져야.
      s = init_with(2) |> start_game()
      s = %{s | status: :over, winner_id: "p1"}
      {:ok, ns, _} = Bomberman.handle_player_leave("p2", :disconnect, s)
      assert ns.status == :waiting
      assert ns.winner_id == nil
      assert ns.bombs == %{}
      assert ns.explosions == []
      assert ns.items == %{}
      # 남은 player 는 spawn corner 로 재배치 + alive=true.
      assert map_size(ns.players) == 1
      assert ns.players["p1"].alive
      assert {ns.players["p1"].row, ns.players["p1"].col} == {1, 1}
    end
  end

  describe "start_game" do
    test ":over + 1명 → reset_to_waiting (stuck modal 회피)" do
      # 게임 끝나고 ("다시 하기" 클릭) 인원 부족 시 :waiting 리셋.
      s = init_with(1) |> Map.put(:status, :over) |> Map.put(:winner_id, "p1")
      {:ok, ns, _} = Bomberman.handle_input("p1", %{"action" => "start_game"}, s)
      assert ns.status == :waiting
      assert ns.winner_id == nil
    end

    test "2명 미만 무시" do
      s = init_with(1)
      assert {:ok, ^s, []} = Bomberman.handle_input("p1", %{"action" => "start_game"}, s)
    end

    test "2명 이상 + start_game → :playing + grid 생성 + spawn" do
      s = init_with(2)
      {:ok, ns, broadcasts} = Bomberman.handle_input("p1", %{"action" => "start_game"}, s)
      assert ns.status == :playing
      assert length(ns.grid) == 11
      assert length(hd(ns.grid)) == 13
      # spawn corner safe (empty)
      cell_at = fn {r, c} -> ns.grid |> Enum.at(r) |> Enum.at(c) end
      assert cell_at.({1, 1}) == :empty
      assert cell_at.({1, 11}) == :empty
      assert cell_at.({9, 1}) == :empty
      assert cell_at.({9, 11}) == :empty
      assert Enum.any?(broadcasts, fn {tag, _} -> tag == :game_started end)
    end
  end

  describe "move" do
    setup do
      s = init_with(2) |> start_game()
      # 결정론적 위치: p1 = (1, 1).
      {:ok, state: s}
    end

    test "이동 가능 한 칸 — 위치 변경", %{state: state} do
      {:ok, ns, broadcasts} =
        Bomberman.handle_input("p1", %{"action" => "move", "dir" => "right"}, state)

      p = ns.players["p1"]
      # spawn safe zone — (1, 2) empty 보장.
      assert {p.row, p.col} == {1, 2}
      assert Enum.any?(broadcasts, fn {tag, _} -> tag == :player_moved end)
    end

    test "벽 / 바깥 → 이동 무시", %{state: state} do
      # p1 (1,1) 에서 위로 = (0,1) = wall.
      {:ok, ns, _} = Bomberman.handle_input("p1", %{"action" => "move", "dir" => "up"}, state)
      assert {ns.players["p1"].row, ns.players["p1"].col} == {1, 1}
    end

    test "사망한 player 이동 무시", %{state: state} do
      state = put_in(state.players["p1"].alive, false)

      {:ok, ^state, []} =
        Bomberman.handle_input("p1", %{"action" => "move", "dir" => "right"}, state)
    end
  end

  describe "place_bomb + tick + explosion" do
    setup do
      s = init_with(2) |> start_game()
      {:ok, state: s}
    end

    test "폭탄 설치 → bombs map 에 추가", %{state: state} do
      {:ok, ns, broadcasts} = Bomberman.handle_input("p1", %{"action" => "place_bomb"}, state)
      assert map_size(ns.bombs) == 1
      assert Map.has_key?(ns.bombs, {1, 1})
      assert Enum.any?(broadcasts, fn {tag, _} -> tag == :bomb_placed end)
    end

    test "bomb_max 초과 시 추가 설치 거부", %{state: state} do
      # bomb_max default = 1.
      {:ok, s1, _} = Bomberman.handle_input("p1", %{"action" => "place_bomb"}, state)
      # 다른 cell 로 이동 후 또 설치 시도.
      {:ok, s2, _} = Bomberman.handle_input("p1", %{"action" => "move", "dir" => "right"}, s1)
      {:ok, s3, _} = Bomberman.handle_input("p1", %{"action" => "place_bomb"}, s2)
      # 여전히 1개.
      assert map_size(s3.bombs) == 1
    end

    test "tick 으로 fuse 감소 + 시간 끝나면 폭발 + bombs 에서 제거", %{state: state} do
      {:ok, s1, _} = Bomberman.handle_input("p1", %{"action" => "place_bomb"}, state)
      assert s1.bombs[{1, 1}].fuse_ms == 3000

      # 강제 fuse 50ms — 한 번 tick 하면 폭발.
      s2 = put_in(s1.bombs[{1, 1}].fuse_ms, 50)
      {:ok, s3, broadcasts} = Bomberman.tick(s2)
      assert s3.bombs == %{}
      assert s3.explosions != []
      assert Enum.any?(broadcasts, fn {tag, _} -> tag == :bomb_exploded end)
    end

    test "폭발 explosion ttl 감소 후 사라짐", %{state: state} do
      {:ok, s1, _} = Bomberman.handle_input("p1", %{"action" => "place_bomb"}, state)
      s2 = put_in(s1.bombs[{1, 1}].fuse_ms, 50)
      {:ok, s3, _} = Bomberman.tick(s2)

      # ttl 50 강제, 한 번 tick 하면 사라짐.
      # status 강제 :playing 유지 (자기 폭탄 사망으로 :over 진입 방지).
      [exp | _] = s3.explosions

      s4 = %{
        s3
        | explosions: [%{exp | ttl_ms: 50}],
          status: :playing,
          players:
            s3.players
            |> Map.update!("p1", fn p -> %{p | alive: true, row: 9, col: 11} end)
            |> Map.update!("p2", fn p -> %{p | alive: true} end)
      }

      {:ok, s5, _} = Bomberman.tick(s4)
      assert s5.explosions == []
    end
  end

  describe "tick + 게임 종료" do
    test "alive 1명 남으면 :over + winner" do
      s = init_with(2) |> start_game()
      s = put_in(s.players["p2"].alive, false)
      {:ok, ns, broadcasts} = Bomberman.tick(s)
      assert ns.status == :over
      assert ns.winner_id == "p1"
      assert Enum.any?(broadcasts, fn {tag, _} -> tag == :game_finished end)
    end

    test "alive 0명 → :over winner=nil" do
      s = init_with(2) |> start_game()

      s =
        s
        |> put_in([Access.key!(:players), "p1", Access.key!(:alive)], false)
        |> put_in([Access.key!(:players), "p2", Access.key!(:alive)], false)

      {:ok, ns, _} = Bomberman.tick(s)
      assert ns.status == :over
      assert ns.winner_id == nil
    end
  end

  describe "game_over?" do
    test ":over → :yes + winner + nickname/alive" do
      s = init_with(2) |> Map.put(:status, :over) |> Map.put(:winner_id, "p1")
      assert {:yes, %{winner: "p1", players: ps}} = Bomberman.game_over?(s)
      assert Map.has_key?(ps, "p1")
      assert Map.has_key?(ps, "p2")
    end

    test "그 외 :no" do
      assert :no = Bomberman.game_over?(init_with(2))
    end
  end
end
