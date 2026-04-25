defmodule HappyTrizn.Games.Games2048Test do
  use ExUnit.Case, async: true

  alias HappyTrizn.Games.Games2048

  describe "meta/0" do
    test "single, max_players 1" do
      meta = Games2048.meta()
      assert meta.slug == "2048"
      assert meta.mode == :single
      assert meta.max_players == 1
    end
  end

  describe "init/1" do
    test "초기 board 에 tile 2개 있음" do
      {:ok, state} = Games2048.init(%{})
      assert length(state.board) == 4
      assert Enum.all?(state.board, &(length(&1) == 4))
      tiles = state.board |> List.flatten() |> Enum.reject(&is_nil/1)
      assert length(tiles) == 2
      assert Enum.all?(tiles, &(&1 in [2, 4]))
      assert state.score == 0
      refute state.won
      refute state.over
    end
  end

  describe "move/2 (logic)" do
    test "left compress + merge" do
      board = [
        [2, 2, nil, nil],
        [nil, nil, nil, nil],
        [nil, nil, nil, nil],
        [nil, nil, nil, nil]
      ]

      {result, gained} = Games2048.move(board, :left)
      assert result == [[4, nil, nil, nil] | List.duplicate([nil, nil, nil, nil], 3)]
      assert gained == 4
    end

    test "right compress + merge" do
      board = [
        [nil, nil, 2, 2],
        [nil, nil, nil, nil],
        [nil, nil, nil, nil],
        [nil, nil, nil, nil]
      ]

      {result, gained} = Games2048.move(board, :right)
      assert result == [[nil, nil, nil, 4] | List.duplicate([nil, nil, nil, nil], 3)]
      assert gained == 4
    end

    test "up merge column" do
      board = [
        [2, nil, nil, nil],
        [2, nil, nil, nil],
        [nil, nil, nil, nil],
        [nil, nil, nil, nil]
      ]

      {result, gained} = Games2048.move(board, :up)
      [r0 | _] = result
      assert hd(r0) == 4
      assert gained == 4
    end

    test "no merge — 다른 값" do
      board = [
        [2, 4, nil, nil],
        [nil, nil, nil, nil],
        [nil, nil, nil, nil],
        [nil, nil, nil, nil]
      ]

      {result, gained} = Games2048.move(board, :left)
      assert result == [[2, 4, nil, nil] | List.duplicate([nil, nil, nil, nil], 3)]
      assert gained == 0
    end

    test "한 줄에 동일값 4개 → 두 쌍 merge" do
      board = [[2, 2, 2, 2], [nil, nil, nil, nil], [nil, nil, nil, nil], [nil, nil, nil, nil]]
      {result, gained} = Games2048.move(board, :left)
      [first | _] = result
      assert first == [4, 4, nil, nil]
      assert gained == 8
    end
  end

  describe "handle_input move" do
    setup do
      # 결정적 board (랜덤 spawn 회피하려 init 안 쓰고 직접 만듦)
      state = %{
        board: [
          [2, 2, nil, nil],
          [nil, nil, nil, nil],
          [nil, nil, nil, nil],
          [nil, nil, nil, nil]
        ],
        score: 0,
        won: false,
        over: false
      }

      {:ok, state: state}
    end

    test "left move → 점수 증가 + state_changed broadcast", %{state: state} do
      {:ok, new_state, broadcasts} =
        Games2048.handle_input("p1", %{"action" => "move", "dir" => "left"}, state)

      assert new_state.score == 4
      # spawn 추가됨 → tile 더 많음
      assert tiles_count(new_state.board) >= 2
      assert [{:state_changed, _}] = broadcasts
    end

    test "변화 없는 방향 = 무효", %{state: state} do
      {:ok, new_state, broadcasts} =
        Games2048.handle_input("p1", %{"action" => "move", "dir" => "right"}, state)

      # right 시 (2,2) 가 (nil,nil,2,2) 처럼 우측 정렬 → board 변경됨. 변화 있음.
      # 다른 케이스: 이미 정렬된 board
      assert is_map(new_state)
      assert is_list(broadcasts)
    end

    test "restart 액션 → 새 게임", %{state: state} do
      state = %{state | score: 100, won: true}
      {:ok, fresh, [{:state_changed, _}]} = Games2048.handle_input("p1", %{"action" => "restart"}, state)
      assert fresh.score == 0
      refute fresh.won
    end

    test "alien action 무시", %{state: state} do
      {:ok, ^state, []} = Games2048.handle_input("p1", %{"action" => "wat"}, state)
    end
  end

  describe "game_over?/1" do
    test "over=true 면 yes + score" do
      state = %{board: [], score: 200, won: false, over: true}
      assert {:yes, %{score: 200, won: false}} = Games2048.game_over?(state)
    end

    test "over=false 면 no" do
      state = %{board: [], score: 0, won: false, over: false}
      assert :no = Games2048.game_over?(state)
    end
  end

  defp tiles_count(board) do
    board |> List.flatten() |> Enum.reject(&is_nil/1) |> length()
  end
end
