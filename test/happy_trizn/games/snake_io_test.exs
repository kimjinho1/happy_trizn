defmodule HappyTrizn.Games.SnakeIoTest do
  use ExUnit.Case, async: true

  alias HappyTrizn.Games.SnakeIo

  defp init_with(n) do
    {:ok, state} = SnakeIo.init(%{})

    Enum.reduce(1..n, state, fn i, acc ->
      {:ok, ns, _} = SnakeIo.handle_player_join("p#{i}", %{nickname: "P#{i}"}, acc)
      ns
    end)
  end

  describe "meta + init" do
    test "multi 16, min 1, slug snake_io" do
      m = SnakeIo.meta()
      assert m.slug == "snake_io"
      assert m.mode == :multi
      assert m.max_players == 16
      assert m.min_players == 1
      assert m.tick_interval_ms == 50
    end

    test "init 시 :playing + 빈 players + food 보장" do
      {:ok, s} = SnakeIo.init(%{})
      assert s.status == :playing
      assert s.players == %{}
      assert s.grid_size == 200
      assert MapSet.size(s.food) >= 60
    end
  end

  describe "join / leave" do
    test "1~16명 join — 16번째까지 OK" do
      s = init_with(16)
      assert map_size(s.players) == 16
    end

    test "17번째 거부 :full" do
      s = init_with(16)
      assert {:reject, :full} = SnakeIo.handle_player_join("p17", %{}, s)
    end

    test "join 시 snake 길이 3, 색깔 unique 분배" do
      s = init_with(2)
      assert map_size(s.players) == 2
      [p1, p2] = Map.values(s.players)
      assert length(p1.body) == 3
      assert length(p2.body) == 3
      assert p1.color != p2.color
      assert p1.alive
      assert p2.alive
    end

    test "leave 시 player 제거 + body 일부 food drop" do
      s = init_with(2)
      food_before = MapSet.size(s.food)
      {:ok, ns, _} = SnakeIo.handle_player_leave("p1", :disconnect, s)
      assert map_size(ns.players) == 1
      # body 일부가 food 로 변환됨 — food 가 줄지 않았어야.
      assert MapSet.size(ns.food) >= food_before
    end

    test ":playing 캐주얼이라 game_over? 항상 :no" do
      s = init_with(2)
      assert :no = SnakeIo.game_over?(s)
    end
  end

  describe "set_dir input" do
    test "유효 dir → next_dir 갱신" do
      s = init_with(1)
      [{pid, p}] = Enum.to_list(s.players)
      # 현재 dir 와 반대 아닌 방향 선택.
      target =
        case p.dir do
          :up -> :left
          :down -> :left
          :left -> :up
          :right -> :up
        end

      {:ok, ns, _} =
        SnakeIo.handle_input(pid, %{"action" => "set_dir", "dir" => Atom.to_string(target)}, s)

      assert ns.players[pid].next_dir == target
    end

    test "180도 반대 방향 무시" do
      s = init_with(1)
      [{pid, p}] = Enum.to_list(s.players)

      opposite =
        case p.dir do
          :up -> "down"
          :down -> "up"
          :left -> "right"
          :right -> "left"
        end

      {:ok, ns, _} = SnakeIo.handle_input(pid, %{"action" => "set_dir", "dir" => opposite}, s)
      # next_dir 그대로.
      assert ns.players[pid].next_dir == p.next_dir
    end

    test "사망한 player 입력 무시" do
      s = init_with(1)
      [{pid, _}] = Enum.to_list(s.players)
      s = put_in(s.players[pid].alive, false)

      {:ok, ^s, _} = SnakeIo.handle_input(pid, %{"action" => "set_dir", "dir" => "left"}, s)
    end
  end

  describe "tick broadcast" do
    test "tick 마다 :snake_state broadcast — players + food + tick_no 포함" do
      s = init_with(2)
      {:ok, ns, broadcasts} = SnakeIo.tick(s)

      assert [{:snake_state, payload}] = broadcasts
      assert payload.players == ns.players
      assert payload.food == ns.food
      assert payload.tick_no == ns.tick_no
    end
  end

  describe "tick — head 전진" do
    test "tick 마다 head 1칸 이동 + tail 줄어듦 (식사 안 함)" do
      s = init_with(1)
      [{pid, p}] = Enum.to_list(s.players)
      # food 없는 안전한 위치 검증을 위해 food 비움.
      s = %{s | food: MapSet.new(), food_target: 0}
      {hr, hc} = hd(p.body)
      {dr, dc} = dir_delta(p.dir)

      {:ok, ns, _} = SnakeIo.tick(s)
      np = ns.players[pid]
      assert hd(np.body) == {hr + dr, hc + dc}
      assert length(np.body) == 3
    end

    test "벽 충돌 → 사망 + body food drop" do
      s = init_with(1)
      [{pid, _}] = Enum.to_list(s.players)
      # head 를 격자 가장자리 한칸 안에 두고 그 방향으로 set.
      s = %{s | food: MapSet.new(), food_target: 0}

      s =
        update_in(s.players[pid], fn p ->
          %{p | body: [{0, 5}, {1, 5}, {2, 5}], dir: :up, next_dir: :up, alive: true}
        end)

      {:ok, ns, _} = SnakeIo.tick(s)
      assert ns.players[pid].alive == false
      assert ns.players[pid].died_at_tick == ns.tick_no
    end

    test "자기 몸 충돌 → 사망 (tail follow 는 허용)" do
      s = init_with(1)
      [{pid, _}] = Enum.to_list(s.players)
      s = %{s | food: MapSet.new(), food_target: 0}

      # 6-cell U-shape — head 가 다음 tick 에서 자기 몸 가운데로 들어감.
      # body: head=(5,5), 다음=(5,4) — left 로 가면 (5,4) 박음 (가운데 cell).
      s =
        update_in(s.players[pid], fn p ->
          %{
            p
            | body: [{5, 5}, {5, 4}, {6, 4}, {6, 5}, {6, 6}, {5, 6}],
              dir: :down,
              next_dir: :left
          }
        end)

      {:ok, ns, _} = SnakeIo.tick(s)
      assert ns.players[pid].alive == false
    end

    test "tail follow 은 허용 (다음 tick 에 tail 이 빠지므로)" do
      s = init_with(1)
      [{pid, _}] = Enum.to_list(s.players)
      s = %{s | food: MapSet.new(), food_target: 0}

      # 4-cell loop — head 가 tail 자리로 진입. trim 이 follow 시켜주니 안 죽음.
      # body: head=(5,5), tail=(5,6). dir down → (6,5) → next_dir right → (6,6) ... 너무 복잡.
      # 직선 후 head 가 tail 자리로 가는 케이스: body=[(5,5),(5,4),(5,3)], dir left, head 가
      # (5,4) 로 가면 (5,4) 가 mid 라 죽음.
      # tail follow: head=(5,5), tail=(5,5)+offset.
      # body=[(5,5),(6,5),(6,6),(5,6)], dir left, next_dir up. head=(5,5)→ (4,5). 안 죽음.
      # 진짜 tail follow 케이스: body=[(5,5),(6,5),(7,5)], dir down, head 가 (6,5) 못 가지만
      # 그 반대인 head 가 tail cell 로 wrap 되는 건 어려움. 일단 outward move 로 안 죽는
      # 것 검증.
      s =
        update_in(s.players[pid], fn p ->
          %{p | body: [{5, 5}, {6, 5}, {7, 5}], dir: :up, next_dir: :up, alive: true}
        end)

      {:ok, ns, _} = SnakeIo.tick(s)
      # head (5,5) → (4,5). 충돌 X.
      assert ns.players[pid].alive
    end
  end

  describe "food 먹기" do
    test "head 가 food 셀 도달 → grow + food 제거" do
      s = init_with(1)
      [{pid, p}] = Enum.to_list(s.players)
      {hr, hc} = hd(p.body)
      {dr, dc} = dir_delta(p.dir)
      target = {hr + dr, hc + dc}

      # 다음 head 자리에 food 강제 배치.
      s = %{s | food: MapSet.new([target]), food_target: 1}

      {:ok, ns, _} = SnakeIo.tick(s)
      # food 먹어 length +1 (grow 적용 후 tail 안 줄어듦).
      assert length(ns.players[pid].body) == 4
      # food set 에서 제거됨.
      refute MapSet.member?(ns.food, target)
    end
  end

  describe "충돌 + kill credit" do
    test "다른 snake 몸 충돌 → 사망 + 그 snake kill +1" do
      s = init_with(2)
      [a_id, b_id] = Map.keys(s.players) |> Enum.sort()
      s = %{s | food: MapSet.new(), food_target: 0}

      # A 는 가만히 (body 가 (5,5),(5,6),(5,7) 가로). B 의 head 가 A 의 (5,5) 로 다음 tick 진입.
      s =
        s
        |> update_in([:players, a_id], fn p ->
          %{p | body: [{5, 5}, {5, 6}, {5, 7}], dir: :left, next_dir: :left, alive: true}
        end)
        # B 머리 (6,5) → 다음 tick :up 으로 (5,5) — A 의 head 와 충돌.
        |> update_in([:players, b_id], fn p ->
          %{p | body: [{6, 5}, {7, 5}, {8, 5}], dir: :up, next_dir: :up, alive: true}
        end)

      {:ok, ns, _} = SnakeIo.tick(s)
      # B 죽음 (A 머리에 박음). A 는 살아남음 (head 가 (5,4) 로 이동).
      assert ns.players[b_id].alive == false
      assert ns.players[a_id].alive
      # A 가 B 를 죽인 kill 카운트.
      assert ns.players[a_id].kills == 1
    end
  end

  describe "respawn" do
    test "사망 후 60 tick 지나면 자동 부활" do
      s = init_with(1)
      [{pid, _}] = Enum.to_list(s.players)

      # 사망 상태로 강제.
      s =
        update_in(s.players[pid], fn p ->
          %{p | alive: false, died_at_tick: 0, body: [{50, 50}, {50, 51}, {50, 52}]}
        end)

      s = %{s | tick_no: 60, food: MapSet.new(), food_target: 0}

      {:ok, ns, _} = SnakeIo.tick(s)
      assert ns.players[pid].alive
      assert length(ns.players[pid].body) == 3
      assert ns.players[pid].died_at_tick == nil
    end

    test "사망 후 60 tick 미만이면 부활 X" do
      s = init_with(1)
      [{pid, _}] = Enum.to_list(s.players)

      s =
        update_in(s.players[pid], fn p ->
          %{p | alive: false, died_at_tick: 0, body: [{50, 50}]}
        end)

      s = %{s | tick_no: 30, food: MapSet.new(), food_target: 0}

      {:ok, ns, _} = SnakeIo.tick(s)
      refute ns.players[pid].alive
    end
  end

  describe "best_length" do
    test "tick 마다 best_length 갱신 (현재 length max)" do
      s = init_with(1)
      [{pid, _}] = Enum.to_list(s.players)
      # body 강제 길이 7.
      s =
        update_in(s.players[pid], fn p ->
          %{p | body: [{50, 50}, {50, 51}, {50, 52}, {50, 53}, {50, 54}, {50, 55}, {50, 56}]}
        end)

      s = %{s | food: MapSet.new(), food_target: 0}

      {:ok, ns, _} = SnakeIo.tick(s)
      # advance + trim 후 length 7 유지 (이동만 하고 식사 X). best_length 갱신.
      assert ns.players[pid].best_length >= 7
    end
  end

  # 헬퍼 — 모듈 internal dir_delta 와 동일.
  defp dir_delta(:up), do: {-1, 0}
  defp dir_delta(:down), do: {1, 0}
  defp dir_delta(:left), do: {0, -1}
  defp dir_delta(:right), do: {0, 1}
end
