defmodule HappyTrizn.Accounts do
  @moduledoc """
  사용자 인증 + 세션 관리.

  두 트랙:
  - 게스트: 닉네임만, user_id=nil 세션. 게임/채팅 OK, 친구/영구 기록 X.
  - 등록자: @trizn.kr 가입 + 비번. 모든 기능 + 영구 기록.

  Admin 은 .env 고정 계정으로 별도 — 이 모듈 범위 밖.
  """

  import Ecto.Query, warn: false

  alias HappyTrizn.Repo
  alias HappyTrizn.Accounts.{User, Session}

  # =========================================================================
  # 등록자 (Users)
  # =========================================================================

  def register_user(attrs) when is_map(attrs) do
    %User{}
    |> User.registration_changeset(attrs)
    |> Repo.insert()
  end

  def authenticate(email, password) when is_binary(email) and is_binary(password) do
    user = get_user_by_email(email)

    cond do
      user && user.status == "banned" ->
        {:error, :banned}

      user && User.valid_password?(user, password) ->
        {:ok, user}

      true ->
        # timing attack 방어 — 사용자 없을 때도 bcrypt 시간 일관
        Bcrypt.no_user_verify()
        {:error, :invalid_credentials}
    end
  end

  def get_user(id) when is_binary(id), do: Repo.get(User, id)

  def get_user_by_email(email) when is_binary(email) do
    Repo.get_by(User, email: String.downcase(email))
  end

  def get_user_by_nickname(nickname) when is_binary(nickname) do
    Repo.get_by(User, nickname: nickname)
  end

  def list_users(opts \\ []) do
    status = Keyword.get(opts, :status)
    limit = Keyword.get(opts, :limit, 100)
    offset = Keyword.get(opts, :offset, 0)

    User
    |> maybe_filter_status(status)
    |> order_by(asc: :nickname)
    |> limit(^limit)
    |> offset(^offset)
    |> Repo.all()
  end

  defp maybe_filter_status(query, nil), do: query
  defp maybe_filter_status(query, status), do: from(u in query, where: u.status == ^status)

  def ban_user(%User{} = user) do
    with {:ok, banned} <- update_status(user, "banned") do
      delete_user_sessions(banned)
      {:ok, banned}
    end
  end

  def unban_user(%User{} = user), do: update_status(user, "active")

  defp update_status(user, status) do
    user
    |> User.status_changeset(%{status: status})
    |> Repo.update()
  end

  # =========================================================================
  # 세션
  # =========================================================================

  @doc """
  등록 사용자 세션 발급.

  Returns `{:ok, raw_token, %Session{}}`. 호출자는 raw_token 을 cookie 에 저장.
  Banned user 는 차단.
  """
  def create_user_session(%User{status: "banned"}), do: {:error, :banned}

  def create_user_session(%User{} = user) do
    insert_session(user, user.nickname)
  end

  @doc "게스트 세션 — 닉네임만."
  def create_guest_session(nickname) when is_binary(nickname) do
    nickname = String.trim(nickname)

    cond do
      String.length(nickname) < 2 ->
        {:error, :nickname_too_short}

      String.length(nickname) > 32 ->
        {:error, :nickname_too_long}

      true ->
        insert_session(nil, nickname)
    end
  end

  defp insert_session(user_or_nil, nickname) do
    {raw, changeset} = Session.build(user_or_nil, nickname)

    case Repo.insert(changeset) do
      {:ok, session} -> {:ok, raw, session}
      {:error, cs} -> {:error, cs}
    end
  end

  @doc """
  cookie 에 들은 raw token 으로 세션 + 사용자 조회.

  Returns `{user_or_nil, %Session{}}` 또는 `nil` (만료/없음/banned).
  """
  def get_session_by_token(raw) when is_binary(raw) do
    hash = Session.hash_token(raw)
    now = DateTime.utc_now()

    case Repo.get_by(Session, token_hash: hash) do
      nil ->
        nil

      %Session{expires_at: exp} = session ->
        if DateTime.compare(exp, now) == :gt do
          resolve_session_user(session)
        else
          delete_session(session)
          nil
        end
    end
  end

  def get_session_by_token(_), do: nil

  defp resolve_session_user(%Session{user_id: nil} = session), do: {nil, session}

  defp resolve_session_user(%Session{user_id: id} = session) do
    case get_user(id) do
      nil ->
        delete_session(session)
        nil

      %User{status: "banned"} ->
        delete_session(session)
        nil

      user ->
        {user, session}
    end
  end

  def delete_session(%Session{} = session), do: Repo.delete(session)

  def delete_user_sessions(%User{id: id}) do
    from(s in Session, where: s.user_id == ^id) |> Repo.delete_all()
  end

  @doc "백그라운드 작업: 만료 세션 청소."
  def prune_expired_sessions do
    now = DateTime.utc_now()
    from(s in Session, where: s.expires_at < ^now) |> Repo.delete_all()
  end
end
