defmodule HappyTrizn.Games.Bomberman do
  @moduledoc """
  Bomberman — 4인 격자 폭탄.

  ## 격자 13×11 (col × row)

  - 외벽 (테두리): :wall (파괴 불가)
  - 짝수 row + 짝수 col 안쪽 칸: :wall (체커보드 패턴)
  - 그 외 빈 칸 일부: :block (파괴 가능)
  - 4 spawn corners + 인접 칸: 항상 :empty (시작 위치 보장)

  ## State

      status: :waiting / :playing / :over
      grid: 11×13 list of list — :wall | :block | :empty
      players: %{id => %{nickname, row, col, alive, bomb_max, bomb_range, kick?, dead_at}}
      bombs: %{{row,col} => %{owner, fuse_ms, range}}
      explosions: list of %{cells, ttl_ms, owner}
      items: %{{row,col} => :bomb_up | :range_up | :speed_up | :kick}
      winner_id

  ## Tick (50ms)

  - bomb fuse 감소, 0 이하 → 폭발 (chain reaction)
  - explosion ttl 감소, 0 → 사라짐
  - 폭발 cell 위 player → 사망
  - alive 1명 (또는 0명) + :playing → :over

  ## Actions

      "start_game" — :waiting + 2명 이상 → :playing
      "move" {dir: "up"|"down"|"left"|"right"}
      "place_bomb" — bomb_max 안 초과 시 현 위치 폭탄
  """

  @behaviour HappyTrizn.Games.GameBehaviour

  @tick_ms 50
  @rows 11
  @cols 13
  @bomb_fuse_ms 3000
  @explosion_ttl_ms 400
  @item_drop_chance 0.2
  @max_players 4

  @spawn_corners [{1, 1}, {1, 11}, {9, 1}, {9, 11}]

  def rows, do: @rows
  def cols, do: @cols

  # ============================================================================
  # GameBehaviour
  # ============================================================================

  @impl true
  def meta do
    %{
      name: "Bomberman",
      slug: "bomberman",
      mode: :multi,
      max_players: @max_players,
      min_players: 2,
      description: "4인 격자 폭탄",
      tick_interval_ms: @tick_ms
    }
  end

  @impl true
  def init(_) do
    {:ok,
     %{
       status: :waiting,
       grid: empty_grid(),
       players: %{},
       bombs: %{},
       explosions: [],
       items: %{},
       winner_id: nil
     }}
  end

  # ============================================================================
  # Player join / leave
  # ============================================================================

  @impl true
  def handle_player_join(player_id, meta, state) do
    cond do
      Map.has_key?(state.players, player_id) ->
        {:ok, state, []}

      map_size(state.players) >= @max_players ->
        {:reject, :full}

      state.status == :playing ->
        {:reject, :in_progress}

      true ->
        nickname = Map.get(meta, :nickname, "anon")
        {row, col} = Enum.at(@spawn_corners, map_size(state.players))

        player = %{
          nickname: nickname,
          row: row,
          col: col,
          alive: true,
          bomb_max: 1,
          bomb_range: 2,
          kick?: false,
          dead_at: nil
        }

        new_players = Map.put(state.players, player_id, player)
        {:ok, %{state | players: new_players}, [{:player_joined, player_id}]}
    end
  end

  @impl true
  def handle_player_leave(player_id, _reason, state) do
    new_players = Map.delete(state.players, player_id)
    new_bombs = Map.reject(state.bombs, fn {_, b} -> b.owner == player_id end)
    new_state = %{state | players: new_players, bombs: new_bombs}

    cond do
      map_size(new_players) == 0 ->
        {:ok, %{new_state | status: :over}, [{:player_left, player_id}]}

      state.status == :playing and count_alive(new_players) <= 1 ->
        winner = highest_alive(new_players)

        {:ok, %{new_state | status: :over, winner_id: winner},
         [{:player_left, player_id}, {:game_finished, %{winner: winner}}]}

      true ->
        {:ok, new_state, [{:player_left, player_id}]}
    end
  end

  # ============================================================================
  # Actions
  # ============================================================================

  @impl true
  def handle_input(player_id, %{"action" => "start_game"}, state) do
    cond do
      state.status not in [:waiting, :over] -> {:ok, state, []}
      map_size(state.players) < 2 -> {:ok, state, []}
      not Map.has_key?(state.players, player_id) -> {:ok, state, []}
      true -> start_game(state)
    end
  end

  def handle_input(player_id, %{"action" => "move", "dir" => dir}, state) do
    with %{} = player <- Map.get(state.players, player_id),
         true <- player.alive,
         :playing <- state.status,
         {dr, dc} when not is_nil(dr) <- direction(dir) do
      new_row = player.row + dr
      new_col = player.col + dc

      if walkable?(state, new_row, new_col) do
        # 아이템 줍기.
        {pickup_item, new_items} = Map.pop(state.items, {new_row, new_col})

        new_player =
          player
          |> Map.put(:row, new_row)
          |> Map.put(:col, new_col)
          |> apply_item(pickup_item)

        new_state = %{
          state
          | players: Map.put(state.players, player_id, new_player),
            items: new_items
        }

        new_state = check_player_on_explosion(new_state, player_id)

        broadcasts =
          [{:player_moved, %{player: player_id, row: new_row, col: new_col}}] ++
            if pickup_item,
              do: [{:item_picked, %{player: player_id, kind: pickup_item}}],
              else: []

        {:ok, new_state, broadcasts}
      else
        {:ok, state, []}
      end
    else
      _ -> {:ok, state, []}
    end
  end

  def handle_input(player_id, %{"action" => "place_bomb"}, state) do
    with %{} = player <- Map.get(state.players, player_id),
         true <- player.alive,
         :playing <- state.status,
         true <- can_place_bomb?(state, player_id, player) do
      bomb = %{owner: player_id, fuse_ms: @bomb_fuse_ms, range: player.bomb_range}
      new_bombs = Map.put(state.bombs, {player.row, player.col}, bomb)

      {:ok, %{state | bombs: new_bombs},
       [{:bomb_placed, %{row: player.row, col: player.col, owner: player_id}}]}
    else
      _ -> {:ok, state, []}
    end
  end

  def handle_input(_, _, state), do: {:ok, state, []}

  # ============================================================================
  # Tick
  # ============================================================================

  @impl true
  def tick(%{status: :playing} = state) do
    {state, b1} = tick_bombs(state)
    state = tick_explosions(state)
    state = check_all_players_on_explosion(state)
    {state, b2} = check_game_over(state)
    {:ok, state, b1 ++ b2}
  end

  def tick(state), do: {:ok, state, []}

  # ============================================================================
  # Game over
  # ============================================================================

  @impl true
  def game_over?(%{status: :over} = state) do
    public_players =
      Map.new(state.players, fn {id, p} ->
        {id, %{nickname: p.nickname, alive: p.alive}}
      end)

    {:yes, %{winner: state.winner_id, players: public_players}}
  end

  def game_over?(_), do: :no

  @impl true
  def terminate(_, _), do: :ok

  # ============================================================================
  # Game start
  # ============================================================================

  defp start_game(state) do
    grid = build_grid()

    reset_players =
      state.players
      |> Map.to_list()
      |> Enum.with_index()
      |> Map.new(fn {{id, p}, idx} ->
        {row, col} = Enum.at(@spawn_corners, idx, {1, 1})

        new_p = %{
          p
          | row: row,
            col: col,
            alive: true,
            bomb_max: 1,
            bomb_range: 2,
            kick?: false,
            dead_at: nil
        }

        {id, new_p}
      end)

    new_state = %{
      state
      | grid: grid,
        players: reset_players,
        bombs: %{},
        explosions: [],
        items: %{},
        winner_id: nil,
        status: :playing
    }

    {:ok, new_state, [{:game_started, %{}}]}
  end

  # ============================================================================
  # Grid builder
  # ============================================================================

  defp empty_grid do
    for _ <- 1..@rows, do: List.duplicate(:empty, @cols)
  end

  defp build_grid do
    safe = MapSet.new(spawn_safe_zone())

    for r <- 0..(@rows - 1) do
      for c <- 0..(@cols - 1) do
        cond do
          # 외벽
          r == 0 or r == @rows - 1 or c == 0 or c == @cols - 1 -> :wall
          # 체커보드 안쪽 wall
          rem(r, 2) == 0 and rem(c, 2) == 0 -> :wall
          # spawn safe zone
          {r, c} in safe -> :empty
          # 70% block
          :rand.uniform() < 0.7 -> :block
          true -> :empty
        end
      end
    end
  end

  defp spawn_safe_zone do
    Enum.flat_map(@spawn_corners, fn {r, c} ->
      [{r, c}, {r + 1, c}, {r - 1, c}, {r, c + 1}, {r, c - 1}]
    end)
  end

  # ============================================================================
  # Movement
  # ============================================================================

  defp direction("up"), do: {-1, 0}
  defp direction("down"), do: {1, 0}
  defp direction("left"), do: {0, -1}
  defp direction("right"), do: {0, 1}
  defp direction(_), do: nil

  defp walkable?(state, row, col) do
    cond do
      row < 0 or row >= @rows or col < 0 or col >= @cols -> false
      cell_at(state.grid, row, col) != :empty -> false
      Map.has_key?(state.bombs, {row, col}) -> false
      true -> true
    end
  end

  defp cell_at(grid, row, col) do
    grid |> Enum.at(row) |> Enum.at(col)
  end

  # ============================================================================
  # Items
  # ============================================================================

  defp apply_item(player, nil), do: player
  defp apply_item(player, :bomb_up), do: %{player | bomb_max: player.bomb_max + 1}
  defp apply_item(player, :range_up), do: %{player | bomb_range: player.bomb_range + 1}
  defp apply_item(player, :speed_up), do: player
  defp apply_item(player, :kick), do: %{player | kick?: true}
  defp apply_item(player, _), do: player

  defp random_item, do: Enum.random([:bomb_up, :range_up, :speed_up, :kick])

  # ============================================================================
  # Bombs / explosions
  # ============================================================================

  defp can_place_bomb?(state, player_id, player) do
    not Map.has_key?(state.bombs, {player.row, player.col}) and
      count_my_bombs(state, player_id) < player.bomb_max
  end

  defp count_my_bombs(state, player_id) do
    Enum.count(state.bombs, fn {_, b} -> b.owner == player_id end)
  end

  defp tick_bombs(state) do
    {new_bombs, exploded} =
      Enum.reduce(state.bombs, {%{}, []}, fn {pos, bomb}, {acc, exp} ->
        new_fuse = bomb.fuse_ms - @tick_ms

        if new_fuse <= 0 do
          {acc, [{pos, bomb} | exp]}
        else
          {Map.put(acc, pos, %{bomb | fuse_ms: new_fuse}), exp}
        end
      end)

    state = %{state | bombs: new_bombs}
    process_explosions(state, exploded, [])
  end

  defp process_explosions(state, [], broadcasts), do: {state, broadcasts}

  defp process_explosions(state, [{{row, col}, bomb} | rest], broadcasts) do
    {cells, destroyed_blocks, chain_bombs} = compute_explosion_cells(state, row, col, bomb.range)

    new_grid =
      Enum.reduce(destroyed_blocks, state.grid, fn {br, bc}, g ->
        replace_cell(g, br, bc, :empty)
      end)

    new_items =
      Enum.reduce(destroyed_blocks, state.items, fn {br, bc}, items ->
        if :rand.uniform() < @item_drop_chance,
          do: Map.put(items, {br, bc}, random_item()),
          else: items
      end)

    explosion = %{cells: cells, ttl_ms: @explosion_ttl_ms, owner: bomb.owner}

    new_state = %{
      state
      | grid: new_grid,
        items: new_items,
        explosions: [explosion | state.explosions]
    }

    bcs = broadcasts ++ [{:bomb_exploded, %{row: row, col: col, cells: cells, owner: bomb.owner}}]

    chain = Enum.map(chain_bombs, fn pos -> {pos, Map.get(state.bombs, pos)} end)
    new_bombs = Map.drop(new_state.bombs, chain_bombs)
    new_state = %{new_state | bombs: new_bombs}

    process_explosions(new_state, rest ++ chain, bcs)
  end

  defp compute_explosion_cells(state, row, col, range) do
    initial = {[{row, col}], [], []}

    Enum.reduce([{-1, 0}, {1, 0}, {0, -1}, {0, 1}], initial, fn {dr, dc}, acc ->
      ray_explosion(state, row, col, dr, dc, range, acc)
    end)
  end

  defp ray_explosion(_state, _r, _c, _dr, _dc, 0, acc), do: acc

  defp ray_explosion(state, r, c, dr, dc, n, {cells, blocks, chains}) do
    nr = r + dr
    nc = c + dc

    cond do
      nr < 0 or nr >= @rows or nc < 0 or nc >= @cols ->
        {cells, blocks, chains}

      cell_at(state.grid, nr, nc) == :wall ->
        {cells, blocks, chains}

      cell_at(state.grid, nr, nc) == :block ->
        {[{nr, nc} | cells], [{nr, nc} | blocks], chains}

      Map.has_key?(state.bombs, {nr, nc}) ->
        {[{nr, nc} | cells], blocks, [{nr, nc} | chains]}

      true ->
        ray_explosion(state, nr, nc, dr, dc, n - 1, {[{nr, nc} | cells], blocks, chains})
    end
  end

  defp tick_explosions(state) do
    new_explosions =
      state.explosions
      |> Enum.map(&%{&1 | ttl_ms: &1.ttl_ms - @tick_ms})
      |> Enum.reject(&(&1.ttl_ms <= 0))

    %{state | explosions: new_explosions}
  end

  defp check_all_players_on_explosion(state) do
    Enum.reduce(state.players, state, fn {id, _}, acc -> check_player_on_explosion(acc, id) end)
  end

  defp check_player_on_explosion(state, player_id) do
    player = Map.get(state.players, player_id)

    if player && player.alive && in_explosion?(state, player.row, player.col) do
      put_in(state.players[player_id].alive, false)
      |> put_in([Access.key(:players), player_id, Access.key(:dead_at)], now_ms())
    else
      state
    end
  end

  defp in_explosion?(state, row, col) do
    Enum.any?(state.explosions, fn e -> {row, col} in e.cells end)
  end

  # ============================================================================
  # Game over check
  # ============================================================================

  defp check_game_over(state) do
    alive = count_alive(state.players)

    cond do
      state.status != :playing ->
        {state, []}

      alive == 0 ->
        {%{state | status: :over, winner_id: nil}, [{:game_finished, %{winner: nil}}]}

      alive == 1 ->
        winner = highest_alive(state.players)
        {%{state | status: :over, winner_id: winner}, [{:game_finished, %{winner: winner}}]}

      true ->
        {state, []}
    end
  end

  # ============================================================================
  # Helpers
  # ============================================================================

  defp count_alive(players), do: Enum.count(players, fn {_, p} -> p.alive end)

  defp highest_alive(players) do
    case Enum.find(players, fn {_, p} -> p.alive end) do
      {id, _} -> id
      _ -> nil
    end
  end

  defp replace_cell(grid, row, col, value) do
    new_row = grid |> Enum.at(row) |> List.replace_at(col, value)
    List.replace_at(grid, row, new_row)
  end

  defp now_ms, do: System.monotonic_time(:millisecond)
end
