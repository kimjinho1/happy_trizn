ExUnit.start()
Ecto.Adapters.SQL.Sandbox.mode(HappyTrizn.Repo, :manual)

# Admin 비번 해시 런타임 생성 후 application env 에 주입.
# 평문 = "admin1234". bcrypt cost 4 (config/test.exs).
# id, session_secret 도 강제 — runtime.exs 가 .env 에서 다른 값으로 override 했을 수 있음.
Application.put_env(
  :happy_trizn,
  :admin,
  id: "admin",
  password_hash: Bcrypt.hash_pwd_salt("admin1234"),
  session_secret: "test_admin_session_secret_for_phoenix_token_sign_must_be_long",
  ip_whitelist: []
)
