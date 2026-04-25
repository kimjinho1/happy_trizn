defmodule HappyTrizn.UserGameSettings.Setting do
  @moduledoc """
  게임별 사용자 옵션 schema.

  - `key_bindings` — `%{action_name => [key, ...]}` map. Action 이름은 게임마다 정의.
  - `options` — 게임별 자유 옵션 map (Tetris: das/arr/grid/ghost/skin/...).
  """

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  @valid_game_types ~w(tetris bomberman skribbl snake_io games_2048 minesweeper pacman)

  schema "user_game_settings" do
    belongs_to :user, HappyTrizn.Accounts.User
    field :game_type, :string
    field :key_bindings, :map, default: %{}
    field :options, :map, default: %{}
    field :updated_at, :utc_datetime
  end

  def changeset(setting, attrs) do
    setting
    |> cast(attrs, [:user_id, :game_type, :key_bindings, :options])
    |> validate_required([:user_id, :game_type, :key_bindings, :options])
    |> validate_inclusion(:game_type, @valid_game_types)
    |> validate_length(:game_type, max: 32)
    |> unique_constraint([:user_id, :game_type])
    |> put_updated_at()
  end

  defp put_updated_at(cs) do
    put_change(cs, :updated_at, DateTime.utc_now() |> DateTime.truncate(:second))
  end
end
