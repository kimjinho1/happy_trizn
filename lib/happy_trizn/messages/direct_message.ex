defmodule HappyTrizn.Messages.DirectMessage do
  @moduledoc """
  1:1 다이렉트 메시지 schema.

  - `from_user_id`: 보낸 사람.
  - `to_user_id`: 받은 사람. 둘은 친구 사이여야 (Messages.send 단계 검증).
  - `body`: 메시지 본문 (1~1000자).
  - `read_at`: 받은 사람이 thread 열어 읽었을 때 set.
  """

  use Ecto.Schema
  import Ecto.Changeset

  alias HappyTrizn.Accounts.User

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "direct_messages" do
    belongs_to :from, User, foreign_key: :from_user_id
    belongs_to :to, User, foreign_key: :to_user_id
    field :body, :string
    field :read_at, :utc_datetime

    timestamps(type: :utc_datetime, updated_at: false)
  end

  def changeset(msg, attrs) do
    msg
    |> cast(attrs, [:from_user_id, :to_user_id, :body, :read_at])
    |> validate_required([:from_user_id, :to_user_id, :body])
    |> validate_length(:body, min: 1, max: 1000)
    |> validate_not_self()
  end

  defp validate_not_self(cs) do
    f = get_field(cs, :from_user_id)
    t = get_field(cs, :to_user_id)
    if f && t && f == t, do: add_error(cs, :to_user_id, "cannot DM yourself"), else: cs
  end
end
