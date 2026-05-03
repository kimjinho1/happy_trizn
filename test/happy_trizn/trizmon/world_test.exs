defmodule HappyTrizn.Trizmon.WorldTest do
  use ExUnit.Case, async: true

  alias HappyTrizn.Trizmon.World

  describe "맵 lookup" do
    test "starting_town 존재" do
      map = World.get_map("starting_town")
      assert map.id == "starting_town"
      assert map.name == "시작 마을"
      assert map.width == 16
      assert map.height == 12
    end

    test "없는 맵 → starting_town fallback" do
      assert World.get_map("ghost_map").id == "starting_town"
      assert World.get_map(nil).id == "starting_town"
    end

    test "spawn 위치 walkable" do
      map = World.get_map("starting_town")
      {sx, sy} = map.spawn
      tile = World.tile_at(map, sx, sy)
      assert World.walkable?(tile)
    end
  end

  describe "tile_at/3 + walkable?/1" do
    test "범위 밖 → :wall (걷기 X)" do
      map = World.get_map("starting_town")
      assert World.tile_at(map, -1, 0) == :wall
      assert World.tile_at(map, 999, 0) == :wall
      assert World.tile_at(map, 0, -1) == :wall
    end

    test "walkable types" do
      assert World.walkable?(:grass)
      assert World.walkable?(:path)
      assert World.walkable?(:tall_grass)
      assert World.walkable?(:sand)
      assert World.walkable?(:door)
    end

    test "non-walkable types" do
      refute World.walkable?(:wall)
      refute World.walkable?(:water)
      refute World.walkable?(:npc)
    end
  end

  describe "try_move/4" do
    test "정상 이동" do
      map = World.get_map("starting_town")
      {sx, sy} = map.spawn

      # spawn (7, 9) — 사방 walkable 확인 후 이동.
      cases = [:up, :down, :left, :right]

      results =
        Enum.map(cases, fn dir ->
          {dir, World.try_move(map, sx, sy, dir)}
        end)

      # 적어도 한 방향 이동 가능해야 (spawn 이 유효).
      assert Enum.any?(results, fn {_, r} -> match?({:ok, _, _}, r) end)
    end

    test "벽 충돌 → :blocked" do
      map = World.get_map("starting_town")
      # (0, 0) = 벽. up/left → :blocked
      assert World.try_move(map, 0, 0, :up) == :blocked
      assert World.try_move(map, 0, 0, :left) == :blocked
    end
  end

  describe "encounter_tile?/1 + roll_encounter/4" do
    test "tall_grass 만 인카운터 가능" do
      assert World.encounter_tile?(:tall_grass)
      refute World.encounter_tile?(:grass)
      refute World.encounter_tile?(:path)
    end

    test "rate 100 + tall_grass → 항상 species 반환" do
      map = World.get_map("starting_town")
      # row 1 col 1 = :tall_grass.
      result = World.roll_encounter(map, 1, 1, rate: 100)
      assert is_binary(result)
      assert result in map.encounter_pool
    end

    test "rate 0 → 항상 nil" do
      map = World.get_map("starting_town")
      assert World.roll_encounter(map, 1, 1, rate: 0) == nil
    end

    test "tall_grass 아닌 곳 → 항상 nil" do
      map = World.get_map("starting_town")
      # spawn (7, 9) = grass 또는 path
      assert World.roll_encounter(map, 7, 9, rate: 100) == nil
    end
  end

  describe "NPC (Sprint 5c-3c)" do
    test "npc_at — 정확한 좌표" do
      assert %{id: "town_elder", type: :greeter} = World.npc_at("starting_town", 6, 7)
      assert %{id: "first_trainer", type: :trainer} = World.npc_at("starting_town", 11, 7)
    end

    test "npc_at — NPC 없는 좌표 → nil" do
      assert World.npc_at("starting_town", 0, 0) == nil
      assert World.npc_at("ghost_map", 6, 7) == nil
    end

    test "npc_by_id — id 로 lookup" do
      assert %{name: "마을 어른"} = World.npc_by_id("town_elder")
      assert %{name: "트레이너 민수"} = World.npc_by_id("first_trainer")
      assert World.npc_by_id("nonexistent") == nil
    end

    test "adjacent_npc — 4 방향 검사 (town_elder at (6,7))" do
      assert {6, 7, %{id: "town_elder"}} = World.adjacent_npc("starting_town", 5, 7)
      assert {6, 7, %{id: "town_elder"}} = World.adjacent_npc("starting_town", 7, 7)
      assert {6, 7, %{id: "town_elder"}} = World.adjacent_npc("starting_town", 6, 6)
      assert {6, 7, %{id: "town_elder"}} = World.adjacent_npc("starting_town", 6, 8)
    end

    test "adjacent_npc — 멀리 → nil" do
      assert World.adjacent_npc("starting_town", 0, 0) == nil
    end

    test "트레이너 party 정의됨" do
      trainer = World.npc_by_id("first_trainer")
      assert is_list(trainer.party)
      assert length(trainer.party) >= 1
      assert is_binary(hd(trainer.party))
    end
  end

  describe "render_payload/1" do
    test "tile atom → string list 변환" do
      map = World.get_map("starting_town")
      payload = World.render_payload(map)

      assert payload.id == "starting_town"
      assert payload.width == 16
      assert payload.height == 12
      assert is_list(payload.tiles)
      assert is_binary(payload.tiles |> hd() |> hd())
      assert payload.spawn == [7, 9]
    end
  end
end
