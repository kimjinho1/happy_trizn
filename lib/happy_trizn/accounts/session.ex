defmodule HappyTrizn.Accounts.Session do
  @moduledoc """
  로그인/게스트 세션 schema (DB-backed).

  컨테이너 재배포 / 재시작 시에도 로그인 유지하려고 ETS 대신 MySQL 사용.
  raw token 은 cookie 에만 두고 DB 에는 SHA-256 해시만 저장 (token leak 방지).
  """

  use Ecto.Schema
  import Ecto.Changeset

  alias HappyTrizn.Accounts.User

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  @session_validity_days 30
  @token_bytes 32

  schema "sessions" do
    field :nickname, :string
    field :token_hash, :binary
    field :expires_at, :utc_datetime
    belongs_to :user, User

    timestamps(type: :utc_datetime, updated_at: false)
  end

  @doc """
  유저(또는 게스트=nil) 세션 changeset 생성.

  Returns `{raw_token, changeset}` — 호출자는 raw_token 을 cookie 에 저장,
  changeset 을 Repo.insert 함. raw_token 은 절대 DB 에 저장 안 함.
  """
  def build(user_or_nil, nickname) when is_binary(nickname) do
    raw = :crypto.strong_rand_bytes(@token_bytes)
    hash = :crypto.hash(:sha256, raw)

    expires =
      DateTime.utc_now()
      |> DateTime.add(@session_validity_days, :day)
      |> DateTime.truncate(:second)

    attrs = %{
      token_hash: hash,
      nickname: nickname,
      expires_at: expires,
      user_id: user_id(user_or_nil)
    }

    {raw, change(%__MODULE__{}, attrs)}
  end

  @doc "Hash a raw token from a cookie for DB lookup."
  def hash_token(raw) when is_binary(raw), do: :crypto.hash(:sha256, raw)

  @doc "Convert raw bytes to base64url for cookie storage."
  def encode_token(raw) when is_binary(raw), do: Base.url_encode64(raw, padding: false)

  @doc "Decode base64url cookie value back to raw bytes. Returns :error on bad input."
  def decode_token(encoded) when is_binary(encoded) do
    case Base.url_decode64(encoded, padding: false) do
      {:ok, raw} when byte_size(raw) == @token_bytes -> {:ok, raw}
      _ -> :error
    end
  end

  def decode_token(_), do: :error

  defp user_id(nil), do: nil
  defp user_id(%User{id: id}), do: id
end
