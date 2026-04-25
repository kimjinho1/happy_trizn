defmodule HappyTrizn.Games.Bomberman do
  @moduledoc """
  Bomberman — 멀티 4인 격자 폭탄. Sprint 3b 풀 구현 (격자 맵 / 폭탄 / 아이템 / 서버 권위).

  state stub:
    - players: %{player_id => %{x, y, alive}}
    - status: :waiting | :playing | :over
    - winner: player_id | nil
  """

  @behaviour HappyTrizn.Games.GameBehaviour

  @impl true
  def meta do
    %{
      name: "Bomberman",
      slug: "bomberman",
      mode: :multi,
      max_players: 4,
      min_players: 2,
      description: "4인 격자 폭탄 (Sprint 3b 풀 구현 예정)"
    }
  end

  @impl true
  def init(_), do: {:ok, %{players: %{}, status: :waiting, winner: nil}}

  @impl true
  def handle_player_join(player_id, _meta, state) do
    if map_size(state.players) >= 4 do
      {:reject, :full}
    else
      new_players = Map.put(state.players, player_id, %{alive: true})
      {:ok, %{state | players: new_players}, [{:player_joined, player_id}]}
    end
  end

  @impl true
  def handle_player_leave(player_id, _reason, state) do
    new_players = Map.delete(state.players, player_id)
    alive = new_players |> Enum.filter(fn {_, p} -> p.alive end) |> Enum.map(fn {id, _} -> id end)

    cond do
      state.status == :playing and length(alive) == 1 ->
        winner = hd(alive)
        {:ok, %{state | players: new_players, status: :over, winner: winner}, [{:winner, winner}]}

      true ->
        {:ok, %{state | players: new_players}, [{:player_left, player_id}]}
    end
  end

  @impl true
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
