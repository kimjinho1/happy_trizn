defmodule HappyTrizn.Games.Tetris do
  @moduledoc """
  Tetris (Jstris-like) — 멀티 1v1 / battle. 클라이언트 권위 + 서버는 가비지/점수/승패.

  Sprint 3a: 인터페이스 stub. 풀 구현 (SRS 회전, 가비지 라인, 콤보, 60fps tick) 은 Sprint 3b.

  state:
    - players: %{player_id => %{score, lines, top_out}}
    - status: :waiting | :playing | :over
    - winner: player_id | nil
  """

  @behaviour HappyTrizn.Games.GameBehaviour

  @impl true
  def meta do
    %{
      name: "Tetris",
      slug: "tetris",
      mode: :multi,
      max_players: 2,
      min_players: 2,
      description: "Jstris-like 1v1 (Sprint 3b 풀 구현 예정)"
    }
  end

  @impl true
  def init(_), do: {:ok, %{players: %{}, status: :waiting, winner: nil}}

  @impl true
  def handle_player_join(player_id, _meta, state) do
    if map_size(state.players) >= 2 do
      {:reject, :full}
    else
      new_players = Map.put(state.players, player_id, %{score: 0, lines: 0, top_out: false})
      new_status = if map_size(new_players) == 2, do: :playing, else: :waiting
      {:ok, %{state | players: new_players, status: new_status}, [{:player_joined, player_id}]}
    end
  end

  @impl true
  def handle_player_leave(player_id, _reason, state) do
    new_players = Map.delete(state.players, player_id)

    cond do
      state.status == :playing and map_size(new_players) == 1 ->
        winner = new_players |> Map.keys() |> hd()
        {:ok, %{state | players: new_players, status: :over, winner: winner}, [{:winner, winner}]}

      true ->
        {:ok, %{state | players: new_players}, [{:player_left, player_id}]}
    end
  end

  @impl true
  def handle_input(player_id, %{"action" => "score_update", "score" => score, "lines" => lines}, state) do
    if Map.has_key?(state.players, player_id) do
      new_players =
        Map.update!(state.players, player_id, fn p -> %{p | score: score, lines: lines} end)

      {:ok, %{state | players: new_players}, [{:score, %{player: player_id, score: score, lines: lines}}]}
    else
      {:ok, state, []}
    end
  end

  def handle_input(player_id, %{"action" => "top_out"}, state) do
    if Map.has_key?(state.players, player_id) do
      new_players = Map.update!(state.players, player_id, &Map.put(&1, :top_out, true))
      remaining = new_players |> Enum.reject(fn {_, p} -> p.top_out end) |> Enum.map(fn {id, _} -> id end)
      winner = if length(remaining) == 1, do: hd(remaining), else: nil

      new_state = %{state | players: new_players, status: if(winner, do: :over, else: :playing), winner: winner}
      broadcast = if winner, do: [{:winner, winner}], else: []
      {:ok, new_state, broadcast}
    else
      {:ok, state, []}
    end
  end

  # 가비지 라인 라우팅 (클라이언트 → 서버 → 상대 클라이언트)
  def handle_input(player_id, %{"action" => "garbage", "lines" => lines}, state) do
    target = state.players |> Map.keys() |> Enum.find(&(&1 != player_id))
    if target do
      {:ok, state, [{:garbage, %{from: player_id, to: target, lines: lines}}]}
    else
      {:ok, state, []}
    end
  end

  def handle_input(_, _, state), do: {:ok, state, []}

  @impl true
  def tick(state), do: {:ok, state, []}

  @impl true
  def game_over?(%{status: :over, winner: w} = state),
    do: {:yes, %{winner: w, players: state.players}}

  def game_over?(_), do: :no

  @impl true
  def terminate(_, _), do: :ok
end
