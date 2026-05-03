defmodule HappyTrizn.Trizmon.World do
  @moduledoc """
  모험 모드 맵 데이터 + 충돌 / 인카운터 trigger (Sprint 5c-3a).

  spec: docs/TRIZMON_SPEC.md §9

  Tile types:
    :grass — 일반 길 (걷기 가능)
    :path — 마을 길 (걷기 가능, 인카운터 X)
    :wall — 벽 / 나무 (걷기 X)
    :tall_grass — 풀숲 (걷기 가능, 인카운터 8% 확률)
    :door — 건물 입구 (걷기 가능, 추후 맵 전환)
    :npc — NPC 위치 (걷기 X, 말하기 가능)
    :water — 물 (걷기 X)
    :sand — 모래 (걷기 가능)

  Map = %{id, name, width, height, tiles: [[atom, ...]], spawn: {x, y},
          encounter_pool: [species_slug, ...]}.

  NPC: (map_id, {x, y}) → spec.
    type: :greeter | :trainer
    greeter: dialog
    trainer: greeting + party (species_slug list) + win_text + lose_text
  """

  @npcs %{
    {"starting_town", {6, 7}} => %{
      id: "town_elder",
      name: "마을 어른",
      type: :greeter,
      dialog: "어서 와! 시작 마을이야. 풀숲을 조심해 — 야생 트리즈몬이 자주 나와."
    },
    {"starting_town", {11, 7}} => %{
      id: "first_trainer",
      name: "트레이너 민수",
      type: :trainer,
      greeting: "어이! 너 트리즈몬 트레이너 같은데 한 판 어때?",
      party: ["normalmon-001", "voltmon-001"],
      win_text: "너 강하네! 다음에 또 보자.",
      lose_text: "이런... 좀 더 수련해야겠어."
    }
  }

  @maps %{
    "starting_town" => %{
      id: "starting_town",
      name: "시작 마을",
      width: 16,
      height: 12,
      spawn: {7, 9},
      encounter_pool: ["normalmon-001", "bugmon-001", "voltmon-001"],
      tiles:
        [
          # row 0 (top wall)
          [:wall, :wall, :wall, :wall, :wall, :wall, :wall, :wall, :wall, :wall, :wall, :wall, :wall, :wall, :wall, :wall],
          # row 1 (북쪽 풀숲 region)
          [:wall, :tall_grass, :tall_grass, :tall_grass, :tall_grass, :tall_grass, :grass, :path, :grass, :tall_grass, :tall_grass, :tall_grass, :tall_grass, :tall_grass, :tall_grass, :wall],
          # row 2
          [:wall, :tall_grass, :grass, :grass, :grass, :tall_grass, :grass, :path, :grass, :tall_grass, :grass, :grass, :grass, :tall_grass, :grass, :wall],
          # row 3
          [:wall, :grass, :grass, :wall, :grass, :grass, :grass, :path, :grass, :grass, :grass, :wall, :grass, :grass, :grass, :wall],
          # row 4 (water)
          [:wall, :grass, :grass, :wall, :wall, :grass, :grass, :path, :grass, :water, :water, :wall, :wall, :grass, :grass, :wall],
          # row 5 (마을 시작)
          [:wall, :path, :path, :path, :path, :path, :path, :path, :path, :path, :path, :path, :path, :path, :path, :wall],
          # row 6 (집)
          [:wall, :path, :wall, :wall, :path, :wall, :wall, :wall, :wall, :path, :wall, :wall, :wall, :wall, :path, :wall],
          # row 7 (집 입구)
          [:wall, :path, :wall, :door, :path, :wall, :npc, :path, :wall, :door, :wall, :npc, :path, :wall, :path, :wall],
          # row 8
          [:wall, :path, :path, :path, :path, :path, :path, :path, :path, :path, :path, :path, :path, :path, :path, :wall],
          # row 9 (spawn)
          [:wall, :grass, :grass, :path, :grass, :grass, :grass, :path, :grass, :grass, :grass, :path, :grass, :grass, :grass, :wall],
          # row 10
          [:wall, :grass, :grass, :path, :grass, :grass, :grass, :path, :grass, :grass, :grass, :path, :grass, :grass, :grass, :wall],
          # row 11 (bottom wall)
          [:wall, :wall, :wall, :wall, :wall, :wall, :wall, :wall, :wall, :wall, :wall, :wall, :wall, :wall, :wall, :wall]
        ]
    }
  }

  @doc "맵 id list."
  def map_ids, do: Map.keys(@maps)

  @doc "맵 lookup. nil 이면 starting_town fallback."
  def get_map(id) when is_binary(id) do
    Map.get(@maps, id) || Map.fetch!(@maps, "starting_town")
  end

  def get_map(_), do: Map.fetch!(@maps, "starting_town")

  @doc "특정 좌표 tile 반환."
  def tile_at(map, x, y) do
    cond do
      x < 0 or y < 0 or x >= map.width or y >= map.height -> :wall
      true -> map.tiles |> Enum.at(y) |> Enum.at(x)
    end
  end

  @doc "그 tile 걷기 가능?"
  def walkable?(tile) when tile in [:grass, :path, :tall_grass, :sand, :door], do: true
  def walkable?(_), do: false

  @doc "인카운터 trigger 가능한 tile?"
  def encounter_tile?(:tall_grass), do: true
  def encounter_tile?(_), do: false

  @doc """
  이동 시도 — (map, x, y, dir) → {:ok, new_x, new_y} | :blocked.
  dir = :up | :down | :left | :right
  """
  def try_move(map, x, y, dir) do
    {dx, dy} = delta(dir)
    nx = x + dx
    ny = y + dy

    if walkable?(tile_at(map, nx, ny)) do
      {:ok, nx, ny}
    else
      :blocked
    end
  end

  defp delta(:up), do: {0, -1}
  defp delta(:down), do: {0, 1}
  defp delta(:left), do: {-1, 0}
  defp delta(:right), do: {1, 0}
  defp delta(_), do: {0, 0}

  @doc """
  step 마다 인카운터 roll. encounter_tile? + 8% 확률 → species_slug 반환.
  default rate 8% (포켓몬 컨벤션 기준).
  """
  def roll_encounter(map, x, y, opts \\ []) do
    rate = Keyword.get(opts, :rate, 8)
    pool = map.encounter_pool || []

    cond do
      pool == [] -> nil
      not encounter_tile?(tile_at(map, x, y)) -> nil
      :rand.uniform(100) > rate -> nil
      true -> Enum.random(pool)
    end
  end

  @doc "특정 (map_id, x, y) 의 NPC. 없으면 nil."
  def npc_at(map_id, x, y) when is_binary(map_id) do
    Map.get(@npcs, {map_id, {x, y}})
  end

  def npc_at(_, _, _), do: nil

  @doc "id → npc spec (트레이너 battle 진입 시 lookup)."
  def npc_by_id(id) when is_binary(id) do
    @npcs
    |> Map.values()
    |> Enum.find(fn npc -> npc.id == id end)
  end

  def npc_by_id(_), do: nil

  @doc """
  플레이어 인접 4 방향 NPC 찾기. {x, y, npc} 또는 nil.
  """
  def adjacent_npc(map_id, x, y) when is_binary(map_id) do
    [{x, y - 1}, {x, y + 1}, {x - 1, y}, {x + 1, y}]
    |> Enum.find_value(fn {nx, ny} ->
      case npc_at(map_id, nx, ny) do
        nil -> nil
        npc -> {nx, ny, npc}
      end
    end)
  end

  def adjacent_npc(_, _, _), do: nil

  @doc """
  client 전송용 payload — tiles + spawn + encounter_pool 등.
  JSON 직렬화 가능 (tile atom → string).
  """
  def render_payload(map) do
    %{
      id: map.id,
      name: map.name,
      width: map.width,
      height: map.height,
      tiles: Enum.map(map.tiles, fn row -> Enum.map(row, &Atom.to_string/1) end),
      spawn: Tuple.to_list(map.spawn),
      encounter_pool: map.encounter_pool
    }
  end
end
