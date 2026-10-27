# PhantomExpose — Smart Electricity Theft Detection System

A production-style microservices platform that detects consumers likely to be under-reporting usage, bypassing meters, or tampering with electricity records — built with Spring Boot 3 / Java 21, React + Material UI, Kafka, PostgreSQL, Redis, and Docker.

## 1. Folder structure

```
phantomexpose/
├── docker-compose.yml              # orchestrates postgres, redis, kafka, all 7 services, frontend
├── db/
│   └── init-db.sql                 # creates one database per microservice on first boot
├── docs/
│   ├── schema.sql                  # full DDL, all tables, indexes
│   ├── ER-diagram.md               # mermaid ER diagram + design notes
│   ├── API.md                      # REST endpoints, request/response examples, error handling
│   ├── testing-strategy.md         # unit/integration/E2E/perf test plan
│   ├── deployment-guide.md         # local, k8s, observability, security checklist
│   └── resume.md                   # resume-ready project description
├── services/
│   ├── api-gateway/                # Spring Cloud Gateway, JWT validation, rate limiting, routing
│   ├── auth-service/               # registration, login, JWT issuing, role-based users
│   ├── consumer-service/           # consumers, meters, transformers, Redis caching
│   ├── meter-reading-service/      # daily/monthly readings, bulk CSV upload, smart-meter simulator
│   ├── detection-service/          # theft detection rule engine, risk scoring, alerts
│   ├── notification-service/       # Kafka-driven email notifications
│   └── analytics-service/          # dashboard aggregation, region heatmap
└── frontend/
    ├── src/
    │   ├── api/client.js           # axios instance with JWT interceptor
    │   ├── context/AuthContext.jsx # login/register/logout state
    │   ├── theme/theme.js          # MUI theme (light palette per spec)
    │   ├── components/             # DashboardLayout, StatCard, ProtectedRoute
    │   └── pages/                  # Login, Register, Dashboard, Consumers, MeterReadings, Alerts, Analytics
    └── Dockerfile                  # multi-stage build -> nginx
```

Each service under `services/` is a **fully independent Maven project** (own `pom.xml`, own `Dockerfile`, own `application.yml`, own database) — this is a true microservices layout, not a monolith split by package.

## 2. Technology stack recap

| Layer | Choice |
|---|---|
| Language/runtime | Java 21, Spring Boot 3.3 |
| Security | Spring Security + JWT (jjwt), BCrypt password hashing |
| Persistence | Spring Data JPA / Hibernate, PostgreSQL (database-per-service) |
| Caching | Redis (consumer lookups, analytics dashboard, gateway rate limiting) |
| Messaging | Apache Kafka (reading → detection → alert → notification pipeline) |
| Inter-service calls | OpenFeign (detection → consumer/meter-reading; analytics → consumer) |
| Gateway | Spring Cloud Gateway |
| Build | Maven, Lombok, MapStruct |
| Frontend | React 18, Material UI 5, Recharts, Axios, React Router |
| Deployment | Docker, Docker Compose (Kubernetes path documented) |

## 3. Step-by-step implementation plan (the order this was actually built in)

1. **Project skeleton** — created the multi-service folder layout under `services/`, one Maven module per microservice, each with its own `pom.xml` targeting Java 21 / Spring Boot 3.3.2, plus the shared `docker-compose.yml` and `db/init-db.sql` for a database-per-service Postgres instance.
2. **Auth service first** — everything else needs authenticated callers, so `User` entity, `Role` enum, BCrypt + JJWT-based `AuthService`, `/api/auth/register` and `/api/auth/login` were built and tested before any other service.
3. **Consumer domain** — `Consumer`, `Meter`, `Transformer` entities and their CRUD services/controllers, with Redis `@Cacheable` on consumer lookups since that's the highest-read entity in the system.
4. **Meter reading pipeline** — `MeterReading` entity with a composite index on `(meter_number/consumer_id, reading_date)`, a CSV bulk-upload endpoint (OpenCSV), a scheduled `SmartMeterSimulator` for demo data generation, and a Kafka producer publishing `meter-reading-created` on every write.
5. **Detection engine (the core of the system)** — six independent `DetectionRule` implementations behind a common interface, a `DetectionEngine` orchestrator that Spring auto-wires all rule beans into, weighted score aggregation into a 0–100 risk score, and a Kafka `@KafkaListener` that runs the engine automatically whenever a new reading arrives.
6. **Alerting** — `Alert` entity/state machine (`OPEN → ASSIGNED → UNDER_INVESTIGATION/ESCALATED → CLOSED_*`), auto-generated for MEDIUM-risk-and-above detection results, with a Kafka `alert-created` event fired for downstream notification.
7. **Notifications** — a Kafka consumer in `notification-service` that turns `alert-created` events into emails (Spring Mail) and persists a `Notification` audit row regardless of send success.
8. **Analytics** — read-model repositories mapped onto the detection database for cheap aggregate queries (risk breakdown, alert status counts, region-wise theft-probability heatmap), Redis-cached for dashboard performance.
9. **API Gateway** — Spring Cloud Gateway routes for all six downstream services, a custom `GlobalFilter` that validates the JWT once at the edge and forwards user identity as headers, plus Redis-backed rate limiting.
10. **Frontend** — Vite + React + MUI SPA: theme matching the specified light palette, `AuthContext` + `ProtectedRoute`, a sidebar `DashboardLayout`, and one page per module (Dashboard with pie chart + summary cards, Consumers with a registration dialog, Meter Readings with a line chart + CSV-style manual entry, Alerts with inline status/assignment controls, Analytics with a bar chart + heatmap list).
11. **Documentation** — full DDL (`docs/schema.sql`), ER diagram, API reference, testing strategy, deployment guide, and resume write-up, so the project is demo-ready and interview-ready, not just code.
12. **Containerization** — a `Dockerfile` per service (multi-stage: Maven build → slim JRE runtime) and one for the frontend (Vite build → nginx), wired together in `docker-compose.yml` with explicit `depends_on`/health-check ordering so `docker compose up` brings up a fully working stack.

## 4. Quick start

```bash
docker compose up -d --build
```
Then open the frontend at **http://localhost:3000**, register an account (pick a role), and start registering transformers → consumers → meters → readings. See `docs/deployment-guide.md` for the full guide and `docs/API.md` for every endpoint.

## 5. Where to look for what

- Detection logic: `services/detection-service/src/main/java/com/phantomexpose/detection/rules/`
- Risk scoring orchestration: `services/detection-service/.../service/DetectionEngine.java`
- Event flow: `meter-reading-service` → Kafka `meter-reading-created` → `detection-service` → Kafka `alert-created` → `notification-service`
- Full schema: `docs/schema.sql`
- Every endpoint with example payloads: `docs/API.md`
