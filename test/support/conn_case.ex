defmodule HappyTriznWeb.ConnCase do
  @moduledoc """
  This module defines the test case to be used by
  tests that require setting up a connection.

  Such tests rely on `Phoenix.ConnTest` and also
  import other functionality to make it easier
  to build common data structures and query the data layer.

  Finally, if the test case interacts with the database,
  we enable the SQL sandbox, so changes done to the database
  are reverted at the end of every test. If you are using
  PostgreSQL, you can even run database tests asynchronously
  by setting `use HappyTriznWeb.ConnCase, async: true`, although
  this option is not recommended for other databases.
  """

  use ExUnit.CaseTemplate

  using do
    quote do
      # The default endpoint for testing
      @endpoint HappyTriznWeb.Endpoint

      use HappyTriznWeb, :verified_routes

      # Import conveniences for testing with connections
      import Plug.Conn
      import Phoenix.ConnTest
      import HappyTriznWeb.ConnCase
    end
  end

  setup tags do
    HappyTrizn.DataCase.setup_sandbox(tags)

    # 각 테스트 unique remote_ip — RateLimit ETS 격리.
    # Hammer key 가 IP 기반이라 같은 IP 면 테스트 간 카운터 누적.
    ip = {127, 0, 0, :rand.uniform(253) + 1}
    conn = Phoenix.ConnTest.build_conn() |> Map.put(:remote_ip, ip)
    {:ok, conn: conn}
  end

  @doc """
  사용자(또는 게스트=nil) 세션 발급 후 conn 에 cookie + plug session 심음.
  컨트롤러/Plug 테스트에서 인증된 상태 시뮬레이션용.
  """
  def log_in_user(conn, user_or_nil, nickname \\ nil) do
    {:ok, raw, _session} =
      case user_or_nil do
        nil ->
          HappyTrizn.Accounts.create_guest_session(
            nickname || "guest_#{System.unique_integer([:positive])}"
          )

        user ->
          HappyTrizn.Accounts.create_user_session(user)
      end

    encoded = HappyTrizn.Accounts.Session.encode_token(raw)
    cookie_name = HappyTriznWeb.Plugs.FetchCurrentUser.cookie_name()

    conn
    |> Phoenix.ConnTest.init_test_session(%{session_token: encoded})
    |> Plug.Test.put_req_cookie(cookie_name, encoded)
  end

  @doc """
  Admin 세션 cookie 심음. EnsureAdmin Plug 통과시키는 용.
  """
  def log_in_admin(conn, admin_id \\ nil) do
    cfg = Application.get_env(:happy_trizn, :admin, [])
    id = admin_id || Keyword.get(cfg, :id, "admin")
    secret = Keyword.fetch!(cfg, :session_secret)
    token = Phoenix.Token.sign(secret, "admin", id)
    cookie_name = HappyTriznWeb.Plugs.EnsureAdmin.cookie_name()

    Plug.Test.put_req_cookie(conn, cookie_name, token)
  end

  @doc """
  표준 사용자 fixture.
  """
  def user_fixture(attrs \\ %{}) do
    nickname_suffix = System.unique_integer([:positive])

    attrs =
      Enum.into(attrs, %{
        email: "user#{nickname_suffix}@trizn.kr",
        nickname: "user#{nickname_suffix}",
        password: "hello12345"
      })

    {:ok, user} = HappyTrizn.Accounts.register_user(attrs)
    user
  end
end
