# PhantomExpose — Resume-Ready Project Description

## Short version (for a resume bullet list)

**PhantomExpose — Smart Electricity Theft Detection System** (Spring Boot, React, Kafka, PostgreSQL, Docker)
- Designed and built a 7-service microservice platform (API Gateway, Auth, Consumer, Meter Reading, Detection, Notification, Analytics) using Spring Boot 3 / Java 21, Spring Cloud Gateway, and OpenFeign, with JWT-based role authentication for four user types (Admin, Utility Officer, Field Inspector, Consumer).
- Implemented a rule-based theft detection engine combining six independent heuristics (sudden consumption drop, neighborhood deviation, transformer energy mismatch, flat/stuck meter readings, abnormal usage variance, and meter reset detection) into a weighted 0–100 risk score, driven in near real time by Kafka events from the meter reading pipeline.
- Built an event-driven alerting pipeline (Kafka producer/consumer chain across services) that automatically raises, assigns, and tracks investigation cases for medium-to-critical risk consumers, with email notifications via Spring Mail.
- Delivered a React + Material UI dashboard with live risk breakdowns, region-wise theft probability heatmaps, and monthly consumption trend charts (Recharts), styled with a custom light theme.
- Containerized the full stack (7 backend services + frontend + Postgres + Redis + Kafka) with Docker Compose for one-command local deployment, and documented a Kubernetes production rollout path with database-per-service isolation, Redis-backed API rate limiting, and Actuator-based health/metrics endpoints.

## Longer version (for a portfolio page or cover letter)

PhantomExpose is a full-stack, microservice-based platform I designed to simulate how a utility company could detect electricity theft and non-technical losses at scale. Rather than relying on manual audits, the system continuously ingests meter readings — including a scheduled smart-meter simulator for demo data — and runs them through a pluggable rule engine that scores every consumer's theft risk from six independent signals: sudden consumption drops, deviation from neighborhood peers on the same transformer, transformer-level energy-loss mismatches, meters that stop changing for weeks, statistically erratic usage, and outright meter resets.

The architecture follows a database-per-service microservices pattern: an Auth service issues JWTs consumed by a Spring Cloud Gateway that fronts six backend services, each independently deployable and independently scalable. Meter readings flow through Kafka into the Detection service, which evaluates risk and — for medium-risk-and-above consumers — automatically raises an alert that's routed through Kafka again to a Notification service for email delivery, closing the loop from raw reading to inspector task without any manual polling. An Analytics service aggregates results into a dashboard-ready summary, cached in Redis for fast repeated reads.

On the frontend, I built a role-aware React SPA with Material UI, using a light, minimalist design system (soft blues, rounded cards, no dark themes) so utility officers and field inspectors can triage alerts quickly: assigning inspectors, tracking investigation status through to a confirmed-theft or false-positive close, and viewing region-wise theft-probability heatmaps and consumption trend charts.

The whole system — seven Spring Boot services, a React frontend, PostgreSQL, Redis, and Kafka/Zookeeper — runs with a single `docker compose up`, and I documented a path to a production Kubernetes deployment with Flyway-managed migrations, externalized secrets, Prometheus/Grafana observability, and horizontal autoscaling on the highest-throughput services.

## Key technical talking points for interviews

- **Why rules instead of ML first**: a transparent, explainable rule engine (with per-rule reason strings surfaced all the way to the alert) is easier for utility inspectors to trust and act on than an opaque model score — and it establishes labeled ground truth (confirmed theft vs. false positive) that a future ML model could be trained on.
- **Why Kafka between reading ingestion and detection**: decouples the write-heavy meter-reading path from the compute-heavier detection path, and lets the notification service fan out independently without either producer blocking on it.
- **Trade-off made explicit**: the analytics-service reads directly from the detection database rather than calling detection-service's REST API for every dashboard load — a deliberate CQRS-style read-model shortcut favoring dashboard latency over strict service encapsulation, documented as such rather than hidden.
