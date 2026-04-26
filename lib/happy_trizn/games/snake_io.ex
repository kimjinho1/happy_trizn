defmodule HappyTrizn.Games.SnakeIo do
  @moduledoc """
  Snake.io — 캐주얼 멀티 (자유 입퇴장, max 16인).

  ## 게임 규칙

  - 100×100 격자. 자유 입퇴장 (lobby 없음). 항상 :playing.
  - 50ms tick (≒ 20fps). 매 tick 살아있는 snake 의 head 가 dir 방향으로 1 칸 전진.
  - food 먹으면 length +1 (tail 안 줄어듦). food 위치는 매 tick 항상 N개 유지.
  - 충돌 (벽 / 자기 몸 / 다른 snake 몸) → 사망. 몸 길이만큼 food drop.
  - 사망 후 3초 (60 tick) 뒤 랜덤 위치 자동 respawn (length 3, 랜덤 dir).
  - score = best_length (지금까지 도달한 최대 길이).
  - `game_over?` 항상 `:no` — 캐주얼 모드라 절대 끝나지 않음.

  ## state

      %{
        status: :playing,
        tick_no: int,                       # tick 카운터 (respawn 타이밍 등)
        grid_size: 100,
        food: MapSet of {r, c},
        food_target: int,                   # 항상 유지할 food 개수.
        players: %{
          player_id => %{
            nickname,
            color: hex string,
            body: [{r, c}, ...],            # head → tail.
            dir: :up | :down | :left | :right,
            next_dir,                       # client input 큐. tick 에서 dir 로 적용.
            alive: bool,
            grow: int,                      # 양수면 다음 tick 에서 tail 안 줄임 (성장).
            best_length: int,               # 사망 전 도달한 최대 length.
            died_at_tick: int | nil,
            kills: int
          }
        }
      }

  ## Actions

      "set_dir" %{"dir" => "up"|"down"|"left"|"right"}
        → next_dir 큐. 다음 tick 에서 적용. 180도 방향 전환은 무시 (자기 머리 박는 거 방지).
  """

  @behaviour HappyTrizn.Games.GameBehaviour

  @grid_size 100
  @tick_ms 50
  @max_players 16
  @initial_length 3
  @respawn_ticks 60
  @food_per_player 5
  @food_min 30

  @colors ~w(
    #ef4444 #3b82f6 #22c55e #facc15 #a855f7 #ec4899 #06b6d4 #f97316
    #84cc16 #14b8a6 #6366f1 #f43f5e #eab308 #8b5cf6 #10b981 #d946ef
  )

  def grid_size, do: @grid_size

  # ============================================================================
  # GameBehaviour
  # ============================================================================

  @impl true
  def meta do
    %{
      name: "Snake.io",
      slug: "snake_io",
      mode: :multi,
      max_players: @max_players,
      min_players: 1,
      description: "100×100 캐주얼 자유 입퇴장",
      tick_interval_ms: @tick_ms
    }
  end

  @impl true
  def init(_) do
    state = %{
      status: :playing,
      tick_no: 0,
      grid_size: @grid_size,
      food: MapSet.new(),
      food_target: @food_min,
      players: %{}
    }

    {:ok, ensure_food(state)}
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

      true ->
        nickname = Map.get(meta, :nickname, "anon")
        color = pick_color(state.players)

        # spawn — 빈 셀 찾고 그쪽에 길이 3 의 snake 배치.
        {body, dir} = pick_spawn(state)

        player = %{
          nickname: nickname,
          color: color,
          body: body,
          dir: dir,
          next_dir: dir,
          alive: true,
          grow: 0,
          best_length: length(body),
          died_at_tick: nil,
          kills: 0
        }

        new_players = Map.put(state.players, player_id, player)
        new_target = max(@food_min, map_size(new_players) * @food_per_player)
        new_state = %{state | players: new_players, food_target: new_target}
        {:ok, ensure_food(new_state), [{:player_joined, player_id}]}
    end
  end

  @impl true
  def handle_player_leave(player_id, _reason, state) do
    case Map.fetch(state.players, player_id) do
      :error ->
        {:ok, state, [{:player_left, player_id}]}

      {:ok, p} ->
        # 떠난 player body 를 food 로 일부 흩뿌림 (재미용).
        new_food =
          p.body
          |> Enum.take_every(2)
          |> Enum.reduce(state.food, &MapSet.put(&2, &1))

        new_players = Map.delete(state.players, player_id)
        new_target = max(@food_min, map_size(new_players) * @food_per_player)

        {:ok, %{state | players: new_players, food: new_food, food_target: new_target},
         [{:player_left, player_id}]}
    end
  end

  # ============================================================================
  # Actions
  # ============================================================================

  @impl true
  def handle_input(player_id, %{"action" => "set_dir", "dir" => dir_s}, state) do
    with %{} = player <- Map.get(state.players, player_id),
         true <- player.alive,
         {:ok, new_dir} <- parse_dir(dir_s),
         true <- not opposite?(player.dir, new_dir) do
      new_p = %{player | next_dir: new_dir}
      {:ok, %{state | players: Map.put(state.players, player_id, new_p)}, []}
    else
      _ -> {:ok, state, []}
    end
  end

  def handle_input(_, _, state), do: {:ok, state, []}

  # ============================================================================
  # Tick
  # ============================================================================

  @impl true
  def tick(state) do
    state = %{state | tick_no: state.tick_no + 1}

    # 1. dir → next_dir 적용 + head 1칸 전진.
    state = advance_heads(state)

    # 2. 충돌 판정 (벽 / 자기 몸 / 타 snake 몸). 사망 처리 + food drop.
    state = resolve_collisions(state)

    # 3. food 먹기 (head 가 food 셀에 있으면 먹음 → grow+1, food 제거).
    state = eat_food(state)

    # 4. tail 줄임 (grow 가 0 보다 크면 안 줄이고 grow-1, 아니면 tail pop).
    state = trim_tails(state)

    # 5. 죽은 snake 자동 respawn (3초 = 60 tick 후).
    state = respawn_dead(state)

    # 6. food spawn 보충.
    state = ensure_food(state)

    # 7. best_length 갱신.
    state = update_best_length(state)

    # 매 tick 전체 state broadcast — LiveView 가 GenServer.call 안 거치고
    # payload 로 직접 game_state 갱신 (Tetris freeze 패턴 회피). canvas 라
    # DOM diff 부담 X.
    payload = %{
      players: state.players,
      food: state.food,
      tick_no: state.tick_no
    }

    {:ok, state, [{:snake_state, payload}]}
  end

  # ============================================================================
  # game_over? — 캐주얼 모드라 절대 끝나지 않음.
  # ============================================================================

  @impl true
  def game_over?(_), do: :no

  @impl true
  def terminate(_, _), do: :ok

  # ============================================================================
  # Helpers
  # ============================================================================

  defp parse_dir("up"), do: {:ok, :up}
  defp parse_dir("down"), do: {:ok, :down}
  defp parse_dir("left"), do: {:ok, :left}
  defp parse_dir("right"), do: {:ok, :right}
  defp parse_dir(_), do: :error

  defp opposite?(:up, :down), do: true
  defp opposite?(:down, :up), do: true
  defp opposite?(:left, :right), do: true
  defp opposite?(:right, :left), do: true
  defp opposite?(_, _), do: false

  defp dir_delta(:up), do: {-1, 0}
  defp dir_delta(:down), do: {1, 0}
  defp dir_delta(:left), do: {0, -1}
  defp dir_delta(:right), do: {0, 1}

  defp pick_color(players) do
    used = players |> Map.values() |> Enum.map(& &1.color) |> MapSet.new()

    case Enum.find(@colors, fn c -> not MapSet.member?(used, c) end) do
      nil -> Enum.random(@colors)
      c -> c
    end
  end

  defp pick_spawn(state) do
    # 격자 가운데 영역 중심으로 빈 칸 시도. 충돌 회피 — 안 되면 랜덤.
    occupied =
      state.players
      |> Map.values()
      |> Enum.flat_map(& &1.body)
      |> MapSet.new()
      |> MapSet.union(state.food)

    margin = 5

    candidate =
      Enum.find_value(1..50, fn _ ->
        r = Enum.random(margin..(@grid_size - margin - 1))
        c = Enum.random(margin..(@grid_size - margin - 1))
        dir = Enum.random([:up, :down, :left, :right])
        body = build_initial_body(r, c, dir)

        if Enum.all?(body, fn cell -> not MapSet.member?(occupied, cell) end) do
          {body, dir}
        end
      end)

    # fallback — 그냥 충돌 무시.
    candidate ||
      {build_initial_body(div(@grid_size, 2), div(@grid_size, 2), :right), :right}
  end

  defp build_initial_body(r, c, dir) do
    {dr, dc} = dir_delta(dir)
    # head = (r,c). tail 은 dir 의 반대 방향.
    Enum.map(0..(@initial_length - 1), fn i ->
      {r - dr * i, c - dc * i}
    end)
  end

  defp ensure_food(state) do
    needed = state.food_target - MapSet.size(state.food)

    if needed <= 0 do
      state
    else
      occupied =
        state.players
        |> Map.values()
        |> Enum.flat_map(& &1.body)
        |> MapSet.new()
        |> MapSet.union(state.food)

      new_food =
        Enum.reduce(1..needed, state.food, fn _, acc ->
          add_random_food(acc, occupied)
        end)

      %{state | food: new_food}
    end
  end

  defp add_random_food(food, occupied) do
    # 빈 셀 찾는다. 50회 시도 (격자 큰 편이라 거의 항상 첫 시도 성공).
    Enum.find_value(1..50, food, fn _ ->
      cell = {Enum.random(0..(@grid_size - 1)), Enum.random(0..(@grid_size - 1))}

      if not MapSet.member?(food, cell) and not MapSet.member?(occupied, cell) do
        MapSet.put(food, cell)
      end
    end)
  end

  defp advance_heads(state) do
    new_players =
      Enum.into(state.players, %{}, fn {id, p} ->
        if p.alive do
          dir = p.next_dir || p.dir
          {dr, dc} = dir_delta(dir)
          [{hr, hc} | _] = p.body
          new_head = {hr + dr, hc + dc}
          new_body = [new_head | p.body]
          {id, %{p | body: new_body, dir: dir}}
        else
          {id, p}
        end
      end)

    %{state | players: new_players}
  end

  defp resolve_collisions(state) do
    # head 위치 모음 (alive 만). + 모든 body cell (head 포함).
    alive_heads =
      Enum.flat_map(state.players, fn {id, p} ->
        if p.alive, do: [{id, hd(p.body)}], else: []
      end)

    # head→bodies (자기 몸 포함). 머리/꼬리 매핑은 후행 처리.
    all_bodies =
      Enum.into(state.players, %{}, fn {id, p} -> {id, MapSet.new(p.body)} end)

    # 누가 죽었는지 1-pass 결정.
    {dead_ids, kill_credits} =
      Enum.reduce(alive_heads, {MapSet.new(), %{}}, fn {id, head}, {dead_acc, kills_acc} ->
        cond do
          out_of_bounds?(head) ->
            {MapSet.put(dead_acc, id), kills_acc}

          # 자기 몸 충돌 (head 자신 제외).
          self_collision?(state.players[id], head) ->
            {MapSet.put(dead_acc, id), kills_acc}

          # 타 player 몸 충돌. 머리 vs 머리도 양쪽 사망.
          (killer = head_in_others?(id, head, all_bodies)) != nil ->
            {MapSet.put(dead_acc, id), Map.update(kills_acc, killer, 1, &(&1 + 1))}

          true ->
            {dead_acc, kills_acc}
        end
      end)

    # 사망 처리 — body 를 food 로 흩뿌림 (전부 변환, 자기 자신 안 dropping).
    new_players =
      Enum.into(state.players, %{}, fn {id, p} ->
        cond do
          MapSet.member?(dead_ids, id) ->
            {id, %{p | alive: false, died_at_tick: state.tick_no, dir: p.dir}}

          Map.has_key?(kill_credits, id) ->
            {id, %{p | kills: p.kills + Map.fetch!(kill_credits, id)}}

          true ->
            {id, p}
        end
      end)

    new_food =
      Enum.reduce(dead_ids, state.food, fn dead_id, food_acc ->
        body = state.players[dead_id].body
        # 길이 절반 정도만 food 로 바꿈 (격자 도배 방지).
        body
        |> Enum.take_every(2)
        |> Enum.reduce(food_acc, fn cell, acc ->
          if out_of_bounds?(cell), do: acc, else: MapSet.put(acc, cell)
        end)
      end)

    %{state | players: new_players, food: new_food}
  end

  defp out_of_bounds?({r, c}) do
    r < 0 or r >= @grid_size or c < 0 or c >= @grid_size
  end

  defp self_collision?(player, head) do
    # head 본인 + tail 제외 — tail 은 다음 trim 에서 빠지니 follow 허용 (snake 표준).
    # food 를 먹는 경우라면 grow > 0 으로 tail 안 빠지지만, food 는 body 셀 위에 spawn
    # 안 되므로 head=tail 충돌이 grow 케이스에서 발생할 일 없음.
    [_head | rest] = player.body
    rest_no_tail = Enum.drop(rest, -1)
    head in rest_no_tail
  end

  defp head_in_others?(self_id, head, all_bodies) do
    Enum.find_value(all_bodies, fn {id, body_set} ->
      cond do
        id == self_id -> nil
        MapSet.member?(body_set, head) -> id
        true -> nil
      end
    end)
  end

  defp eat_food(state) do
    {new_players, new_food} =
      Enum.reduce(state.players, {%{}, state.food}, fn {id, p}, {players_acc, food_acc} ->
        if p.alive and MapSet.member?(food_acc, hd(p.body)) do
          new_p = %{p | grow: p.grow + 1}
          new_food = MapSet.delete(food_acc, hd(p.body))
          {Map.put(players_acc, id, new_p), new_food}
        else
          {Map.put(players_acc, id, p), food_acc}
        end
      end)

    %{state | players: new_players, food: new_food}
  end

  defp trim_tails(state) do
    new_players =
      Enum.into(state.players, %{}, fn {id, p} ->
        if p.alive do
          if p.grow > 0 do
            {id, %{p | grow: p.grow - 1}}
          else
            new_body = List.delete_at(p.body, -1)
            {id, %{p | body: new_body}}
          end
        else
          {id, p}
        end
      end)

    %{state | players: new_players}
  end

  defp respawn_dead(state) do
    new_players =
      Enum.into(state.players, %{}, fn {id, p} ->
        cond do
          p.alive ->
            {id, p}

          p.died_at_tick && state.tick_no - p.died_at_tick >= @respawn_ticks ->
            {body, dir} = pick_spawn(state)

            {id,
             %{
               p
               | body: body,
                 dir: dir,
                 next_dir: dir,
                 alive: true,
                 grow: 0,
                 died_at_tick: nil
             }}

          true ->
            {id, p}
        end
      end)

    %{state | players: new_players}
  end

  defp update_best_length(state) do
    new_players =
      Enum.into(state.players, %{}, fn {id, p} ->
        len = length(p.body)
        {id, %{p | best_length: max(p.best_length, len)}}
      end)

    %{state | players: new_players}
  end
end
