defmodule HappyTrizn.Messages do
  @moduledoc """
  1:1 다이렉트 메시지 (DM) context.

  - 친구 사이에만 DM 허용 (스팸 / 괴롭힘 방지).
  - 받은 사람이 thread 열면 자동 mark_read.
  - PubSub: `user:<id>:dm` topic 으로 새 메시지 / 읽음 broadcast.

  ## Topics

      "user:<id>:dm" — 받은 사람 알림 + thread page 갱신.
        - {:dm_received, %DirectMessage{}}
        - {:dm_read, %{peer_id, count}} — peer 가 내 thread 읽음.
  """

  import Ecto.Query, warn: false

  alias HappyTrizn.Repo
  alias HappyTrizn.Accounts.User
  alias HappyTrizn.Friends
  alias HappyTrizn.Messages.DirectMessage

  @pubsub HappyTrizn.PubSub

  # ============================================================================
  # Public API
  # ============================================================================

  @doc """
  메시지 발송. 친구 끼리만, 본문 1~1000자.

  Returns `{:ok, %DirectMessage{}}` | `{:error, :not_friends | :invalid | changeset}`.
  """
  def send(%User{} = from, %User{} = to, body) when is_binary(body) do
    cond do
      from.id == to.id ->
        {:error, :invalid}

      not Friends.are_friends?(from, to) ->
        {:error, :not_friends}

      true ->
        body = String.trim(body)

        if body == "" do
          {:error, :invalid}
        else
          %DirectMessage{}
          |> DirectMessage.changeset(%{
            from_user_id: from.id,
            to_user_id: to.id,
            body: String.slice(body, 0, 1000)
          })
          |> Repo.insert()
          |> case do
            {:ok, msg} ->
              # 받는 사람 + 보낸 사람 양쪽 broadcast (자기 다른 디바이스 sync).
              Phoenix.PubSub.broadcast(@pubsub, topic(to.id), {:dm_received, msg})
              Phoenix.PubSub.broadcast(@pubsub, topic(from.id), {:dm_sent, msg})
              {:ok, msg}

            err ->
              err
          end
        end
    end
  end

  @doc """
  두 user 사이 thread 가져오기. 시간 오름차순.
  옵션: `:limit` (기본 200), `:before_id` (cursor pagination 향후).
  """
  def list_thread(%User{id: id1}, %User{id: id2}, opts \\ []) do
    limit = Keyword.get(opts, :limit, 200)

    from(m in DirectMessage,
      where:
        (m.from_user_id == ^id1 and m.to_user_id == ^id2) or
          (m.from_user_id == ^id2 and m.to_user_id == ^id1),
      order_by: [asc: m.inserted_at],
      limit: ^limit
    )
    |> Repo.all()
  end

  @doc "받는 user 가 peer 와의 thread 의 미읽 메시지 모두 read_at 마킹. 읽은 갯수 반환."
  def mark_thread_read(%User{id: reader_id}, %User{id: peer_id}) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    {count, _} =
      from(m in DirectMessage,
        where: m.from_user_id == ^peer_id and m.to_user_id == ^reader_id and is_nil(m.read_at)
      )
      |> Repo.update_all(set: [read_at: now])

    if count > 0 do
      # peer 에게 "내가 읽었음" 알림 (read receipt).
      Phoenix.PubSub.broadcast(
        @pubsub,
        topic(peer_id),
        {:dm_read, %{peer_id: reader_id, count: count}}
      )
    end

    count
  end

  @doc "특정 user 의 전체 미읽 DM 갯수."
  def unread_count(%User{id: id}) do
    from(m in DirectMessage,
      where: m.to_user_id == ^id and is_nil(m.read_at),
      select: count(m.id)
    )
    |> Repo.one()
  end

  @doc """
  최근 대화 상대 list — 각 친구 별 마지막 메시지 + 미읽 갯수.

  Returns list of `%{peer: %User{}, last: %DirectMessage{}, unread: int}`.
  """
  def recent_threads(%User{id: id} = user) do
    # 1. 친구 list (accepted 만).
    friends = Friends.list_friends(user)

    # 2. 각 친구 별 마지막 메시지 + 미읽 갯수.
    friends
    |> Enum.map(fn friend ->
      last =
        from(m in DirectMessage,
          where:
            (m.from_user_id == ^id and m.to_user_id == ^friend.id) or
              (m.from_user_id == ^friend.id and m.to_user_id == ^id),
          order_by: [desc: m.inserted_at],
          limit: 1
        )
        |> Repo.one()

      unread =
        from(m in DirectMessage,
          where: m.from_user_id == ^friend.id and m.to_user_id == ^id and is_nil(m.read_at),
          select: count(m.id)
        )
        |> Repo.one()

      %{peer: friend, last: last, unread: unread}
    end)
    |> Enum.sort_by(fn t ->
      case t.last do
        nil -> 0
        m -> -DateTime.to_unix(m.inserted_at, :second)
      end
    end)
  end

  @doc "사용자 user:<id>:dm topic subscribe."
  def subscribe(%User{id: id}), do: Phoenix.PubSub.subscribe(@pubsub, topic(id))

  defp topic(user_id), do: "user:#{user_id}:dm"
end
