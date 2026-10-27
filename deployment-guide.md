# PhantomExpose — Deployment Guide

## 1. Prerequisites

- Docker & Docker Compose v2
- JDK 21 + Maven 3.9+ (only needed for local, non-container builds)
- Node.js 20+ (only needed for local, non-container frontend dev)
- Ports free on the host: `3000, 5432, 6379, 8080-8086, 9092, 2181`

## 2. Local run — full stack via Docker Compose

```bash
cd phantomexpose
docker compose build          # builds all 7 services + frontend images
docker compose up -d          # starts Postgres, Redis, Kafka/Zookeeper, all services, frontend
docker compose ps             # confirm everything is healthy
```

- Frontend: http://localhost:3000
- API Gateway (single entry point for the SPA and Postman): http://localhost:8080
- Individual services are also directly reachable on 8081–8086 for debugging, but should not be called directly in production — always go through the gateway so JWT validation and rate limiting apply.

Postgres auto-creates the five per-service databases on first boot via `db/init-db.sql` mounted into `/docker-entrypoint-initdb.d`. Hibernate's `ddl-auto: update` then creates/updates tables on each service's first startup — acceptable for dev/demo; **for production, replace this with versioned Flyway/Liquibase migrations** generated from `docs/schema.sql`.

To tear down:
```bash
docker compose down          # stop containers, keep volumes (data persists)
docker compose down -v       # stop and wipe the Postgres volume too
```

## 3. Local development (running services outside Docker)

Useful when iterating on one service while the rest of the stack runs in Docker:

```bash
docker compose up -d postgres redis kafka zookeeper
cd services/detection-service
mvn spring-boot:run \
  -Dspring-boot.run.arguments="--DB_HOST=localhost --KAFKA_BROKER=localhost:29092"
```

Frontend:
```bash
cd frontend
npm install
VITE_API_BASE_URL=http://localhost:8080 npm run dev
```

## 4. Environment configuration

All secrets/config are externalized via environment variables (see each service's `application.yml`). Minimum you should override for anything beyond a laptop demo:

| Variable | Used by | Purpose |
|---|---|---|
| `JWT_SECRET` | api-gateway, auth-service | HMAC signing key — must match across both, ≥256-bit random value |
| `DB_USER` / `DB_PASSWORD` | all data services | Postgres credentials |
| `SMTP_HOST/PORT/USER/PASSWORD` | notification-service | Outbound email |
| `KAFKA_BROKER` | meter-reading, detection, notification | Kafka bootstrap servers |
| `REDIS_HOST` | consumer, analytics, api-gateway | Cache/rate-limiter backend |

In production, source these from a secrets manager (AWS Secrets Manager, HashiCorp Vault, or Kubernetes Secrets) — never bake them into images or commit them to source control.

## 5. Production deployment path (Kubernetes)

The Docker images built by each service's `Dockerfile` are directly deployable to Kubernetes:

1. Push images to a registry: `docker tag detection-service:latest <registry>/phantomexpose/detection-service:1.0.0 && docker push ...` (repeat per service).
2. Provision managed Postgres (RDS/Cloud SQL), managed Redis (ElastiCache/MemoryStore), and a Kafka cluster (MSK/Confluent Cloud) instead of the compose containers.
3. Create a Kubernetes `Deployment` + `Service` per microservice, mirroring the `docker-compose.yml` environment variables via `ConfigMap`/`Secret`.
4. Expose only `api-gateway` externally (Ingress/LoadBalancer); keep the other six services as internal `ClusterIP` services, matching the "only the gateway is public" rule from step 2.
5. Configure `HorizontalPodAutoscaler` on `meter-reading-service` and `detection-service` — they see the highest event throughput.
6. Add liveness/readiness probes against each service's `/actuator/health` (already exposed via `spring-boot-starter-actuator`).
7. Swap Hibernate `ddl-auto: update` for a Flyway migration job run as a Kubernetes `Job` before each rollout.

## 6. Observability

- **Logs**: ship container stdout/stderr to a centralized log store (ELK/Loki); every service already logs via SLF4J.
- **Metrics**: Actuator + Micrometer → Prometheus; each service's `/actuator/prometheus` endpoint can be scraped once `micrometer-registry-prometheus` is added.
- **Tracing**: add Spring Cloud Sleuth/Micrometer Tracing + Zipkin/Jaeger to trace a reading through meter-reading → Kafka → detection → notification, which is where distributed-tracing value is highest in this system.
- **Alerting**: hook Prometheus alert rules to the same `alerts` domain concept in reverse — e.g., alert on-call if `detection-service` Kafka consumer lag exceeds a threshold.

## 7. Rollback strategy

- Each service is versioned and deployed independently (true microservice deploys) — a bad `detection-service` release can be rolled back without touching `consumer-service` or the frontend.
- Database migrations (once on Flyway) should be additive/backward-compatible per release so a service rollback doesn't require a matching schema rollback.

## 8. Security hardening checklist before go-live

- [ ] Replace default JWT secret and all default passwords in `docker-compose.yml`
- [ ] Enforce HTTPS/TLS termination at the ingress/load balancer
- [ ] Move `RequestRateLimiter` config on the gateway from defaults to values tuned for expected load
- [ ] Enable audit logging (`audit_log` table in `phantomexpose_auth`) on all sensitive mutations
- [ ] Rotate SMTP and DB credentials via secrets manager, not `.env` files
- [ ] Run `mvn dependency-check:check` / `npm audit` in CI to catch vulnerable dependencies
