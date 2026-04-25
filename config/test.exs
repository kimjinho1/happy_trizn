import Config

# Configure your database
#
# The MIX_TEST_PARTITION environment variable can be used
# to provide built-in test partitioning in CI environment.
# Run `mix help test` for more information.
config :happy_trizn, HappyTrizn.Repo,
  username: System.get_env("MYSQL_USER", "root"),
  password: System.get_env("MYSQL_PASSWORD", ""),
  hostname: System.get_env("MYSQL_HOST", "localhost"),
  port: String.to_integer(System.get_env("MYSQL_PORT", "3306")),
  database: "happy_trizn_test#{System.get_env("MIX_TEST_PARTITION")}",
  pool: Ecto.Adapters.SQL.Sandbox,
  pool_size: System.schedulers_online() * 2

# We don't run a server during test. If one is required,
# you can enable the server option below.
config :happy_trizn, HappyTriznWeb.Endpoint,
  http: [ip: {127, 0, 0, 1}, port: 4002],
  secret_key_base: "nV2BjvypqvlDR1yJrhRKdKnrxJrvH+giQj9wEvOsR2ifBHn3NZ03uf1zOlL92l7e",
  server: false

# In test we don't send emails
config :happy_trizn, HappyTrizn.Mailer, adapter: Swoosh.Adapters.Test

# Disable swoosh api client as it is only required for production adapters
config :swoosh, :api_client, false

# Print only warnings and errors during test
config :logger, level: :warning

# Initialize plugs at runtime for faster test compilation
config :phoenix, :plug_init_mode, :runtime

# Enable helpful, but potentially expensive runtime checks
config :phoenix_live_view,
  enable_expensive_runtime_checks: true

# Sort query params output of verified routes for robust url comparisons
config :phoenix,
  sort_verified_routes_query_params: true

# Bcrypt log rounds 4 (test 속도)
config :bcrypt_elixir, :log_rounds, 4

# Admin session secret + ip_whitelist 만 컴파일 타임 결정.
# password_hash 는 test_helper.exs 에서 런타임 hash 후 put_env (bcrypt cost 4).
config :happy_trizn, :admin,
  id: "admin",
  password_hash: nil,
  session_secret: "test_admin_session_secret_for_phoenix_token_sign_must_be_long",
  ip_whitelist: []

# Mongo url nil → Application.start 시 Mongo supervisor 안 띄움.
# Chat 모듈은 best-effort 라 :mongo 프로세스 없으면 skip.
config :happy_trizn, :mongo, url: nil, pool_size: 1
