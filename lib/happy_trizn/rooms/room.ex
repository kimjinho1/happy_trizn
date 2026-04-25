defmodule HappyTrizn.Rooms.Room do
  @moduledoc """
  멀티게임 방 schema.

  - `game_type`: tetris / bomberman / skribbl / snake_io 등 (Sprint 3 게임 모듈 키).
  - `password_hash` + `password_salt`: SHA-256 + 16 byte salt. nil 이면 비번 없는 방.
  - `host_id`: 방 만든 사람. 강퇴 권한 있음. 호스트 disconnect 정책은 GameBehaviour 가 처리.
  - `max_players`: 게임별 default (Tetris 2, Bomberman 4, Skribbl 8 등).
  - `status`: `"open"` (입장 가능) / `"playing"` (게임 중) / `"closed"` (종료).
  """

  use Ecto.Schema
  import Ecto.Changeset

  alias HappyTrizn.Accounts.User

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  @valid_statuses ~w(open playing closed)
  @max_max_players 16

  schema "rooms" do
    field :game_type, :string
    field :name, :string
    field :password_salt, :binary
    field :password_hash, :binary
    field :max_players, :integer, default: 4
    field :status, :string, default: "open"
    field :password, :string, virtual: true, redact: true

    belongs_to :host, User, foreign_key: :host_id

    timestamps(type: :utc_datetime)
  end

  def create_changeset(room, attrs) do
    room
    |> cast(attrs, [:game_type, :name, :password, :host_id, :max_players])
    |> validate_required([:game_type, :name, :host_id])
    |> validate_length(:name, min: 1, max: 64)
    |> validate_length(:game_type, min: 1, max: 32)
    |> validate_number(:max_players, greater_than: 0, less_than_or_equal_to: @max_max_players)
    |> hash_password()
  end

  def status_changeset(room, attrs) do
    room
    |> cast(attrs, [:status])
    |> validate_inclusion(:status, @valid_statuses)
  end

  @doc "비번 검증 — nil 이면 비번 없는 방, 누구나 OK."
  def verify_password(%__MODULE__{password_hash: nil}, _), do: true
  def verify_password(_, nil), do: false
  def verify_password(_, ""), do: false

  def verify_password(%__MODULE__{password_salt: salt, password_hash: hash}, plain)
      when is_binary(salt) and is_binary(hash) and is_binary(plain) do
    expected = :crypto.hash(:sha256, salt <> plain)
    Plug.Crypto.secure_compare(expected, hash)
  end

  defp hash_password(%Ecto.Changeset{valid?: true, changes: %{password: pw}} = cs)
       when is_binary(pw) and pw != "" do
    salt = :crypto.strong_rand_bytes(16)
    hash = :crypto.hash(:sha256, salt <> pw)

    cs
    |> put_change(:password_salt, salt)
    |> put_change(:password_hash, hash)
    |> delete_change(:password)
  end

  defp hash_password(%Ecto.Changeset{changes: %{password: ""}} = cs) do
    # 빈 문자열 = 비번 없는 방으로 처리
    cs
    |> put_change(:password_salt, nil)
    |> put_change(:password_hash, nil)
    |> delete_change(:password)
  end

  defp hash_password(cs), do: cs
end
