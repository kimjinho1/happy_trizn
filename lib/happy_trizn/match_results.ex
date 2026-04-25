defmodule HappyTrizn.MatchResults do
  @moduledoc """
  Match (라운드) 결과 저장 컨텍스트.

  - `record/1` — 결과 row 저장 (game_over 시 호출).
  - `for_user/1` — 사용자가 참여한 결과 list (winner_id 또는 stats.players 안 user_id 매칭은 향후).
  - `recent/2` — 최근 N개 (게임 별 또는 전체).
  """

  import Ecto.Query

  alias HappyTrizn.Repo
  alias HappyTrizn.MatchResults.MatchResult

  @doc """
  매치 결과 저장.

  attrs:
    - game_type (required)
    - room_id (멀티) | nil (싱글)
    - winner_id (멀티 + 승자 있음) | nil
    - duration_ms (required, >= 0)
    - stats (required, map)
    - finished_at (default: now)
  """
  def record(attrs) do
    finished_at = Map.get(attrs, :finished_at) || DateTime.utc_now() |> DateTime.truncate(:second)

    attrs = Map.put(attrs, :finished_at, finished_at)

    %MatchResult{}
    |> MatchResult.changeset(attrs)
    |> Repo.insert()
  end

  def for_user(%{id: user_id}) do
    from(r in MatchResult,
      where: r.winner_id == ^user_id,
      order_by: [desc: r.finished_at]
    )
    |> Repo.all()
  end

  def for_user(nil), do: []

  def recent(game_type \\ nil, limit \\ 50) do
    q = from(r in MatchResult, order_by: [desc: r.finished_at], limit: ^limit)
    q = if game_type, do: from(r in q, where: r.game_type == ^game_type), else: q
    Repo.all(q)
  end

  def get(id), do: Repo.get(MatchResult, id)
end
