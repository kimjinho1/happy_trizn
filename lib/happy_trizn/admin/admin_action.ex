defmodule HappyTrizn.Admin.AdminAction do
  @moduledoc """
  관리자 액션 감사 로그.

  - admin_id: .env 의 ADMIN_ID (현재 단일 계정, 향후 다중 admin 대비)
  - action: ban / unban / nickname_change / room_kill / etc.
  - target_user_id: ban/unban 같은 사용자 대상 액션
  - target_room_id: room_kill 같은 방 대상 액션
  - payload: 추가 컨텍스트 (이전/이후 값 등) 자유 형식 map
  """

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "admin_actions" do
    field :admin_id, :string
    field :action, :string
    field :target_user_id, :binary_id
    field :target_room_id, :binary_id
    field :payload, :map

    timestamps(type: :utc_datetime, updated_at: false)
  end

  @valid_actions ~w(ban unban nickname_change room_kill admin_login admin_logout)

  def changeset(action, attrs) do
    action
    |> cast(attrs, [:admin_id, :action, :target_user_id, :target_room_id, :payload])
    |> validate_required([:admin_id, :action])
    |> validate_inclusion(:action, @valid_actions)
    |> validate_length(:admin_id, max: 64)
    |> validate_length(:action, max: 32)
  end
end
