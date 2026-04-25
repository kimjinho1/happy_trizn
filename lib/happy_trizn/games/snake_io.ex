defmodule HappyTrizn.Games.SnakeIo do
  @moduledoc """
  Snake.io — 캐주얼 멀티 (자유 입퇴장). Sprint 3b 풀 구현.

  state stub:
    - players: %{player_id => %{length, alive}}
    - status: :playing  (캐주얼이라 항상 진행, game_over 없음)
  """

  @behaviour HappyTrizn.Games.GameBehaviour

  @impl true
  def meta do
    %{
      name: "Snake.io",
      slug: "snake_io",
      mode: :multi,
      max_players: 16,
      min_players: 1,
      description: "캐주얼 멀티 (Sprint 3b 풀 구현 예정)"
    }
  end

  @impl true
  def init(_), do: {:ok, %{players: %{}, status: :playing}}

  @impl true
  def handle_player_join(player_id, _meta, state) do
    new_players = Map.put(state.players, player_id, %{length: 3, alive: true})
    {:ok, %{state | players: new_players}, [{:player_joined, player_id}]}
  end

  @impl true
  def handle_player_leave(player_id, _reason, state) do
    new_players = Map.delete(state.players, player_id)
    {:ok, %{state | players: new_players}, [{:player_left, player_id}]}
  end

  @impl true
  def handle_input(_, _, state), do: {:ok, state, []}

  @impl true
  def tick(state), do: {:ok, state, []}

  @impl true
  def game_over?(_), do: :no

  @impl true
  def terminate(_, _), do: :ok
end
