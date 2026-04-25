defmodule HappyTrizn.RateLimitTest do
  use ExUnit.Case, async: true

  alias HappyTrizn.RateLimit

  defp unique_key(prefix), do: "#{prefix}:#{System.unique_integer([:positive])}"

  describe "hit/3" do
    test "limit 안에서는 :allow" do
      key = unique_key("test_allow")
      assert {:allow, 1} = RateLimit.hit(key, 1_000, 3)
      assert {:allow, 2} = RateLimit.hit(key, 1_000, 3)
      assert {:allow, 3} = RateLimit.hit(key, 1_000, 3)
    end

    test "limit 초과 시 :deny + retry_after" do
      key = unique_key("test_deny")
      RateLimit.hit(key, 60_000, 2)
      RateLimit.hit(key, 60_000, 2)

      assert {:deny, retry_after} = RateLimit.hit(key, 60_000, 2)
      assert is_integer(retry_after)
      assert retry_after > 0
    end

    test "다른 key 끼리 격리" do
      key_a = unique_key("test_iso_a")
      key_b = unique_key("test_iso_b")

      RateLimit.hit(key_a, 60_000, 1)
      assert {:deny, _} = RateLimit.hit(key_a, 60_000, 1)
      # b 는 영향 없음
      assert {:allow, 1} = RateLimit.hit(key_b, 60_000, 1)
    end

    test "scale_ms 만료 후 카운터 리셋" do
      key = unique_key("test_reset")
      assert {:allow, 1} = RateLimit.hit(key, 50, 1)
      assert {:deny, _} = RateLimit.hit(key, 50, 1)
      Process.sleep(60)
      assert {:allow, 1} = RateLimit.hit(key, 50, 1)
    end
  end
end
