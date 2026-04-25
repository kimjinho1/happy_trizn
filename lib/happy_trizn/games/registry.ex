defmodule HappyTrizn.Games.Registry do
  @moduledoc """
  게임 모듈 레지스트리.

  config/config.exs 에 게임 모듈 list 등록. 부팅 시 `meta/0` 호출해 캐시.
  Sprint 3 에서 게임 모듈 추가 = config list 에 한 줄 + 폴더 하나.

  ## Config

      config :happy_trizn, :games, [
        HappyTrizn.Games.Tetris,
        HappyTrizn.Games.Bomberman,
        ...
      ]

  ## API

      Registry.list_all()      # [%{name, slug, mode, max_players, ...}, ...]
      Registry.list_multi()    # 멀티만
      Registry.list_single()   # 싱글만
      Registry.get_module("tetris")  # HappyTrizn.Games.Tetris
      Registry.get_meta("tetris")    # %{name: "Tetris", ...}
  """

  @doc "config 의 모든 게임 모듈 list."
  def all_modules do
    Application.get_env(:happy_trizn, :games, [])
  end

  @doc "각 모듈의 meta() 결과 list."
  def list_all do
    Enum.map(all_modules(), & &1.meta())
  end

  def list_multi, do: list_all() |> Enum.filter(&(&1.mode == :multi))
  def list_single, do: list_all() |> Enum.filter(&(&1.mode == :single))

  def get_module(slug) when is_binary(slug) do
    Enum.find(all_modules(), fn mod -> mod.meta().slug == slug end)
  end

  def get_meta(slug) when is_binary(slug) do
    case get_module(slug) do
      nil -> nil
      mod -> mod.meta()
    end
  end

  def valid_slug?(slug), do: get_module(slug) != nil
end
