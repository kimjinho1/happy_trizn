defmodule HappyTrizn.Games.Tetris.Finesse do
  @moduledoc """
  Tetris 입력 효율 측정 (Sprint 3i).

  Spawn 후 hard_drop 까지의 left/right/rotate(_cw/_ccw/_180) 입력 수를
  optimal 과 비교. soft_drop / hold 는 finesse 입력으로 안 침.

  - actual <= optimal → :ok (effective)
  - actual > optimal  → :violation (player.finesse_violations++)

  ## Optimal 정의

  Spawn 위치 = (rotation=0, col=3) 모든 piece 동일 (Piece.spawn_origin/1).

  Optimal = rotation_inputs + horizontal_inputs.
  - rotation: 0회전 = 0, ±90 = 1, 180 = 1 (180 키 사용 시).
  - horizontal: abs(target_col - 3).

  O piece 는 회전 무의미 — rotation 부분 무시 (회전 입력 자체가 violation 유발).

  ## 한계

  벽 근처 wall-kick 으로 actual < heuristic 인 케이스 (희귀) 는 false-negative.
  finesse 점수는 통계용 — 정확도 100% 는 목표 아님.
  """

  @spawn_col 3

  @doc "spawn (rot=0, col=3) → (target_rot, target_col) 최적 입력 수."
  @spec optimal_count(atom(), 0..3, integer()) :: non_neg_integer()
  def optimal_count(:O, _rot, target_col), do: abs(target_col - @spawn_col)

  def optimal_count(_piece, target_rot, target_col)
      when target_rot in 0..3 do
    rot_inputs(target_rot) + abs(target_col - @spawn_col)
  end

  defp rot_inputs(0), do: 0
  defp rot_inputs(1), do: 1
  defp rot_inputs(2), do: 1
  defp rot_inputs(3), do: 1

  @doc """
  actual_inputs vs optimal → :ok | :violation.

  actual_inputs = piece spawn 부터 hard_drop 직전까지의
  left/right/rotate*(cw/ccw/180) 합.
  """
  @spec evaluate(atom(), 0..3, integer(), non_neg_integer()) :: :ok | :violation
  def evaluate(piece_type, target_rot, target_col, actual_inputs) do
    if actual_inputs > optimal_count(piece_type, target_rot, target_col) do
      :violation
    else
      :ok
    end
  end
end
