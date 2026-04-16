# NestJS Service Scaffold — Arcanada Ecosystem

Checklist for Phase 1 (scaffold) of any new NestJS backend service.

## 1. Init

```bash
mkdir -p Projects/<Name>/code/<service>
cd Projects/<Name>/code/<service>
```

## 2. package.json

Key dependencies (versions as of 2026-04):

**Runtime:** `@nestjs/common`, `@nestjs/core`, `@nestjs/platform-express`, `@nestjs/config`, `@nestjs/schedule`, `@prisma/client`, `bcryptjs`, `bullmq`, `ioredis`, `pino`, `pino-http`, `prom-client`, `rate-limiter-flexible`, `reflect-metadata`, `rxjs`, `zod`

**Dev:** `@nestjs/cli`, `@nestjs/schematics`, `@nestjs/testing`, `@types/bcryptjs`, `@types/express`, `@types/node`, `@typescript-eslint/*`, `eslint` (v9 flat config), `prettier`, `prisma`, `rimraf`, `vitest`, `@vitest/coverage-v8`, `typescript` (5.5+)

**Scripts:** `build`, `start:dev`, `start:prod`, `lint`, `test`, `test:cov`, `prisma:generate`, `prisma:migrate:dev`, `prisma:migrate:deploy`

**Note:** Use `bcryptjs` (not `bcrypt`) — pure JS, no native deps, Node 22+ compatible.

## 3. Config

- `tsconfig.json` — target ES2022, strict null checks, decorators, paths `@/* → src/*`
- `tsconfig.build.json` — extends tsconfig, excludes test/dist
- `nest-cli.json` — sourceRoot: src, deleteOutDir: true
- `eslint.config.mjs` — ESLint 9 flat config, typescript-eslint + prettier
- `.prettierrc` — singleQuote, trailingComma all, printWidth 100
- `vitest.config.ts` — resolve alias `@` → src, node environment

## 4. Prisma

- `prisma/schema.prisma` — datasource postgresql, generator prisma-client-js
- Tables per service design; use `@@map("snake_case")` for table names, `@map("snake_case")` for columns
- BigInt for Telegram user IDs
- `@default(cuid())` for string PKs, `@default(autoincrement())` for audit log
- Indices on frequently queried fields

## 5. Core Modules

- `src/config/env.schema.ts` — Zod schema for all env vars, fail-fast at boot
- `src/config/config.module.ts` — global, wraps NestConfigModule with Zod validate
- `src/prisma/prisma.service.ts` — extends PrismaClient, OnModuleInit/Destroy, `ping()` method
- `src/prisma/prisma.module.ts` — global
- `src/redis/redis.service.ts` — ioredis wrapper, namespaced keys, `ping()`
- `src/redis/redis.module.ts` — global

## 6. Health

- `GET /health` — liveness (always 200 if process alive)
- `GET /health/ready` — readiness (checks DB + Redis)

## 7. Docker

- `Dockerfile` — multi-stage (builder → runtime), non-root `nodejs:1001`, tini entrypoint, curl healthcheck
- `docker/entrypoint.sh` — `prisma migrate deploy` → `exec "$@"`
- `docker-compose.yml` — dev: Postgres 16 + Redis 7 (local)
- `docker-compose.prod.yml` — external DB + Redis, image from registry
- `.dockerignore` — node_modules, dist, .git, .env, test, coverage

## 8. Other Files

- `.env.example` — all env vars with placeholder values
- `.gitignore` — node_modules, dist, .env, coverage, IDE
- `.gitleaks.toml` — allowlist for .env.example, k6, README, deploy/
- `README.md` — quickstart, directory layout, roadmap, security notes

## 9. Verification

```bash
pnpm install
pnpm prisma:generate
pnpm build         # zero errors
pnpm lint          # zero errors/warnings
pnpm test          # all passing (env + health tests minimum)
docker compose up -d && pnpm prisma:migrate:dev --name init  # tables created
docker compose down
```

## Reference

Created from AGENT-0011 (Ops Bot Phase 1) scaffold pattern.
