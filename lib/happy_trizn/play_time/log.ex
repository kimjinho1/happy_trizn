defmodule HappyTrizn.PlayTime.Log do
  @moduledoc """
  실제 게임 플레이 시간 한 세션 (Sprint 5b).

  game_state.status == :playing 으로 진입한 시점부터 :playing 에서 벗어난 시점
  까지의 구간. waiting / countdown / over / 빈 방 대기는 카운트 X.

  user_id nullable — 게스트도 저장 (admin 통계용). 사용자 본인 페이지엔 user_id
  not null 만 노출.
  """

  use Ecto.Schema
  import Ecto.Changeset

  alias HappyTrizn.Accounts.User

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "play_time_logs" do
    field :game_type, :string
    field :duration_seconds, :integer
    field :started_at, :utc_datetime
    field :ended_at, :utc_datetime
    field :room_id, :binary_id

    belongs_to :user, User, foreign_key: :user_id

    timestamps(type: :utc_datetime, updated_at: false)
  end

  def changeset(log, attrs) do
    log
    |> cast(attrs, [
      :user_id,
      :game_type,
      :duration_seconds,
      :started_at,
      :ended_at,
      :room_id
    ])
    |> validate_required([:game_type, :duration_seconds, :started_at, :ended_at])
    |> validate_number(:duration_seconds, greater_than: 0)
    |> validate_length(:game_type, min: 1, max: 32)
  end
end
