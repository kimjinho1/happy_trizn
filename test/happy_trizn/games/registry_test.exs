defmodule HappyTrizn.Games.RegistryTest do
  use ExUnit.Case, async: false
  # async: false — Application env 변경

  alias HappyTrizn.Games.Registry

  defmodule FakeGame do
    @behaviour HappyTrizn.Games.GameBehaviour

    @impl true
    def init(_), do: {:ok, %{}}
    @impl true
    def handle_input(_, _, state), do: {:ok, state, []}
    @impl true
    def handle_player_join(_, _, state), do: {:ok, state, []}
    @impl true
    def handle_player_leave(_, _, state), do: {:ok, state, []}
    @impl true
    def tick(state), do: {:ok, state, []}
    @impl true
    def game_over?(_), do: :no
    @impl true
    def terminate(_, _), do: :ok
    @impl true
    def meta do
      %{
        name: "Fake",
        slug: "fake",
        mode: :multi,
        max_players: 4,
        min_players: 2,
        description: "test only"
      }
    end
  end

  defmodule FakeSolo do
    @behaviour HappyTrizn.Games.GameBehaviour

    @impl true
    def init(_), do: {:ok, %{}}
    @impl true
    def handle_input(_, _, state), do: {:ok, state, []}
    @impl true
    def handle_player_join(_, _, state), do: {:ok, state, []}
    @impl true
    def handle_player_leave(_, _, state), do: {:ok, state, []}
    @impl true
    def tick(state), do: {:ok, state, []}
    @impl true
    def game_over?(_), do: :no
    @impl true
    def terminate(_, _), do: :ok
    @impl true
    def meta, do: %{name: "Solo", slug: "solo", mode: :single, max_players: 1}
  end

  setup do
    original = Application.get_env(:happy_trizn, :games, [])
    Application.put_env(:happy_trizn, :games, [FakeGame, FakeSolo])
    on_exit(fn -> Application.put_env(:happy_trizn, :games, original) end)
    :ok
  end

  describe "list_*" do
    test "list_all 전체 meta" do
      assert [%{slug: "fake"}, %{slug: "solo"}] = Registry.list_all()
    end

    test "list_multi 만" do
      assert [%{slug: "fake", mode: :multi}] = Registry.list_multi()
    end

    test "list_single 만" do
      assert [%{slug: "solo", mode: :single}] = Registry.list_single()
    end
  end

  describe "get_*" do
    test "get_module / get_meta" do
      assert Registry.get_module("fake") == FakeGame
      assert %{name: "Fake"} = Registry.get_meta("fake")
    end

    test "없는 slug = nil" do
      assert Registry.get_module("nonexistent") == nil
      assert Registry.get_meta("nonexistent") == nil
    end

    test "valid_slug?" do
      assert Registry.valid_slug?("fake")
      refute Registry.valid_slug?("nonexistent")
    end
  end

  describe "all_modules/0 with empty config" do
    test "empty list returns []" do
      Application.put_env(:happy_trizn, :games, [])
      assert Registry.list_all() == []
      assert Registry.list_multi() == []
      assert Registry.list_single() == []
    end
  end
end
