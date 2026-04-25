defmodule HappyTrizn.Friends.Friendship do
  @moduledoc """
  양방향 친구 관계 schema.

  - `user_a_id < user_b_id` (canonical 정렬) → (a,b) 와 (b,a) 중복 row 회피.
    insert 시 Friendship.canonical_pair/2 로 정렬 후 저장.
  - `requested_by`: 요청 보낸 사람. accept 권한자는 반대편 (`other(friendship)`).
  - `status`: `"pending"` | `"accepted"`.
  """

  use Ecto.Schema
  import Ecto.Changeset

  alias HappyTrizn.Accounts.User

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  @valid_statuses ~w(pending accepted)

  schema "friendships" do
    belongs_to :user_a, User
    belongs_to :user_b, User
    belongs_to :requester, User, foreign_key: :requested_by
    field :status, :string, default: "pending"

    timestamps(type: :utc_datetime)
  end

  def changeset(friendship, attrs) do
    friendship
    |> cast(attrs, [:user_a_id, :user_b_id, :status, :requested_by])
    |> validate_required([:user_a_id, :user_b_id, :status, :requested_by])
    |> validate_inclusion(:status, @valid_statuses)
    |> validate_canonical_order()
    |> validate_requester_is_party()
    |> validate_no_self_friendship()
    |> unique_constraint([:user_a_id, :user_b_id])
  end

  @doc "두 user id 를 canonical 순서로 정렬해서 반환 ({a, b} where a < b)."
  def canonical_pair(id1, id2) when is_binary(id1) and is_binary(id2) do
    if id1 <= id2, do: {id1, id2}, else: {id2, id1}
  end

  @doc "주어진 user 와 친구의 반대편 id 반환."
  def other_user_id(%__MODULE__{user_a_id: a, user_b_id: b}, my_id) do
    if my_id == a, do: b, else: a
  end

  @doc "수락 가능한 사람 (= requester 가 아닌 쪽)."
  def acceptable_by?(%__MODULE__{requested_by: requested_by}, user_id) do
    requested_by != user_id
  end

  defp validate_canonical_order(changeset) do
    a = get_field(changeset, :user_a_id)
    b = get_field(changeset, :user_b_id)

    if a && b && a > b do
      add_error(changeset, :user_a_id, "must be canonical (a < b)")
    else
      changeset
    end
  end

  defp validate_requester_is_party(changeset) do
    a = get_field(changeset, :user_a_id)
    b = get_field(changeset, :user_b_id)
    r = get_field(changeset, :requested_by)

    if r && r != a && r != b do
      add_error(changeset, :requested_by, "must be one of user_a or user_b")
    else
      changeset
    end
  end

  defp validate_no_self_friendship(changeset) do
    a = get_field(changeset, :user_a_id)
    b = get_field(changeset, :user_b_id)

    if a && a == b do
      add_error(changeset, :user_b_id, "cannot friend yourself")
    else
      changeset
    end
  end
end
