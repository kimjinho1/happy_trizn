# Happy Trizn

사내 게임 허브. Elixir + Phoenix LiveView + MySQL + MongoDB.

- 디자인 문서: [DESIGN.md](DESIGN.md)
- 게임별 본격 spec (Jstris 수준): [GAMES_SPEC.md](GAMES_SPEC.md)
- 테스트 계획: [TEST_PLAN.md](TEST_PLAN.md)
- 게임 라인업: Tetris ✅, 캐치마인드 ✅, Bomberman ⏳, Snake.io ⏳, 2048 (싱글 ✅), Minesweeper (싱글 ✅), Pac-Man ⏳

---

## 목차

- [기능](#기능)
- [요구 사항](#요구-사항)
- [최초 셋업](#최초-셋업)
- [Docker 운영 명령](#docker-운영-명령)
- [개발 명령 (mix wrapper)](#개발-명령-mix-wrapper)
- [DB 접속](#db-접속)
- [백업 / 복원](#백업--복원)
- [데이터 리셋](#데이터-리셋)
- [시크릿 재생성](#시크릿-재생성)
- [포트 / 네트워크](#포트--네트워크)
- [UFW (사내망만 허용)](#ufw-사내망만-허용)
- [트러블슈팅](#트러블슈팅)
- [브랜치 / Sprint 진행](#브랜치--sprint-진행)

---

## 기능

**Sprint 1 완료** (PR #1 + #2 + #3):

- 게스트 모드: 닉네임만 입력하면 즉시 입장 (DB session, user_id=null)
- 회원가입: `@trizn.kr` 도메인 정규식 락 + bcrypt 비번 (외부 가입 차단)
- 로그인 / 로그아웃: DB-backed session (재배포 시 로그인 유지)
- 글로벌 채팅: `LobbyLive` LiveView, Phoenix.PubSub broadcast, MongoDB 영구 저장
- Admin 페이지: `.env` 고정 계정, `EnsureAdmin` Plug, 사용자 목록 / ban / unban
- `admin_actions` 감사 로그
- Rate limit (admin login 5/min, register 3/min, chat 5/10s)
- WebSocket origin 화이트리스트 (PHX_HOST + localhost + 127.0.0.1)
- oneshot migrate service — `docker compose up -d` 한 번에 마이그까지
- 단위/통합 테스트 105개 (Plugs, Controllers, LiveView, 도메인 모듈)

향후 (DESIGN.md 참고):

- Sprint 2 ✅: 친구 시스템, 방 시스템, GameBehaviour 모듈러 인터페이스
- Sprint 3 ⏳: 7게임 (Tetris ✅, 캐치마인드 ✅, 2048 / Minesweeper 싱글 ✅, Bomberman / Snake.io / Pac-Man 미구현)
- Sprint 4 ⏳: DM, 알림, 영구 기록 Broadway Mongo 큐, 사내 서버 배포 + HTTPS

---

## 요구 사항

- Docker Desktop (or Docker Engine) + Docker Compose v2
- Git
- 로컬 Elixir 설치 **불필요** (`bin/mix` wrapper 가 Docker 안에서 mix 실행)

---

## 최초 셋업

```bash
# 1. 리포 클론
git clone https://github.com/kimjinho1/happy_trizn.git && cd happy_trizn

# 2. 환경 변수
cp .env.example .env
# .env 열고 SECRET_KEY_BASE, MYSQL_PASSWORD, ADMIN_PASSWORD_HASH 등 채움.
# 시크릿 생성 명령은 "시크릿 재생성" 섹션 참고.

# 3. Phoenix scaffold (이미 commit 됨, 새 환경에서만 다시)
# bin/mix phx.new . --app happy_trizn --module HappyTrizn --database mysql --no-install

# 4. 의존성 설치 (Docker volume 캐시)
bin/mix deps.get

# 5. Docker Compose 부팅 (mysql + mongo + app)
docker compose up -d --build

# 6. DB 마이그레이션 (최초 1회)
docker compose exec app /app/bin/migrate

# 7. 동작 확인
curl -i http://localhost:4747
# 브라우저: http://localhost:4747
# Admin: http://localhost:4747/admin/login (.env 의 ADMIN_ID / 평문 비번)
```

---

## Docker 운영 명령

### 시작 / 정지

```bash
docker compose up -d              # 백그라운드 부팅
docker compose up                 # 포그라운드 (Ctrl+C 로 정지)
docker compose stop               # 컨테이너 정지 (volume 보존)
docker compose start              # 정지된 컨테이너 다시 시작
docker compose restart            # 모든 서비스 재시작
docker compose restart app        # app 만 재시작 (코드 변경 후)
docker compose down               # 컨테이너 삭제 (volume 보존)
docker compose down -v            # 컨테이너 + volume 삭제 (DB 데이터 날아감)
```

### 빌드 / 업데이트

```bash
docker compose build              # 이미지 빌드 (코드 변경 시)
docker compose build --no-cache   # 캐시 무시 풀 빌드
docker compose build app          # app 만 다시 빌드
docker compose up -d --build      # 빌드 후 부팅
docker compose pull               # GHCR 등 remote 이미지 갱신 (운영)
```

### 코드 변경 후 재배포 (한 줄 — 가장 자주 씀)

```bash
DOCKER_BUILDKIT=1 docker compose build app && \
  docker compose up -d --no-deps app && \
  docker compose exec app /app/bin/migrate
```

- `DOCKER_BUILDKIT=1` — BuildKit cache mount 활성 (deps.get / mix archive 재사용, 빌드 빠름)
- `--no-deps app` — mysql/mongo 는 그대로 두고 app 만 재시작 (DB 안 끊김)
- `migrate` — 새 마이그레이션 있으면 적용. 없어도 안전 (`Migrations already up`)

캐시 다 날리고 풀 재빌드:

```bash
DOCKER_BUILDKIT=1 docker compose build --no-cache app && docker compose up -d --no-deps app
```

확인:

```bash
docker compose ps                       # 헬스 상태
docker compose logs app --tail=20       # 부팅 로그
curl -sS -o /dev/null -w "%{http_code}\n" http://localhost:4747/   # 200 이면 OK
```

### 상태 / 로그

```bash
docker compose ps                 # 실행 중인 서비스 + 헬스 상태
docker compose logs -f            # 모든 로그 실시간
docker compose logs -f app        # app 로그만
docker compose logs --tail=100 app
docker compose top                # 컨테이너별 프로세스
docker stats                      # CPU / 메모리 실시간
```

### 컨테이너 진입

```bash
docker compose exec app sh        # app 컨테이너 셸
docker compose exec app /app/bin/happy_trizn remote   # IEx remote console (release)
docker compose exec mysql mysql -uroot -p             # MySQL 클라이언트
docker compose exec mongo mongosh                     # Mongo 클라이언트
```

### 마이그레이션 / Eval

```bash
docker compose exec app /app/bin/migrate              # 마이그레이션 실행
docker compose exec app /app/bin/happy_trizn eval "HappyTrizn.Release.rollback(HappyTrizn.Repo, 1)"
docker compose exec app /app/bin/happy_trizn eval "HappyTrizn.Accounts.list_users() |> length()"
```

### 코드 변경 시 흐름

```bash
# 1. 코드 수정
# 2. 이미지 다시 빌드
docker compose build app
# 3. app 만 재시작 (DB 는 안 건드림)
docker compose up -d --no-deps app
# 4. 새 마이그레이션 있으면
docker compose exec app /app/bin/migrate
```

---

## 개발 명령 (`bin/mix` wrapper)

`bin/mix` 는 Elixir Docker 컨테이너 안에서 mix 명령 실행. 호스트 Elixir 불필요.
hex/mix 캐시는 Docker named volume (`happy_trizn_hex_cache`, `happy_trizn_mix_cache`)
에 영구 저장 — 매번 다시 받지 않음.

```bash
bin/mix deps.get                  # 의존성 설치
bin/mix deps.update --all         # 의존성 업그레이드
bin/mix compile                   # 컴파일
bin/mix compile --warnings-as-errors --force
MIX_ENV=test bin/mix test         # 전체 테스트 (105 tests, mysql/mongo 컨테이너 떠있어야)
MIX_ENV=test bin/mix test test/happy_trizn/accounts_test.exs:42   # 특정 줄
bin/mix format                    # 코드 포맷
bin/mix phx.gen.secret            # 64 char 시크릿
bin/mix phx.gen.secret 32         # 32 char
bin/mix ecto.gen.migration <name> # 새 마이그레이션
bin/mix ecto.create               # DB 생성 (호스트 직접 실행 시)
bin/mix ecto.migrate              # 마이그레이션 (호스트 직접 실행 시)
bin/mix ecto.rollback             # 롤백
bin/mix ecto.reset                # drop + create + migrate + seed
bin/mix run priv/repo/seeds.exs   # 시드 실행
bin/mix phx.routes                # 라우트 목록
bin/mix help                      # mix 명령 전체
```

`MIX_ENV=test` 등 prefix 가능: `MIX_ENV=test bin/mix test`.

---

## DB 접속

### 컨테이너 안에서 (호스트 노출 X 일 때)

```bash
# MySQL
docker compose exec mysql mysql -uroot -p"$MYSQL_ROOT_PASSWORD" happy_trizn

# MongoDB
docker compose exec mongo mongosh --port 37017 happy_trizn
```

### 호스트에서 직접 (개발 디버깅 — `docker-compose.override.yml` 필요)

```yaml
# docker-compose.override.yml (gitignored)
services:
  mysql:
    ports: ["47306:4406"]   # 호스트:컨테이너
  mongo:
    ports: ["47017:37017"]
```

```bash
docker compose up -d
mysql -h 127.0.0.1 -P 47306 -uroot -p
mongosh --host 127.0.0.1 --port 47017
```

---

## 백업 / 복원

### MySQL

```bash
# 백업
docker compose exec mysql mysqldump -uroot -p"$MYSQL_ROOT_PASSWORD" --single-transaction --routines happy_trizn > backup-$(date +%Y%m%d).sql

# 복원
docker compose exec -T mysql mysql -uroot -p"$MYSQL_ROOT_PASSWORD" happy_trizn < backup-20260426.sql
```

### MongoDB

```bash
# 백업 (호스트 디렉토리로 dump)
docker compose exec mongo mongodump --port 37017 --db happy_trizn --out /tmp/backup
docker cp happy_trizn_mongo:/tmp/backup ./mongo-backup-$(date +%Y%m%d)

# 복원
docker cp ./mongo-backup-20260426 happy_trizn_mongo:/tmp/restore
docker compose exec mongo mongorestore --port 37017 --drop /tmp/restore
```

### Volume 통째로 (전체)

```bash
# 백업
docker run --rm -v happy_trizn_mysql_data:/data -v "$PWD:/backup" alpine \
  tar czf /backup/mysql-volume-$(date +%Y%m%d).tar.gz -C /data .
docker run --rm -v happy_trizn_mongo_data:/data -v "$PWD:/backup" alpine \
  tar czf /backup/mongo-volume-$(date +%Y%m%d).tar.gz -C /data .

# 복원 (컨테이너 stop 후)
docker compose stop
docker run --rm -v happy_trizn_mysql_data:/data -v "$PWD:/backup" alpine \
  sh -c "rm -rf /data/* && tar xzf /backup/mysql-volume-20260426.tar.gz -C /data"
docker compose start
```

---

## 데이터 리셋

```bash
# DB 만 초기화 (compose down -v 후 다시 부팅 + migrate)
docker compose down -v
docker compose up -d
docker compose exec app /app/bin/migrate

# Hex / mix 캐시 도 같이 (clean slate)
docker volume rm happy_trizn_hex_cache happy_trizn_mix_cache
```

---

## 시크릿 재생성

```bash
# Phoenix 시크릿 (32+ chars)
bin/mix phx.gen.secret           # SECRET_KEY_BASE (64)
bin/mix phx.gen.secret 32        # ADMIN_SESSION_SECRET, LIVE_VIEW_SIGNING_SALT (32 이상 강제)

# 호스트 openssl 로 직접 (빠름)
openssl rand -base64 48 | tr -d '\n=+/' | head -c 64    # SECRET_KEY_BASE
openssl rand -base64 24 | tr -d '\n=+/' | head -c 32    # SALT

# Bcrypt admin 비번 해시
docker run --rm \
  -v happy_trizn_hex_cache:/root/.hex \
  -v happy_trizn_mix_cache:/root/.mix \
  -v "$PWD:/app" -w /app \
  elixir:1.16-alpine \
  sh -c 'mix run --no-start -e "IO.puts(Bcrypt.hash_pwd_salt(\"새비번\"))"'
```

`.env` 수정 후 `docker compose restart app` 으로 적용.

---

## 포트 / 네트워크

호스트 노출 포트는 `47xxx` prefix 로 통일 (다른 프로젝트 충돌 회피).

| 서비스 | 호스트 | 컨테이너 내부 | `.env` 변수 |
|---|---|---|---|
| Phoenix | 4747 | 4000 | `PHX_PORT_HOST` / `PORT` |
| MySQL (운영) | 노출 X | 4406 | `MYSQL_PORT` |
| MongoDB (운영) | 노출 X | 37017 | `MONGO_PORT` |
| MySQL (dev override) | 47306 | 4406 | (override.yml) |
| MongoDB (dev override) | 47017 | 37017 | (override.yml) |

`.env` 한 곳만 바꾸면 docker-compose 가 `${VAR:-기본값}` 으로 추종.

Docker 네트워크: `happy_trizn_net`. 볼륨: `happy_trizn_mysql_data`, `happy_trizn_mongo_data`.

`docker-compose.override.yml` 은 gitignored — 로컬 dev 시 DB 호스트 노출용.

---

## UFW (사내망만 허용)

```bash
sudo ufw status
sudo ufw allow from 10.0.0.0/24 to any port 4747 proto tcp   # 사내 서브넷
sudo ufw deny 4747                                            # 외부 거부
sudo ufw enable
```

`<사내_서브넷>` 은 `ip addr` 또는 IT 팀에 문의.

---

## 트러블슈팅

### `Cannot connect to the Docker daemon`
Docker Desktop 실행 안 됨. `open -a Docker` (macOS) 또는 `sudo systemctl start docker` (Linux).

### `Hex registry timeout` 또는 `:timeout` 반복
`bin/mix` wrapper 가 named volume 으로 hex 캐시 보존. 한 번 성공하면 다음 부터 빠름. 안 되면:
```bash
docker volume rm happy_trizn_hex_cache happy_trizn_mix_cache
bin/mix deps.get
```

### Phoenix 5xx 에러 / `secret_key_base` 누락
`.env` 의 `SECRET_KEY_BASE` 가 비었거나 32자 미만. 시크릿 재생성 섹션 참고.

### `mix: command not found` 또는 `the input device is not a TTY`
`bin/mix` 가 자동 감지. 그래도 실패하면 직접:
```bash
docker run --rm -v "$PWD:/app" -w /app elixir:1.16-alpine mix <command>
```

### MySQL `caching_sha2_password` 인증 실패
구 클라이언트 호환성. `docker-compose.yml` 에 이미 `--default-authentication-plugin=caching_sha2_password` 있음. 그래도 안 되면 client 측 옵션 확인.

### MongoDB 연결 실패 / chat 메시지 사라짐
Mongo 컨테이너 헬스체크 시간 (`start_period: 20s`) 동안 app 시작. `docker compose logs mongo` 로 확인. `Chat.log_message/2` 는 best-effort 라 Mongo 다운 시 broadcast 만 진행 (메시지는 RAM 에서만 살아남음).

### 포트 충돌 (`bind: address already in use`)
다른 프로세스가 4747/47306/47017 사용 중. `sudo ss -tlnp | grep 4747` 로 확인 후 `.env` 의 `MYSQL_PORT` 또는 `docker-compose.yml` 의 `4747:4000` 부분 변경.

### 컨테이너 헬스체크 fail 반복
```bash
docker compose ps                    # 헬스 상태
docker compose logs mysql --tail=50  # 무엇이 fail
docker compose down -v && docker compose up -d   # 데이터 리셋 후 재시도
```

### admin 로그인 안 됨
`.env` 의 `ADMIN_ID` 와 `ADMIN_PASSWORD_HASH` 일치 확인. 평문 비번 잊었으면 시크릿 재생성으로 새 hash 만들어 .env 갈아치우기 + `docker compose restart app`.

---

## 브랜치 / Sprint 진행

- `main` — 안정 버전
- 현재: `feat/sprint-3d-skribbl` — 캐치마인드 + UX 개선 (PR #11)

### Sprint 진행 상황 (430 tests pass)

- [x] **Sprint 1**: 기반 (scaffold, docker, 게스트, 회원가입, 로그인, 채팅, admin)
- [x] **Sprint 2**: 친구/로비 (친구목록, 방 시스템, GameBehaviour)
- [x] **Sprint 3a**: 게임 모듈 인터페이스 + GameSession + 2048/Minesweeper 싱글
- [x] **Sprint 3b**: Tetris 풀 구현
  - [x] 3b-3: SRS / wall kick / hold / 180 / combo / B2B / T-spin / DAS-ARR
  - [x] 3b-4: lock delay / 통계 / match_results / ghost / settings / 솔로 연습 / 카운트다운
  - [x] 3b-5: 사운드 (8 효과음) / 매치 히스토리 / 개인 기록 / 리더보드 / freeze fix
- [x] **Sprint 3d**: 캐치마인드 (그림 맞추기) — canvas / 5 라운드 / 한국어 150+ 단어 / 점수
- [x] 글로벌 top nav (Happy Trizn 브랜드 + 페이지 타이틀)
- [x] 게임 끝/round_end popup 모달 (Tetris + 캐치마인드)
- [x] Tetris leave 시 :practice 자동 전환 (1명 남으면 게임 영향 X)
- [ ] **Sprint 3e**: Bomberman 풀 구현 (4인 60fps tick + 폭탄 chain)
- [ ] **Sprint 3f**: Snake.io 풀 구현 (자유 입퇴장, 무한 맵)
- [ ] **Sprint 3g**: Pac-Man 풀 구현 (싱글 ghost AI)
- [ ] **Sprint 3h**: 2048 / Minesweeper 옵션 로직 보강 (board 사이즈 / 난이도)
- [ ] **Sprint 3i**: Tetris Finesse 분석 (현재 stub)
- [ ] **Sprint 3j**: JS Tetris canvas + skin
- [ ] **Sprint 3k**: 모바일 반응형
- [ ] **Sprint 4**: DM Channel + 알림 + Broadway Mongo 큐 (game_events)

자세한 게임별 진행 = [GAMES_SPEC.md](GAMES_SPEC.md), 테스트 = [TEST_PLAN.md](TEST_PLAN.md).
