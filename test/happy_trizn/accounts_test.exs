defmodule HappyTrizn.AccountsTest do
  use HappyTrizn.DataCase, async: true

  alias HappyTrizn.Accounts
  alias HappyTrizn.Accounts.{User, Session}

  @valid_attrs %{
    email: "alice@trizn.kr",
    nickname: "alice",
    password: "supersecret"
  }

  describe "register_user/1" do
    test "@trizn.kr 도메인으로 가입 성공" do
      assert {:ok, %User{} = user} = Accounts.register_user(@valid_attrs)
      assert user.email == "alice@trizn.kr"
      assert user.nickname == "alice"
      assert user.status == "active"
      assert user.password_hash
      refute user.password_hash == "supersecret"
    end

    test "외부 도메인 거부 (@gmail.com)" do
      attrs = %{@valid_attrs | email: "alice@gmail.com"}
      assert {:error, cs} = Accounts.register_user(attrs)
      assert "must be a @trizn.kr address" in errors_on(cs).email
    end

    test "외부 도메인 거부 (@trizn.kr.evil.com)" do
      attrs = %{@valid_attrs | email: "alice@trizn.kr.evil.com"}
      assert {:error, cs} = Accounts.register_user(attrs)
      assert "must be a @trizn.kr address" in errors_on(cs).email
    end

    test "대문자 도메인 정규화" do
      attrs = %{@valid_attrs | email: "Alice@TRIZN.KR"}
      assert {:ok, user} = Accounts.register_user(attrs)
      assert user.email == "alice@trizn.kr"
    end

    test "이메일 중복 거부" do
      assert {:ok, _} = Accounts.register_user(@valid_attrs)
      attrs = %{@valid_attrs | nickname: "alice2"}
      assert {:error, cs} = Accounts.register_user(attrs)
      assert "has already been taken" in errors_on(cs).email
    end

    test "닉네임 중복 거부" do
      assert {:ok, _} = Accounts.register_user(@valid_attrs)
      attrs = %{@valid_attrs | email: "bob@trizn.kr"}
      assert {:error, cs} = Accounts.register_user(attrs)
      assert "has already been taken" in errors_on(cs).nickname
    end

    test "비번 8자 미만 거부" do
      attrs = %{@valid_attrs | password: "short"}
      assert {:error, cs} = Accounts.register_user(attrs)
      assert "should be at least 8 character(s)" in errors_on(cs).password
    end

    test "닉네임 한글 OK" do
      attrs = %{@valid_attrs | nickname: "김철수"}
      assert {:ok, user} = Accounts.register_user(attrs)
      assert user.nickname == "김철수"
    end

    test "닉네임 특수문자 거부" do
      attrs = %{@valid_attrs | nickname: "alice!@#"}
      assert {:error, cs} = Accounts.register_user(attrs)
      assert "letters, numbers, _, - only" in errors_on(cs).nickname
    end
  end

  describe "authenticate/2" do
    setup do
      {:ok, user} = Accounts.register_user(@valid_attrs)
      {:ok, user: user}
    end

    test "정확한 비번이면 user 반환", %{user: user} do
      assert {:ok, %User{id: id}} = Accounts.authenticate(user.email, "supersecret")
      assert id == user.id
    end

    test "이메일 대문자도 매치", %{user: _} do
      assert {:ok, _} = Accounts.authenticate("ALICE@trizn.kr", "supersecret")
    end

    test "잘못된 비번은 invalid_credentials", %{user: user} do
      assert {:error, :invalid_credentials} =
               Accounts.authenticate(user.email, "wrong_password")
    end

    test "ban 된 사용자는 :banned 반환", %{user: user} do
      {:ok, _} = Accounts.ban_user(user)
      assert {:error, :banned} = Accounts.authenticate(user.email, "supersecret")
    end

    test "없는 이메일은 invalid_credentials" do
      assert {:error, :invalid_credentials} =
               Accounts.authenticate("ghost@trizn.kr", "anything")
    end
  end

  describe "ban_user/1" do
    setup do
      {:ok, user} = Accounts.register_user(@valid_attrs)
      {:ok, user: user}
    end

    test "status 가 banned 로 바뀜", %{user: user} do
      assert {:ok, banned} = Accounts.ban_user(user)
      assert banned.status == "banned"
    end

    test "ban 시 모든 세션 무효화", %{user: user} do
      {:ok, raw, _s} = Accounts.create_user_session(user)
      assert Accounts.get_session_by_token(raw) != nil

      {:ok, _} = Accounts.ban_user(user)
      assert Accounts.get_session_by_token(raw) == nil
    end

    test "unban 으로 복구", %{user: user} do
      {:ok, _} = Accounts.ban_user(user)
      {:ok, restored} = Accounts.unban_user(user)
      assert restored.status == "active"
    end
  end

  describe "create_user_session/1" do
    setup do
      {:ok, user} = Accounts.register_user(@valid_attrs)
      {:ok, user: user}
    end

    test "세션 발급 + 토큰 32 byte raw", %{user: user} do
      assert {:ok, raw, %Session{} = session} = Accounts.create_user_session(user)
      assert is_binary(raw)
      assert byte_size(raw) == 32
      assert session.user_id == user.id
      assert session.nickname == user.nickname
    end

    test "토큰으로 user + session 조회", %{user: user} do
      {:ok, raw, _s} = Accounts.create_user_session(user)
      assert {%User{id: uid}, %Session{}} = Accounts.get_session_by_token(raw)
      assert uid == user.id
    end

    test "banned 유저는 세션 발급 거부", %{user: user} do
      {:ok, banned} = Accounts.ban_user(user)
      assert {:error, :banned} = Accounts.create_user_session(banned)
    end
  end

  describe "create_guest_session/1" do
    test "닉네임만으로 게스트 세션" do
      assert {:ok, raw, %Session{user_id: nil}} = Accounts.create_guest_session("guest_x")
      assert byte_size(raw) == 32

      assert {nil, %Session{nickname: "guest_x"}} = Accounts.get_session_by_token(raw)
    end

    test "닉네임 trim" do
      assert {:ok, _, session} = Accounts.create_guest_session("  spaced  ")
      assert session.nickname == "spaced"
    end

    test "1자 거부" do
      assert {:error, :nickname_too_short} = Accounts.create_guest_session("a")
    end

    test "33자 거부" do
      long = String.duplicate("x", 33)
      assert {:error, :nickname_too_long} = Accounts.create_guest_session(long)
    end
  end

  describe "get_session_by_token/1" do
    test "잘못된 토큰은 nil" do
      assert nil == Accounts.get_session_by_token("not-a-real-token")
    end

    test "non-binary 입력은 nil" do
      assert nil == Accounts.get_session_by_token(nil)
      assert nil == Accounts.get_session_by_token(123)
    end

    test "만료된 세션은 nil + 자동 삭제" do
      {:ok, user} = Accounts.register_user(@valid_attrs)
      {:ok, raw, session} = Accounts.create_user_session(user)

      past = DateTime.utc_now() |> DateTime.add(-1, :day) |> DateTime.truncate(:second)

      session
      |> Ecto.Changeset.change(expires_at: past)
      |> HappyTrizn.Repo.update!()

      assert nil == Accounts.get_session_by_token(raw)
      assert nil == HappyTrizn.Repo.get(Session, session.id)
    end
  end
end
