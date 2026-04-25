defmodule HappyTrizn.Friends do
  @moduledoc """
  친구 시스템 (양방향 수락).

  Flow:
    1. A 가 B 에게 send_request → status=pending, requested_by=A
    2. B 가 accept → status=accepted (A 는 자기 요청 못 수락)
    3. 둘 다 친구 (list_friends 양쪽 다 보임)
    4. 누구나 reject 가능 — row 삭제

  Idempotent: 같은 두 사람 사이 send_request 두 번 → 두번째는 변화 없음 (이미 row 있음).

  Notification:
    - PubSub topic "user:<user_id>:friends" 으로 LiveView broadcast.
    - {:friend_request_received, %{from: nick}} | {:friend_request_accepted, %{by: nick}}
  """

  import Ecto.Query, warn: false

  alias HappyTrizn.Repo
  alias HappyTrizn.Accounts.User
  alias HappyTrizn.Friends.Friendship

  @pubsub HappyTrizn.PubSub

  # =========================================================================
  # Send / Accept / Reject
  # =========================================================================

  @doc """
  A 가 B 에게 친구 요청.

  Returns:
    - {:ok, %Friendship{}} — 새로 생성됨
    - {:ok, :already_pending} — 이미 pending 상태
    - {:ok, :already_accepted} — 이미 친구
    - {:error, :self} — 자기 자신
    - {:error, changeset} — 검증 실패
  """
  def send_request(%User{id: from_id}, %User{id: to_id}) when from_id == to_id,
    do: {:error, :self}

  def send_request(%User{} = from, %User{} = to) do
    {a, b} = Friendship.canonical_pair(from.id, to.id)

    case Repo.get_by(Friendship, user_a_id: a, user_b_id: b) do
      nil ->
        attrs = %{
          user_a_id: a,
          user_b_id: b,
          status: "pending",
          requested_by: from.id
        }

        case %Friendship{} |> Friendship.changeset(attrs) |> Repo.insert() do
          {:ok, friendship} ->
            broadcast(to.id, {:friend_request_received, %{from: from.nickname, friendship_id: friendship.id}})
            {:ok, friendship}

          {:error, cs} ->
            {:error, cs}
        end

      %Friendship{status: "pending"} ->
        {:ok, :already_pending}

      %Friendship{status: "accepted"} ->
        {:ok, :already_accepted}
    end
  end

  @doc """
  user 가 friendship 수락. 본인이 보낸 요청은 못 수락.
  """
  def accept(%User{id: user_id} = user, %Friendship{} = friendship) do
    cond do
      not Friendship.acceptable_by?(friendship, user_id) ->
        {:error, :not_acceptable_by_requester}

      friendship.status == "accepted" ->
        {:ok, friendship}

      true ->
        case friendship |> Ecto.Changeset.change(status: "accepted") |> Repo.update() do
          {:ok, updated} ->
            broadcast(friendship.requested_by, {:friend_request_accepted, %{by: user.nickname}})
            {:ok, updated}

          err ->
            err
        end
    end
  end

  @doc "어느 쪽이든 친구 관계 끊기 / pending 거절."
  def reject(%User{id: user_id}, %Friendship{} = friendship) do
    if user_id in [friendship.user_a_id, friendship.user_b_id] do
      Repo.delete(friendship)
    else
      {:error, :not_party}
    end
  end

  # =========================================================================
  # Query
  # =========================================================================

  def get_friendship(id) when is_binary(id), do: Repo.get(Friendship, id)

  def get_friendship_between(%User{id: id1}, %User{id: id2}) do
    {a, b} = Friendship.canonical_pair(id1, id2)
    Repo.get_by(Friendship, user_a_id: a, user_b_id: b)
  end

  def are_friends?(%User{} = u1, %User{} = u2) do
    case get_friendship_between(u1, u2) do
      %Friendship{status: "accepted"} -> true
      _ -> false
    end
  end

  @doc "주어진 user 의 모든 친구 (accepted) — User struct 리스트."
  def list_friends(%User{id: id}) do
    friendships =
      from(f in Friendship,
        where: f.status == "accepted" and (f.user_a_id == ^id or f.user_b_id == ^id)
      )
      |> Repo.all()

    other_ids = Enum.map(friendships, &Friendship.other_user_id(&1, id))

    case other_ids do
      [] ->
        []

      ids ->
        from(u in User, where: u.id in ^ids, order_by: [asc: u.nickname])
        |> Repo.all()
    end
  end

  @doc "주어진 user 가 받은 pending 요청 (수락 가능)."
  def list_pending_received(%User{id: id}) do
    from(f in Friendship,
      where:
        f.status == "pending" and (f.user_a_id == ^id or f.user_b_id == ^id) and
          f.requested_by != ^id,
      preload: [:requester]
    )
    |> Repo.all()
  end

  @doc "주어진 user 가 보낸 pending 요청."
  def list_pending_sent(%User{id: id}) do
    from(f in Friendship,
      where: f.status == "pending" and f.requested_by == ^id,
      preload: [:user_a, :user_b]
    )
    |> Repo.all()
  end

  @doc """
  추천 친구 — 나와 친구 아닌 모든 사용자 (banned 제외) 중 닉네임 순으로 limit 만큼.
  Cachex 60s TTL.
  """
  def recommend(%User{id: id}, limit \\ 10) do
    Cachex.fetch(
      :recommendations_cache,
      {:recommend, id, limit},
      fn _ ->
        my_friend_ids = friend_ids(id)
        excluded = [id | my_friend_ids]

        result =
          from(u in User,
            where: u.status == "active" and u.id not in ^excluded,
            order_by: [asc: u.nickname],
            limit: ^limit
          )
          |> Repo.all()

        {:commit, result, ttl: :timer.seconds(60)}
      end
    )
    |> case do
      {:ok, users} -> users
      {:commit, users} -> users
      _ -> []
    end
  end

  defp friend_ids(my_id) do
    from(f in Friendship,
      where: f.user_a_id == ^my_id or f.user_b_id == ^my_id,
      select: %{user_a_id: f.user_a_id, user_b_id: f.user_b_id}
    )
    |> Repo.all()
    |> Enum.map(fn %{user_a_id: a, user_b_id: b} -> if a == my_id, do: b, else: a end)
  end

  # =========================================================================
  # PubSub
  # =========================================================================

  def subscribe(%User{id: id}), do: Phoenix.PubSub.subscribe(@pubsub, "user:#{id}:friends")

  defp broadcast(user_id, msg) do
    Phoenix.PubSub.broadcast(@pubsub, "user:#{user_id}:friends", msg)
  end
end
