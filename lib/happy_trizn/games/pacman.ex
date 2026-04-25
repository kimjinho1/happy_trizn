defmodule HappyTrizn.Games.PacMan do
  @moduledoc """
  Pac-Man — 클래식 싱글. Sprint 3b 풀 구현 (maze + ghost AI + 점수).

  state stub:
    - score: 0
    - level: 1
    - lives: 3
    - over: bool
  """

  @behaviour HappyTrizn.Games.GameBehaviour

  @impl true
  def meta do
    %{
      name: "Pac-Man",
      slug: "pacman",
      mode: :single,
      max_players: 1,
      min_players: 1,
      description: "클래식 (Sprint 3b 풀 구현 예정)"
    }
  end

  @impl true
  def init(_), do: {:ok, %{score: 0, level: 1, lives: 3, over: false}}

  @impl true
  def handle_player_join(_player_id, _meta, state), do: {:ok, state, []}

  @impl true
  def handle_player_leave(_player_id, _reason, state), do: {:ok, state, []}

  @impl true
  def handle_input(_, _, state), do: {:ok, state, []}

  @impl true
  def tick(state), do: {:ok, state, []}

  @impl true
  def game_over?(%{over: true} = state), do: {:yes, %{score: state.score, level: state.level}}
  def game_over?(_), do: :no

  @impl true
  def terminate(_, _), do: :ok
end
