defmodule HappyTrizn.RateLimit do
  @moduledoc """
  Hammer 7.x module-based rate limiter (in-memory ETS backend).

  ## Buckets

  - `admin_login:<ip>` — 5/min, admin /admin/login 폼
  - `register:<ip>` — 3/min, 회원가입 spam 방어
  - `chat:<user_or_ip>` — 5/10s, 글로벌 채팅 도배 방어

  ## 사용

      case HappyTrizn.RateLimit.hit("admin_login:" <> ip, 60_000, 5) do
        {:allow, count} -> :ok
        {:deny, retry_after_ms} -> {:error, :rate_limited}
      end
  """

  use Hammer, backend: :ets
end
