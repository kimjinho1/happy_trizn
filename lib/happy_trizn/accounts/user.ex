defmodule HappyTrizn.Accounts.User do
  @moduledoc """
  등록 사용자 schema.

  - email: `@trizn.kr` 도메인 락 (외부 가입 차단)
  - nickname: 표시 이름, unique
  - password: bcrypt 해시 저장 (`password` 가상 필드 → `password_hash`)
  - status: `"active"` | `"banned"`. ban 처리는 admin 페이지에서.

  Admin 계정은 이 테이블에 없음 (.env 고정).
  """

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  @email_regex ~r/^[^\s@]+@trizn\.kr$/i
  @valid_statuses ~w(active banned)

  schema "users" do
    field :email, :string
    field :nickname, :string
    field :password, :string, virtual: true, redact: true
    field :password_hash, :string, redact: true
    field :status, :string, default: "active"

    timestamps(type: :utc_datetime)
  end

  @doc """
  회원가입용 changeset. email/nickname/password 검증 + bcrypt 해시.
  """
  def registration_changeset(user, attrs) do
    user
    |> cast(attrs, [:email, :nickname, :password])
    |> validate_required([:email, :nickname, :password])
    |> update_change(:email, &String.downcase/1)
    |> validate_format(:email, @email_regex, message: "must be a @trizn.kr address")
    |> validate_length(:email, max: 160)
    |> validate_length(:nickname, min: 2, max: 32)
    |> validate_format(:nickname, ~r/^[\p{L}\p{N}_\-]+$/u, message: "letters, numbers, _, - only")
    |> validate_length(:password, min: 8, max: 72)
    |> unique_constraint(:email)
    |> unique_constraint(:nickname)
    |> hash_password()
  end

  @doc "Admin ban/unban 용 (status 만 변경)."
  def status_changeset(user, attrs) do
    user
    |> cast(attrs, [:status])
    |> validate_inclusion(:status, @valid_statuses)
  end

  @doc "평문 비번을 저장된 해시와 비교 (timing-safe)."
  def valid_password?(%__MODULE__{password_hash: hash}, password)
      when is_binary(hash) and is_binary(password) do
    Bcrypt.verify_pass(password, hash)
  end

  def valid_password?(_, _), do: false

  defp hash_password(%Ecto.Changeset{valid?: true, changes: %{password: pw}} = cs) do
    cs
    |> put_change(:password_hash, Bcrypt.hash_pwd_salt(pw))
    |> delete_change(:password)
  end

  defp hash_password(changeset), do: changeset
end
