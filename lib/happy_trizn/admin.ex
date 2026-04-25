defmodule HappyTrizn.Admin do
  @moduledoc """
  Admin 액션 감사 로그 + 관리 작업 진입점.

  Admin 인증 자체는 .env 고정 계정 + EnsureAdmin Plug 가 담당. 이 모듈은 액션
  추적 / 통계 / 향후 다중 admin 확장 지점.
  """

  import Ecto.Query, warn: false

  alias HappyTrizn.Repo
  alias HappyTrizn.Admin.AdminAction

  @doc """
  Admin 액션 감사 로그.

  ## 예
      Admin.log_action("admin", "ban", target_user_id: user.id, payload: %{reason: "spam"})
  """
  def log_action(admin_id, action, opts \\ []) do
    attrs = %{
      admin_id: admin_id,
      action: action,
      target_user_id: Keyword.get(opts, :target_user_id),
      target_room_id: Keyword.get(opts, :target_room_id),
      payload: Keyword.get(opts, :payload)
    }

    %AdminAction{}
    |> AdminAction.changeset(attrs)
    |> Repo.insert()
  end

  def list_actions(opts \\ []) do
    limit = Keyword.get(opts, :limit, 100)
    action = Keyword.get(opts, :action)

    AdminAction
    |> maybe_filter_action(action)
    |> order_by(desc: :inserted_at)
    |> limit(^limit)
    |> Repo.all()
  end

  defp maybe_filter_action(query, nil), do: query
  defp maybe_filter_action(query, action), do: from(a in query, where: a.action == ^action)
end
