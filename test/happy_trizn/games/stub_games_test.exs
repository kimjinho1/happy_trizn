defmodule HappyTrizn.Games.StubGamesTest do
  @moduledoc """
  Bomberman / Skribbl / SnakeIo / PacMan stub 모듈의 GameBehaviour smoke test.
  풀 logic 은 Sprint 3b. 일단 init/join/leave/meta 정상 동작.
  """

  use ExUnit.Case, async: true

  alias HappyTrizn.Games.{Bomberman, Skribbl, SnakeIo, PacMan}

  describe "Bomberman" do
    test "meta multi 4" do
      m = Bomberman.meta()
      assert m.slug == "bomberman"
      assert m.mode == :multi
      assert m.max_players == 4
    end

    test "join → state 누적" do
      {:ok, state} = Bomberman.init(%{})
      {:ok, s1, _} = Bomberman.handle_player_join("p1", %{}, state)
      assert map_size(s1.players) == 1
    end

    test "5번째 join 거부" do
      {:ok, state} = Bomberman.init(%{})

      filled =
        Enum.reduce(1..4, state, fn i, acc ->
          {:ok, new, _} = Bomberman.handle_player_join("p#{i}", %{}, acc)
          new
        end)

      assert {:reject, :full} = Bomberman.handle_player_join("p5", %{}, filled)
    end

    test "playing 중 leave → 1명 남으면 winner" do
      {:ok, state} = Bomberman.init(%{})
      {:ok, s1, _} = Bomberman.handle_player_join("p1", %{}, state)
      {:ok, s2, _} = Bomberman.handle_player_join("p2", %{}, s1)
      s2 = %{s2 | status: :playing}

      {:ok, after_leave, broadcasts} = Bomberman.handle_player_leave("p1", :disconnect, s2)
      assert after_leave.status == :over
      assert {:winner, "p2"} in broadcasts
    end
  end

  describe "Skribbl" do
    test "meta multi 8" do
      m = Skribbl.meta()
      assert m.slug == "skribbl"
      assert m.mode == :multi
      assert m.max_players == 8
    end

    test "join + leave smoke" do
      {:ok, state} = Skribbl.init(%{})
      {:ok, s1, _} = Skribbl.handle_player_join("p1", %{}, state)
      {:ok, s2, _} = Skribbl.handle_player_leave("p1", :quit, s1)
      assert map_size(s2.players) == 0
    end

    test "9번째 거부" do
      {:ok, state} = Skribbl.init(%{})

      filled =
        Enum.reduce(1..8, state, fn i, acc ->
          {:ok, new, _} = Skribbl.handle_player_join("p#{i}", %{}, acc)
          new
        end)

      assert {:reject, :full} = Skribbl.handle_player_join("p9", %{}, filled)
    end
  end

  describe "SnakeIo" do
    test "meta multi 16, min 1" do
      m = SnakeIo.meta()
      assert m.slug == "snake_io"
      assert m.mode == :multi
      assert m.max_players == 16
      assert m.min_players == 1
    end

    test "캐주얼 = max 16 까지 허용 + game_over 항상 :no" do
      {:ok, state} = SnakeIo.init(%{})

      filled =
        Enum.reduce(1..16, state, fn i, acc ->
          {:ok, new, _} = SnakeIo.handle_player_join("p#{i}", %{}, acc)
          new
        end)

      assert map_size(filled.players) == 16
      assert :no = SnakeIo.game_over?(filled)
    end
  end

  describe "PacMan" do
    test "meta single" do
      m = PacMan.meta()
      assert m.slug == "pacman"
      assert m.mode == :single
      assert m.max_players == 1
    end

    test "init state" do
      {:ok, state} = PacMan.init(%{})
      assert state.score == 0
      assert state.lives == 3
      assert state.over == false
    end

    test "game_over? over=false → :no" do
      {:ok, state} = PacMan.init(%{})
      assert :no = PacMan.game_over?(state)
    end

    test "game_over? over=true → yes + score" do
      assert {:yes, %{score: 100}} =
               PacMan.game_over?(%{score: 100, level: 1, lives: 0, over: true})
    end
  end
end
