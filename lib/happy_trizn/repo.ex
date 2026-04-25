defmodule HappyTrizn.Repo do
  use Ecto.Repo,
    otp_app: :happy_trizn,
    adapter: Ecto.Adapters.MyXQL
end
