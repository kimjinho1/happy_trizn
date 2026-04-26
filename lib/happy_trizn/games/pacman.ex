defmodule HappyTrizn.Games.PacMan do
  @moduledoc """
  Pac-Man 싱글 — 표준 28×31 maze + 4 ghost AI + dot/pellet/lives.

  ## state

      %{
        status: :playing | :dying | :won | :over,
        score, lives, level,
        tick_no,
        rows, cols,
        walls: MapSet {r, c},
        dots: MapSet {r, c},
        pellets: MapSet {r, c},
        ghost_door: {r, c},
        tunnels: MapSet {r, c},
        pacman: %{row, col, dir, next_dir},
        ghosts: %{blinky | pinky | inky | clyde => %{row, col, dir, mode, mode_ticks}},
        frightened_ticks,         # > 0 면 모든 ghost (eaten 제외) frightened
        ghost_eat_combo,          # power pellet 동안 ghost 잡은 수 (200×2^n).
        dying_ticks,              # >0 면 :dying 애니메이션 진행 중
        spawn: %{pacman, blinky, pinky, inky, clyde}
      }

  ## Tick interval

  100ms (10fps 서버) — Pac-Man 클래식 느낌.

  ## Actions

      "set_dir" %{"dir" => "up"|"down"|"left"|"right"}
      "restart" — game over 후 다시 시작.
  """

  @behaviour HappyTrizn.Games.GameBehaviour

  @tick_ms 110
  @rows 31
  @cols 28
  @initial_lives 3
  @dot_score 10
  @pellet_score 50
  @frightened_ticks 80
  @scatter_ticks 70
  @chase_ticks 200
  @dying_ticks 18

  @ghost_ids [:blinky, :pinky, :inky, :clyde]

  # 표준 Pac-Man 28×31 maze. # 벽, . dot, o power pellet, ' ' empty,
  # P pacman spawn, B/I/N/C ghost spawn (B=blinky, I=inky, N=pinky, C=clyde),
  # T tunnel passable empty, - ghost door (eaten ghost 만 통과).
  @maze """
  ############################
  #............##............#
  #.####.#####.##.#####.####.#
  #o####.#####.##.#####.####o#
  #.####.#####.##.#####.####.#
  #..........................#
  #.####.##.########.##.####.#
  #.####.##.########.##.####.#
  #......##....##....##......#
  ######.##### ## #####.######
  TTTTT#.##### ## #####.#TTTTT
  TTTTT#.##          ##.#TTTTT
  TTTTT#.## ###--### ##.#TTTTT
  ######.## #IBNC #  ##.######
  T     .   #      #   .     T
  ######.## #      # ##.######
  TTTTT#.## ######## ##.#TTTTT
  TTTTT#.##          ##.#TTTTT
  TTTTT#.## ######## ##.#TTTTT
  ######.## ######## ##.######
  #............##............#
  #.####.#####.##.#####.####.#
  #o..##.......P .......##..o#
  ###.##.##.########.##.##.###
  ###.##.##.########.##.##.###
  #......##....##....##......#
  #.##########.##.##########.#
  #.##########.##.##########.#
  #..........................#
  ############################
  """

  # 4 ghost home corner — scatter 모드 시 도착 목표.
  @scatter_targets %{
    blinky: {0, @cols - 2},
    pinky: {0, 1},
    inky: {@rows - 1, @cols - 2},
    clyde: {@rows - 1, 1}
  }

  # ============================================================================
  # GameBehaviour
  # ============================================================================

  @impl true
  def meta do
    %{
      name: "Pac-Man",
      slug: "pacman",
      mode: :single,
      max_players: 1,
      min_players: 1,
      description: "클래식 미로 — 28×31, ghost AI 4종",
      tick_interval_ms: @tick_ms
    }
  end

  @impl true
  def init(_) do
    {:ok, fresh_state()}
  end

  defp fresh_state do
    parsed = parse_maze()

    %{
      status: :playing,
      score: 0,
      lives: @initial_lives,
      level: 1,
      tick_no: 0,
      rows: @rows,
      cols: @cols,
      walls: parsed.walls,
      dots: parsed.dots,
      pellets: parsed.pellets,
      ghost_door: parsed.ghost_door,
      tunnels: parsed.tunnels,
      pacman: %{
        row: elem(parsed.spawn.pacman, 0),
        col: elem(parsed.spawn.pacman, 1),
        dir: :left,
        next_dir: :left
      },
      ghosts:
        Enum.into(@ghost_ids, %{}, fn id ->
          {row, col} = parsed.spawn[id]
          {id, %{row: row, col: col, dir: :up, mode: :scatter, mode_ticks: @scatter_ticks}}
        end),
      frightened_ticks: 0,
      ghost_eat_combo: 0,
      dying_ticks: 0,
      spawn: parsed.spawn,
      total_dots: MapSet.size(parsed.dots) + MapSet.size(parsed.pellets)
    }
  end

  @impl true
  def handle_player_join(_player_id, _meta, state), do: {:ok, state, []}

  @impl true
  def handle_player_leave(_player_id, _reason, state), do: {:ok, state, []}

  # ============================================================================
  # Input
  # ============================================================================

  @impl true
  def handle_input(_pid, %{"action" => "set_dir", "dir" => dir_s}, state) do
    case parse_dir(dir_s) do
      {:ok, dir} ->
        new_pac = %{state.pacman | next_dir: dir}
        {:ok, %{state | pacman: new_pac}, []}

      :error ->
        {:ok, state, []}
    end
  end

  def handle_input(_, %{"action" => "restart"}, state) do
    cond do
      state.status == :over -> {:ok, fresh_state(), [{:restart, :ok}]}
      true -> {:ok, state, []}
    end
  end

  def handle_input(_, _, state), do: {:ok, state, []}

  # ============================================================================
  # Tick
  # ============================================================================

  @impl true
  def tick(%{status: :over} = state), do: {:ok, state, []}

  def tick(%{status: :won} = state) do
    # 다음 level — fresh maze, score/lives/level 누적.
    nxt = fresh_state()

    new = %{
      nxt
      | score: state.score,
        lives: state.lives,
        level: state.level + 1
    }

    {:ok, new, [{:level_up, %{level: new.level}}]}
  end

  def tick(%{status: :dying} = state) do
    state = %{state | dying_ticks: state.dying_ticks - 1, tick_no: state.tick_no + 1}

    if state.dying_ticks <= 0 do
      respawn_after_death(state)
    else
      {:ok, state, []}
    end
  end

  def tick(state) do
    state = %{state | tick_no: state.tick_no + 1}
    state = move_pacman(state)
    state = consume_dot_or_pellet(state)
    state = update_ghost_modes(state)
    state = move_ghosts(state)
    state = check_collisions(state)
    state = check_won(state)
    {:ok, state, []}
  end

  defp move_pacman(state) do
    pac = state.pacman
    # next_dir 가능하면 dir 변경.
    pac =
      if can_move?(state, pac.row, pac.col, pac.next_dir),
        do: %{pac | dir: pac.next_dir},
        else: pac

    {nr, nc} = step(pac.row, pac.col, pac.dir) |> wrap_tunnel()

    if can_enter?(state, nr, nc, :pacman) do
      %{state | pacman: %{pac | row: nr, col: nc}}
    else
      %{state | pacman: pac}
    end
  end

  defp consume_dot_or_pellet(state) do
    pos = {state.pacman.row, state.pacman.col}

    cond do
      MapSet.member?(state.dots, pos) ->
        %{
          state
          | dots: MapSet.delete(state.dots, pos),
            score: state.score + @dot_score
        }

      MapSet.member?(state.pellets, pos) ->
        # power pellet — frightened 발동 + ghost 모드 :eaten 제외 다 frightened.
        new_ghosts =
          Enum.into(state.ghosts, %{}, fn {id, g} ->
            if g.mode == :eaten, do: {id, g}, else: {id, frighten(g)}
          end)

        %{
          state
          | pellets: MapSet.delete(state.pellets, pos),
            score: state.score + @pellet_score,
            frightened_ticks: @frightened_ticks,
            ghost_eat_combo: 0,
            ghosts: new_ghosts
        }

      true ->
        state
    end
  end

  defp frighten(g),
    do: %{g | mode: :frightened, mode_ticks: @frightened_ticks, dir: opposite_dir(g.dir)}

  defp update_ghost_modes(state) do
    fr = max(state.frightened_ticks - 1, 0)
    state = %{state | frightened_ticks: fr}

    new_ghosts =
      Enum.into(state.ghosts, %{}, fn {id, g} ->
        cond do
          g.mode == :eaten ->
            home = state.spawn[id]

            if {g.row, g.col} == home,
              do: {id, %{g | mode: :scatter, mode_ticks: @scatter_ticks}},
              else: {id, g}

          g.mode == :frightened ->
            if fr <= 0,
              do: {id, %{g | mode: :chase, mode_ticks: @chase_ticks}},
              else: {id, %{g | mode_ticks: g.mode_ticks - 1}}

          true ->
            new_ticks = g.mode_ticks - 1

            if new_ticks <= 0 do
              new_mode = if g.mode == :scatter, do: :chase, else: :scatter
              new_ticks = if new_mode == :chase, do: @chase_ticks, else: @scatter_ticks
              {id, %{g | mode: new_mode, mode_ticks: new_ticks}}
            else
              {id, %{g | mode_ticks: new_ticks}}
            end
        end
      end)

    %{state | ghosts: new_ghosts}
  end

  defp move_ghosts(state) do
    new_ghosts =
      Enum.into(state.ghosts, %{}, fn {id, g} ->
        target = ghost_target(id, g, state)
        new_dir = pick_ghost_dir(state, g, target)
        {nr, nc} = step(g.row, g.col, new_dir) |> wrap_tunnel()
        kind = ghost_pass_kind(g)

        if can_enter?(state, nr, nc, kind) do
          {id, %{g | row: nr, col: nc, dir: new_dir}}
        else
          {id, g}
        end
      end)

    %{state | ghosts: new_ghosts}
  end

  # 각 ghost 의 chase target.
  defp ghost_target(id, %{mode: :eaten}, state), do: state.spawn[id]
  defp ghost_target(id, %{mode: :scatter}, _state), do: @scatter_targets[id]

  defp ghost_target(:blinky, %{mode: :chase}, state),
    do: {state.pacman.row, state.pacman.col}

  defp ghost_target(:pinky, %{mode: :chase}, state) do
    {dr, dc} = dir_delta(state.pacman.dir)
    {state.pacman.row + dr * 4, state.pacman.col + dc * 4}
  end

  defp ghost_target(:inky, %{mode: :chase}, state) do
    {dr, dc} = dir_delta(state.pacman.dir)
    {pr, pc} = {state.pacman.row + dr * 2, state.pacman.col + dc * 2}
    blinky = state.ghosts[:blinky]
    {br, bc} = {blinky.row, blinky.col}
    # blinky → pivot 벡터의 2배 (pivot - blinky 만큼 더 나아간 위치).
    {pr + (pr - br), pc + (pc - bc)}
  end

  defp ghost_target(:clyde, %{mode: :chase} = g, state) do
    pac = state.pacman
    dist = abs(g.row - pac.row) + abs(g.col - pac.col)
    if dist > 8, do: {pac.row, pac.col}, else: @scatter_targets[:clyde]
  end

  defp ghost_target(_id, %{mode: :frightened}, state) do
    # 도망 — pick_ghost_dir 안에서 max distance 로 선택.
    {state.pacman.row, state.pacman.col}
  end

  defp pick_ghost_dir(state, g, target) do
    candidates =
      [:up, :down, :left, :right]
      |> Enum.reject(&(&1 == opposite_dir(g.dir)))
      |> Enum.filter(fn d ->
        {nr, nc} = step(g.row, g.col, d) |> wrap_tunnel()
        can_enter?(state, nr, nc, ghost_pass_kind(g))
      end)

    case candidates do
      [] ->
        opposite_dir(g.dir)

      list ->
        scored =
          if g.mode == :frightened do
            Enum.map(list, fn d ->
              {nr, nc} = step(g.row, g.col, d) |> wrap_tunnel()

              # 도망 — target 에서 가장 멀어지는 방향 (음수 점수 → 멀수록 작음).
              {d, -manhattan({nr, nc}, target)}
            end)
          else
            Enum.map(list, fn d ->
              {nr, nc} = step(g.row, g.col, d) |> wrap_tunnel()
              {d, manhattan({nr, nc}, target)}
            end)
          end

        scored |> Enum.min_by(&elem(&1, 1)) |> elem(0)
    end
  end

  defp ghost_pass_kind(%{mode: :eaten}), do: :eaten_ghost
  defp ghost_pass_kind(_g), do: :ghost

  defp manhattan({r1, c1}, {r2, c2}), do: abs(r1 - r2) + abs(c1 - c2)

  defp check_collisions(state) do
    pac_pos = {state.pacman.row, state.pacman.col}

    Enum.reduce(state.ghosts, state, fn {id, g}, st ->
      cond do
        st.status != :playing ->
          st

        {g.row, g.col} != pac_pos ->
          st

        g.mode == :frightened ->
          combo = st.ghost_eat_combo
          gain = 200 * trunc(:math.pow(2, combo))
          new_g = %{g | mode: :eaten}
          new_ghosts = Map.put(st.ghosts, id, new_g)
          %{st | ghosts: new_ghosts, score: st.score + gain, ghost_eat_combo: combo + 1}

        g.mode == :eaten ->
          st

        true ->
          %{st | status: :dying, dying_ticks: @dying_ticks}
      end
    end)
  end

  defp respawn_after_death(state) do
    new_lives = state.lives - 1

    cond do
      new_lives < 0 ->
        {:ok, %{state | status: :over, lives: 0},
         [{:game_over, %{score: state.score, level: state.level}}]}

      true ->
        {:ok,
         %{
           state
           | status: :playing,
             dying_ticks: 0,
             lives: new_lives,
             frightened_ticks: 0,
             ghost_eat_combo: 0,
             pacman: %{
               row: elem(state.spawn.pacman, 0),
               col: elem(state.spawn.pacman, 1),
               dir: :left,
               next_dir: :left
             },
             ghosts:
               Enum.into(@ghost_ids, %{}, fn id ->
                 {row, col} = state.spawn[id]
                 {id, %{row: row, col: col, dir: :up, mode: :scatter, mode_ticks: @scatter_ticks}}
               end)
         }, []}
    end
  end

  defp check_won(state) do
    if MapSet.size(state.dots) == 0 and MapSet.size(state.pellets) == 0,
      do: %{state | status: :won},
      else: state
  end

  # ============================================================================
  # game_over?
  # ============================================================================

  @impl true
  def game_over?(%{status: :over} = state),
    do: {:yes, %{score: state.score, level: state.level, lives: state.lives}}

  def game_over?(_), do: :no

  @impl true
  def terminate(_, _), do: :ok

  # ============================================================================
  # Maze parsing
  # ============================================================================

  defp parse_maze do
    lines =
      @maze
      |> String.split("\n", trim: true)
      |> Enum.map(&String.pad_trailing(&1, @cols))

    spawn_default = %{
      pacman: {23, 13},
      blinky: {13, 13},
      pinky: {13, 14},
      inky: {13, 12},
      clyde: {13, 15}
    }

    {walls, dots, pellets, tunnels, ghost_door, spawns} =
      lines
      |> Enum.with_index()
      |> Enum.reduce(
        {MapSet.new(), MapSet.new(), MapSet.new(), MapSet.new(), nil, spawn_default},
        fn {row, r}, acc ->
          row
          |> String.graphemes()
          |> Enum.with_index()
          |> Enum.reduce(acc, fn {ch, c}, {wls, ds, ps, ts, door, sp} ->
            case ch do
              "#" -> {MapSet.put(wls, {r, c}), ds, ps, ts, door, sp}
              "." -> {wls, MapSet.put(ds, {r, c}), ps, ts, door, sp}
              "o" -> {wls, ds, MapSet.put(ps, {r, c}), ts, door, sp}
              "T" -> {wls, ds, ps, MapSet.put(ts, {r, c}), door, sp}
              "-" -> {wls, ds, ps, ts, door || {r, c}, sp}
              "P" -> {wls, ds, ps, ts, door, Map.put(sp, :pacman, {r, c})}
              "B" -> {wls, ds, ps, ts, door, Map.put(sp, :blinky, {r, c})}
              "I" -> {wls, ds, ps, ts, door, Map.put(sp, :inky, {r, c})}
              "N" -> {wls, ds, ps, ts, door, Map.put(sp, :pinky, {r, c})}
              "C" -> {wls, ds, ps, ts, door, Map.put(sp, :clyde, {r, c})}
              _ -> {wls, ds, ps, ts, door, sp}
            end
          end)
        end
      )

    %{
      walls: walls,
      dots: dots,
      pellets: pellets,
      tunnels: tunnels,
      ghost_door: ghost_door,
      spawn: spawns
    }
  end

  # ============================================================================
  # Movement helpers
  # ============================================================================

  defp parse_dir("up"), do: {:ok, :up}
  defp parse_dir("down"), do: {:ok, :down}
  defp parse_dir("left"), do: {:ok, :left}
  defp parse_dir("right"), do: {:ok, :right}
  defp parse_dir(_), do: :error

  defp dir_delta(:up), do: {-1, 0}
  defp dir_delta(:down), do: {1, 0}
  defp dir_delta(:left), do: {0, -1}
  defp dir_delta(:right), do: {0, 1}

  defp opposite_dir(:up), do: :down
  defp opposite_dir(:down), do: :up
  defp opposite_dir(:left), do: :right
  defp opposite_dir(:right), do: :left

  defp step(r, c, dir) do
    {dr, dc} = dir_delta(dir)
    {r + dr, c + dc}
  end

  # tunnel wrap — row 14 좌우 통함 (실제로는 모든 row 안전).
  defp wrap_tunnel({r, c}) when c < 0, do: {r, @cols - 1}
  defp wrap_tunnel({r, c}) when c >= @cols, do: {r, 0}
  defp wrap_tunnel(rc), do: rc

  defp can_move?(state, r, c, dir) do
    {nr, nc} = step(r, c, dir) |> wrap_tunnel()
    can_enter?(state, nr, nc, :pacman)
  end

  defp can_enter?(state, r, c, kind) do
    cond do
      r < 0 or r >= @rows -> false
      c < 0 or c >= @cols -> false
      MapSet.member?(state.walls, {r, c}) -> false
      kind == :eaten_ghost -> true
      kind == :pacman and {r, c} == state.ghost_door -> false
      kind == :ghost and {r, c} == state.ghost_door -> false
      true -> true
    end
  end
end
