# This file is responsible for configuring your application
# and its dependencies with the aid of the Config module.
#
# This configuration file is loaded before any dependency and
# is restricted to this project.

# General application configuration
import Config

config :happy_trizn,
  ecto_repos: [HappyTrizn.Repo],
  generators: [timestamp_type: :utc_datetime]

# 게임 모듈 레지스트리. 새 게임 추가 = 이 list 에 한 줄 + GameBehaviour 구현 폴더.
config :happy_trizn, :games, [
  HappyTrizn.Games.Games2048,
  HappyTrizn.Games.Minesweeper,
  HappyTrizn.Games.PacMan,
  HappyTrizn.Games.Tetris,
  HappyTrizn.Games.Bomberman,
  HappyTrizn.Games.Skribbl,
  HappyTrizn.Games.SnakeIo
]

# Configure the endpoint
config :happy_trizn, HappyTriznWeb.Endpoint,
  url: [host: "localhost"],
  adapter: Bandit.PhoenixAdapter,
  render_errors: [
    formats: [html: HappyTriznWeb.ErrorHTML, json: HappyTriznWeb.ErrorJSON],
    layout: false
  ],
  pubsub_server: HappyTrizn.PubSub,
  live_view: [signing_salt: "rRgEtkeK"]

# Configure the mailer
#
# By default it uses the "Local" adapter which stores the emails
# locally. You can see the emails in your browser, at "/dev/mailbox".
#
# For production it's recommended to configure a different adapter
# at the `config/runtime.exs`.
config :happy_trizn, HappyTrizn.Mailer, adapter: Swoosh.Adapters.Local

# Configure esbuild (the version is required)
config :esbuild,
  version: "0.25.4",
  happy_trizn: [
    args:
      ~w(js/app.js --bundle --target=es2022 --outdir=../priv/static/assets/js --external:/fonts/* --external:/images/* --alias:@=.),
    cd: Path.expand("../assets", __DIR__),
    env: %{"NODE_PATH" => [Path.expand("../deps", __DIR__), Mix.Project.build_path()]}
  ]

# Configure tailwind (the version is required)
config :tailwind,
  version: "4.1.12",
  happy_trizn: [
    args: ~w(
      --input=assets/css/app.css
      --output=priv/static/assets/css/app.css
    ),
    cd: Path.expand("..", __DIR__)
  ]

# Configure Elixir's Logger
config :logger, :default_formatter,
  format: "$time $metadata[$level] $message\n",
  metadata: [:request_id]

# Use Jason for JSON parsing in Phoenix
config :phoenix, :json_library, Jason

# Import environment specific config. This must remain at the bottom
# of this file so it overrides the configuration defined above.
import_config "#{config_env()}.exs"
