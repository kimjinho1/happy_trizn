# Happy Trizn

사내 게임 허브. Elixir + Phoenix LiveView 기반.

- 디자인 문서: [DESIGN.md](DESIGN.md)
- 테스트 계획: [TEST_PLAN.md](TEST_PLAN.md)
- 게임 라인업: Tetris, Bomberman, Skribbl, Snake.io, 2048, Minesweeper, Pac-Man

## 셋업 (Docker only, 로컬 Elixir 불필요)

전제: Docker Desktop (또는 Docker Engine) 설치 + 데몬 실행 중.

```bash
# 1. 리포 클론
git clone <repo> happy_trizn && cd happy_trizn

# 2. 환경 변수
cp .env.example .env
# .env 파일 열고 SECRET_KEY_BASE, MYSQL_PASSWORD, ADMIN_PASSWORD_HASH 등 채움
# bin/mix phx.gen.secret 으로 SECRET_KEY_BASE 생성 가능 (Phoenix scaffold 후)

# 3. Phoenix scaffold (최초 1회)
bin/mix phx.new . --app happy_trizn --module HappyTrizn --database mysql --no-install

# 4. 의존성 설치
bin/mix deps.get

# 5. Docker Compose 부팅
docker compose up -d
```

## 포트 (`47xxx` prefix로 충돌 회피)

| 서비스 | 호스트 | 컨테이너 |
|---|---|---|
| Phoenix | 4747 | 4000 |
| MySQL | (노출 X) | 3306 |
| MongoDB | (노출 X) | 27017 |
| MySQL dev override | 47306 | 3306 |
| MongoDB dev override | 47017 | 27017 |

`docker-compose.override.yml`은 git ignored — 로컬 디버깅 시 DB 호스트 노출용.

## UFW (사내망만 접속 허용)

```bash
sudo ufw allow from <사내_서브넷> to any port 4747 proto tcp
sudo ufw deny 4747
```

## 개발 명령 (모두 `bin/mix` 통해 Docker로 실행)

```bash
bin/mix deps.get          # 의존성 설치
bin/mix ecto.create       # MySQL DB 생성
bin/mix ecto.migrate      # 마이그레이션
bin/mix test              # 테스트
bin/mix phx.gen.secret    # 시크릿 생성
bin/mix phx.server        # 개발 서버 (보통 docker compose up이 더 편함)
```

## 브랜치

- `main` — 안정 버전
- `feat/sprint-1-scaffold` — Sprint 1 작업 중 (현재)

## Sprint 진행 상황

- [x] Sprint 1: 기반 (scaffold, docker, 게스트, 회원가입, 로그인, 채팅, admin)
  - [x] Phoenix 1.8 + LiveView 1.1 scaffold (mix phx.new --database mysql)
  - [x] deps: bcrypt_elixir, mongodb_driver, hammer, cachex, broadway
  - [x] Multi-stage Dockerfile + docker-compose (4747 / 47306 / 47017 prefix)
  - [x] Users + Sessions migration (DB-backed session for redeploy survival)
  - [x] Accounts context (register/authenticate/sessions, 단위 테스트 25+ 케이스)
  - [x] @trizn.kr 도메인 락 + bcrypt 비번
  - [x] 게스트 모드 (닉네임만, DB session, user_id null)
  - [x] / (PageController) — 닉네임 폼 + 로그인/가입/admin 링크
  - [x] /lobby (LobbyLive) — 글로벌 채팅 (Phoenix.PubSub) + 게임 카테고리
  - [x] MongoDB chat_logs 영구 저장 (best-effort, Mongo 다운 시 skip)
  - [x] Admin (.env 고정 계정, EnsureAdmin Plug, /admin/users, ban/unban)
  - [x] admin_actions 감사 로그
  - [x] Hammer rate limit (admin login 5/min, register 3/min, chat 5/10s)
- [ ] Sprint 2: 친구/로비 (친구목록, DM, 방 시스템, GameBehaviour)
- [ ] Sprint 3: 게임 7개 (Tetris, Bomberman, Skribbl, Snake.io, 2048, Minesweeper, Pac-Man)
- [ ] Sprint 4: 마감 (영구 기록, MongoDB Broadway 큐, 배포)
