defmodule HappyTrizn.Trizmon.Saves do
  @moduledoc """
  사용자 모험 진행 save (Sprint 5c-3a).

  사용자당 1 슬롯. 첫 진입 시 자동 starting_town 생성. 매 이동 후 upsert.

  spec: docs/TRIZMON_SPEC.md §9
  """

  alias HappyTrizn.Repo
  alias HappyTrizn.Trizmon.{Save, World}

  @doc """
  사용자 save 가져옴 — 없으면 starting_town 자동 생성.
  """
  def get_or_init!(user) do
    case Repo.get(Save, user.id) do
      nil ->
        map = World.get_map("starting_town")
        {sx, sy} = map.spawn

        %Save{}
        |> Save.changeset(%{
          user_id: user.id,
          current_map: "starting_town",
          player_x: sx,
          player_y: sy,
          badges: 0,
          money: 1000,
          last_played_at: DateTime.utc_now() |> DateTime.truncate(:second)
        })
        |> Repo.insert!()

      save ->
        save
    end
  end

  @doc """
  Save 위치 + 시간 갱신.
  """
  def update_position!(save, x, y, map_id \\ nil) do
    attrs = %{
      player_x: x,
      player_y: y,
      last_played_at: DateTime.utc_now() |> DateTime.truncate(:second)
    }

    attrs = if map_id, do: Map.put(attrs, :current_map, map_id), else: attrs

    save
    |> Save.changeset(Map.put(attrs, :user_id, save.user_id))
    |> Repo.update!()
  end

  @doc "Reset — testing / debugging."
  def reset!(user) do
    case Repo.get(Save, user.id) do
      nil -> :ok
      save -> Repo.delete!(save)
    end

    get_or_init!(user)
  end
end
