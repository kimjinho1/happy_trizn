defmodule HappyTrizn.GameSnapshots do
  @moduledoc """
  싱글 게임 진행 상태 자동 저장 (Sprint 4k).

  Sudoku / 2048 / Minesweeper 만 대상. Pac-Man 은 tick 게임 (50ms 마다 변경) 이라
  저장 빈도가 너무 높음 + 짧은 한 판이라 가치 낮음.

  state 는 erlang term 통째로 binary 직렬화 — tuple / atom 그대로 보존, 게임 모듈
  변경 0. deserialize 는 [:safe] 옵션으로 atom 새로 만들지 않음 (alread-known atoms only).

  사용처: GameLive mount 시 복원, handle_event input 후 upsert, game_over 시 delete.
  게스트 (user_id nil) 는 저장 X — 같은 닉네임 중복 시 충돌 방지.
  """

  import Ecto.Query

  alias HappyTrizn.GameSnapshots.Snapshot
  alias HappyTrizn.Repo

  # 싱글 게임 중 snapshot 저장 대상.
  @serializable_slugs ~w(sudoku 2048 minesweeper)

  @doc "이 game_type 의 진행 상태를 저장할 가치가 있나?"
  def serializable?(slug) when is_binary(slug), do: slug in @serializable_slugs
  def serializable?(_), do: false

  @doc """
  사용자 + 게임의 최신 snapshot 가져옴. 없거나 deserialize 실패 → nil.

  schema_version 은 호출자가 기대하는 버전과 비교 — 다르면 nil (옛 snapshot 폐기).
  """
  def get(user_id, game_type, expected_version \\ 1)
      when is_binary(user_id) and is_binary(game_type) do
    case Repo.get_by(Snapshot, user_id: user_id, game_type: game_type) do
      nil ->
        nil

      %Snapshot{schema_version: v} when v != expected_version ->
        nil

      %Snapshot{state_blob: blob} ->
        try do
          :erlang.binary_to_term(blob, [:safe])
        rescue
          _ -> nil
        end
    end
  end

  @doc """
  upsert. 같은 (user_id, game_type) 있으면 state_blob + updated_at 갱신.
  """
  def upsert(user_id, game_type, state, schema_version \\ 1)
      when is_binary(user_id) and is_binary(game_type) do
    blob = :erlang.term_to_binary(state)
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    attrs = %{
      user_id: user_id,
      game_type: game_type,
      state_blob: blob,
      schema_version: schema_version,
      updated_at: now,
      inserted_at: now
    }

    # MySQL ON DUPLICATE KEY UPDATE — conflict_target 옵션 미지원, 대신 unique
    # index (user_id, game_type) 가 자동 매칭. set 에 명시한 컬럼만 갱신.
    Repo.insert(
      Snapshot.changeset(%Snapshot{}, attrs),
      on_conflict: [
        set: [state_blob: blob, schema_version: schema_version, updated_at: now]
      ]
    )
  end

  @doc "삭제 — game_over 또는 사용자가 명시적 새 게임 시작 시."
  def delete(user_id, game_type) when is_binary(user_id) and is_binary(game_type) do
    from(s in Snapshot, where: s.user_id == ^user_id and s.game_type == ^game_type)
    |> Repo.delete_all()

    :ok
  end

  @doc "사용자의 모든 snapshot 삭제 — 계정 삭제 / admin reset."
  def delete_all_for_user(user_id) when is_binary(user_id) do
    from(s in Snapshot, where: s.user_id == ^user_id) |> Repo.delete_all()
    :ok
  end
end
