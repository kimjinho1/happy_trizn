defmodule HappyTrizn.Games.Skribbl do
  @moduledoc """
  Skribbl — 그림 맞추기 5+인 멀티. Sprint 3b 풀 구현 (canvas 드로잉 + 단어 맞추기).

  state stub:
    - players: %{player_id => %{score, drawing}}
    - drawer: player_id | nil
    - word: String | nil
    - status: :waiting | :playing | :over
  """

  @behaviour HappyTrizn.Games.GameBehaviour

  @impl true
  def meta do
    %{
      name: "Skribbl",
      slug: "skribbl",
      mode: :multi,
      max_players: 8,
      min_players: 2,
      description: "그림 맞추기 (Sprint 3b 풀 구현 예정)"
    }
  end

  @impl true
  def init(_), do: {:ok, %{players: %{}, drawer: nil, word: nil, status: :waiting}}

  @impl true
  def handle_player_join(player_id, _meta, state) do
    if map_size(state.players) >= 8 do
      {:reject, :full}
    else
      new_players = Map.put(state.players, player_id, %{score: 0})
      {:ok, %{state | players: new_players}, [{:player_joined, player_id}]}
    end
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
