defmodule HappyTrizn.PersonalRecords do
  @moduledoc """
  사용자 개인 최고 기록 컨텍스트.

  매치 끝날 때마다 stats 를 받아 비교 — 갱신될 때만 row 변경.
  """

  import Ecto.Query

  alias HappyTrizn.Repo
  alias HappyTrizn.PersonalRecords.Record

  @doc """
  스코어 / 라인 / 통계 갱신 — `apply_stats/3` 가 비교 후 max 업데이트 + total_wins 증분.

  attrs:
    - score (int)
    - lines (int)
    - won (bool) — true 면 total_wins +1
    - metadata (map) — 게임별 추가 metric (max_pps 등)
  """
  def apply_stats(%{id: user_id}, game_type, attrs) when is_map(attrs) do
    existing =
      Repo.get_by(Record, user_id: user_id, game_type: game_type) || %Record{}

    score = Map.get(attrs, :score, 0)
    lines = Map.get(attrs, :lines, 0)
    won? = Map.get(attrs, :won, false)
    incoming_meta = Map.get(attrs, :metadata, %{})

    new_metadata = merge_metadata(existing.metadata || %{}, incoming_meta)

    new_attrs = %{
      user_id: user_id,
      game_type: game_type,
      max_score: max(existing.max_score || 0, score),
      max_lines: max(existing.max_lines || 0, lines),
      total_wins: (existing.total_wins || 0) + if(won?, do: 1, else: 0),
      metadata: new_metadata,
      achieved_at: DateTime.utc_now() |> DateTime.truncate(:second)
    }

    existing
    |> Record.changeset(new_attrs)
    |> Repo.insert_or_update()
  end

  def apply_stats(nil, _, _), do: {:error, :guest}

  @doc "사용자의 game_type 기록 조회 — 없으면 nil."
  def get_for(%{id: user_id}, game_type) do
    Repo.get_by(Record, user_id: user_id, game_type: game_type)
  end

  def get_for(nil, _), do: nil

  @doc "사용자 모든 게임 기록."
  def list_for_user(%{id: user_id}) do
    from(r in Record, where: r.user_id == ^user_id, order_by: r.game_type)
    |> Repo.all()
  end

  def list_for_user(nil), do: []

  @doc "리더보드 — game_type 별 최고 score 사용자 N 명."
  def leaderboard(game_type, limit \\ 10) when is_binary(game_type) do
    from(r in Record,
      where: r.game_type == ^game_type and r.max_score > 0,
      order_by: [desc: r.max_score, desc: r.max_lines],
      limit: ^limit,
      preload: :user
    )
    |> Repo.all()
  end

  # incoming metadata 의 numeric 값은 max 비교, 그 외엔 덮어쓰기.
  defp merge_metadata(existing, incoming) when is_map(existing) and is_map(incoming) do
    Map.merge(existing, incoming, fn _key, ev, iv ->
      cond do
        is_number(ev) and is_number(iv) -> max(ev, iv)
        true -> iv
      end
    end)
  end

  defp merge_metadata(_, incoming), do: incoming || %{}
end
