defmodule HappyTrizn.Repo.Migrations.AddAvatarToUsers do
  use Ecto.Migration

  def change do
    alter table(:users) do
      # `/uploads/avatars/<user_id>.<ext>` 경로 저장. 미업로드 시 nil → emoji fallback.
      add :avatar_url, :string, size: 255
    end
  end
end
