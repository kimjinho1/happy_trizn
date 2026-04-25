defmodule HappyTrizn.Games.TetrisTest do
  use ExUnit.Case, async: true

  alias HappyTrizn.Games.Tetris

  describe "meta/0" do
    test "multi 1v1" do
      meta = Tetris.meta()
      assert meta.slug == "tetris"
      assert meta.mode == :multi
      assert meta.max_players == 2
      assert meta.min_players == 2
    end
  end

  describe "handle_player_join/3" do
    test "1번째 player → waiting" do
      {:ok, state} = Tetris.init(%{})
      {:ok, s1, _} = Tetris.handle_player_join("p1", %{}, state)
      assert s1.status == :waiting
      assert map_size(s1.players) == 1
    end

    test "2번째 player → playing" do
      {:ok, state} = Tetris.init(%{})
      {:ok, s1, _} = Tetris.handle_player_join("p1", %{}, state)
      {:ok, s2, _} = Tetris.handle_player_join("p2", %{}, s1)
      assert s2.status == :playing
      assert map_size(s2.players) == 2
    end

    test "3번째 player 거부 (full)" do
      {:ok, state} = Tetris.init(%{})
      {:ok, s1, _} = Tetris.handle_player_join("p1", %{}, state)
      {:ok, s2, _} = Tetris.handle_player_join("p2", %{}, s1)
      assert {:reject, :full} = Tetris.handle_player_join("p3", %{}, s2)
    end
  end

  describe "handle_player_leave/3 + winner" do
    test "playing 중 1명 나가면 남은 1명 자동 승" do
      {:ok, state} = Tetris.init(%{})
      {:ok, s1, _} = Tetris.handle_player_join("p1", %{}, state)
      {:ok, s2, _} = Tetris.handle_player_join("p2", %{}, s1)

      {:ok, after_leave, broadcasts} = Tetris.handle_player_leave("p1", :disconnect, s2)
      assert after_leave.status == :over
      assert after_leave.winner == "p2"
      assert {:winner, "p2"} in broadcasts
    end

    test "waiting 중 떠나면 그냥 player 제거" do
      {:ok, state} = Tetris.init(%{})
      {:ok, s1, _} = Tetris.handle_player_join("p1", %{}, state)

      {:ok, s2, broadcasts} = Tetris.handle_player_leave("p1", :quit, s1)
      assert map_size(s2.players) == 0
      assert s2.status == :waiting
      assert {:player_left, "p1"} in broadcasts
    end
  end

  describe "handle_input score_update" do
    test "score / lines 업데이트 + broadcast" do
      {:ok, state} = Tetris.init(%{})
      {:ok, s1, _} = Tetris.handle_player_join("p1", %{}, state)
      {:ok, s2, _} = Tetris.handle_player_join("p2", %{}, s1)

      {:ok, s3, broadcasts} =
        Tetris.handle_input(
          "p1",
          %{"action" => "score_update", "score" => 1500, "lines" => 12},
          s2
        )

      assert s3.players["p1"].score == 1500
      assert s3.players["p1"].lines == 12
      assert [{:score, %{player: "p1", score: 1500, lines: 12}}] = broadcasts
    end

    test "없는 player 의 score_update 는 무시" do
      {:ok, state} = Tetris.init(%{})
      {:ok, ^state, []} =
        Tetris.handle_input("ghost", %{"action" => "score_update", "score" => 100, "lines" => 1}, state)
    end
  end

  describe "handle_input top_out + winner" do
    test "한 player top_out → 상대 자동 승" do
      {:ok, state} = Tetris.init(%{})
      {:ok, s1, _} = Tetris.handle_player_join("p1", %{}, state)
      {:ok, s2, _} = Tetris.handle_player_join("p2", %{}, s1)

      {:ok, s3, broadcasts} = Tetris.handle_input("p1", %{"action" => "top_out"}, s2)

      assert s3.status == :over
      assert s3.winner == "p2"
      assert {:winner, "p2"} in broadcasts
    end
  end

  describe "handle_input garbage routing" do
    test "p1 garbage → p2 에게 전송 broadcast" do
      {:ok, state} = Tetris.init(%{})
      {:ok, s1, _} = Tetris.handle_player_join("p1", %{}, state)
      {:ok, s2, _} = Tetris.handle_player_join("p2", %{}, s1)

      {:ok, _s3, [{:garbage, %{from: "p1", to: "p2", lines: 4}}]} =
        Tetris.handle_input("p1", %{"action" => "garbage", "lines" => 4}, s2)
    end
  end

  describe "game_over?/1" do
    test "status :over → yes" do
      state = %{players: %{"p1" => %{}}, status: :over, winner: "p1"}
      assert {:yes, %{winner: "p1"}} = Tetris.game_over?(state)
    end

    test "status :playing → no" do
      state = %{players: %{}, status: :playing, winner: nil}
      assert :no = Tetris.game_over?(state)
    end
  end
end
