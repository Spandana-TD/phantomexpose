-- =====================================================================
-- PhantomExpose - Database Schema
-- Each microservice owns its own database (database-per-service pattern).
-- Databases: phantomexpose_auth, phantomexpose_consumer, phantomexpose_meter,
--            phantomexpose_detection, phantomexpose_notification
-- Create databases first (see docker-compose init script: db/init-db.sql)
-- =====================================================================

-- =====================================================================
-- DATABASE: phantomexpose_auth
-- =====================================================================
CREATE TABLE users (
    id              BIGSERIAL PRIMARY KEY,
    full_name       VARCHAR(150) NOT NULL,
    email           VARCHAR(150) NOT NULL UNIQUE,
    password        VARCHAR(255) NOT NULL,
    consumer_number VARCHAR(50) UNIQUE,               -- populated only for CONSUMER role
    role            VARCHAR(30) NOT NULL CHECK (role IN ('ADMIN','UTILITY_OFFICER','FIELD_INSPECTOR','CONSUMER')),
    enabled         BOOLEAN NOT NULL DEFAULT TRUE,
    account_locked  BOOLEAN NOT NULL DEFAULT FALSE,
    created_at      TIMESTAMP NOT NULL DEFAULT now(),
    last_login      TIMESTAMP
);
CREATE INDEX idx_users_role ON users(role);

CREATE TABLE audit_log (
    id          BIGSERIAL PRIMARY KEY,
    user_id     BIGINT REFERENCES users(id),
    action      VARCHAR(100) NOT NULL,
    entity_type VARCHAR(100),
    entity_id   VARCHAR(100),
    ip_address  VARCHAR(45),
    metadata    JSONB,
    created_at  TIMESTAMP NOT NULL DEFAULT now()
);
CREATE INDEX idx_audit_user ON audit_log(user_id);
CREATE INDEX idx_audit_created ON audit_log(created_at);

-- =====================================================================
-- DATABASE: phantomexpose_consumer
-- =====================================================================
CREATE TABLE transformers (
    id                        BIGSERIAL PRIMARY KEY,
    transformer_code          VARCHAR(50) NOT NULL UNIQUE,
    distribution_area         VARCHAR(150),
    region                    VARCHAR(100),
    capacity_kva              DOUBLE PRECISION,
    total_supplied_energy_kwh DOUBLE PRECISION NOT NULL DEFAULT 0,
    latitude                  DOUBLE PRECISION,
    longitude                 DOUBLE PRECISION,
    created_at                TIMESTAMP NOT NULL DEFAULT now()
);
CREATE INDEX idx_transformer_region ON transformers(region);

CREATE TABLE consumers (
    id               BIGSERIAL PRIMARY KEY,
    consumer_number  VARCHAR(50) NOT NULL UNIQUE,
    full_name        VARCHAR(150) NOT NULL,
    email            VARCHAR(150),
    phone            VARCHAR(20),
    address          VARCHAR(255),
    region           VARCHAR(100),
    consumer_type    VARCHAR(30) CHECK (consumer_type IN ('RESIDENTIAL','COMMERCIAL','INDUSTRIAL','AGRICULTURAL')),
    transformer_id   BIGINT REFERENCES transformers(id),
    active           BOOLEAN NOT NULL DEFAULT TRUE,
    created_at       TIMESTAMP NOT NULL DEFAULT now()
);
CREATE INDEX idx_consumer_transformer ON consumers(transformer_id);
CREATE INDEX idx_consumer_region ON consumers(region);
CREATE INDEX idx_consumer_number ON consumers(consumer_number);

CREATE TABLE meters (
    id               BIGSERIAL PRIMARY KEY,
    meter_number     VARCHAR(50) NOT NULL UNIQUE,
    meter_type       VARCHAR(30),                 -- SMART, ELECTROMECHANICAL, STATIC
    initial_reading  DOUBLE PRECISION DEFAULT 0,
    consumer_id      BIGINT UNIQUE REFERENCES consumers(id),
    active           BOOLEAN NOT NULL DEFAULT TRUE,
    installed_at     TIMESTAMP NOT NULL DEFAULT now()
);

-- =====================================================================
-- DATABASE: phantomexpose_meter
-- =====================================================================
CREATE TABLE meter_readings (
    id                 BIGSERIAL PRIMARY KEY,
    meter_number       VARCHAR(50) NOT NULL,
    consumer_id        BIGINT NOT NULL,
    transformer_id     BIGINT,
    reading_date       DATE NOT NULL,
    reading_type       VARCHAR(20) CHECK (reading_type IN ('DAILY','MONTHLY','SMART_INTERVAL')),
    reading_value_kwh  DOUBLE PRECISION NOT NULL,
    consumption_kwh    DOUBLE PRECISION,
    estimated          BOOLEAN NOT NULL DEFAULT FALSE,
    created_at         TIMESTAMP NOT NULL DEFAULT now()
);
-- Indexing strategy: composite index for the most common query pattern
-- (history lookup for a meter ordered by date), plus a consumer index
-- since the detection engine queries by consumer_id frequently.
CREATE INDEX idx_meter_reading_meter_date ON meter_readings(meter_number, reading_date DESC);
CREATE INDEX idx_meter_reading_consumer ON meter_readings(consumer_id, reading_date DESC);
CREATE INDEX idx_meter_reading_transformer_date ON meter_readings(transformer_id, reading_date);

-- =====================================================================
-- DATABASE: phantomexpose_detection
-- =====================================================================
CREATE TABLE detection_results (
    id             BIGSERIAL PRIMARY KEY,
    consumer_id    BIGINT NOT NULL,
    transformer_id BIGINT,
    risk_score     INTEGER NOT NULL CHECK (risk_score BETWEEN 0 AND 100),
    risk_category  VARCHAR(20) CHECK (risk_category IN ('LOW','MEDIUM','HIGH','CRITICAL')),
    reasons        VARCHAR(2000),
    evaluated_at   TIMESTAMP NOT NULL DEFAULT now()
);
CREATE INDEX idx_detection_consumer ON detection_results(consumer_id, evaluated_at DESC);
CREATE INDEX idx_detection_risk_category ON detection_results(risk_category);

CREATE TABLE alerts (
    id                     BIGSERIAL PRIMARY KEY,
    consumer_id            BIGINT NOT NULL,
    transformer_id         BIGINT,
    detection_result_id    BIGINT NOT NULL REFERENCES detection_results(id),
    risk_category          VARCHAR(20),
    reasons                VARCHAR(2000),
    status                 VARCHAR(30) NOT NULL DEFAULT 'OPEN'
                             CHECK (status IN ('OPEN','ASSIGNED','UNDER_INVESTIGATION','ESCALATED',
                                                'CLOSED_CONFIRMED_THEFT','CLOSED_FALSE_POSITIVE')),
    assigned_inspector_id  BIGINT,
    investigation_notes    VARCHAR(2000),
    created_at             TIMESTAMP NOT NULL DEFAULT now(),
    updated_at             TIMESTAMP NOT NULL DEFAULT now(),
    closed_at              TIMESTAMP
);
CREATE INDEX idx_alert_status ON alerts(status);
CREATE INDEX idx_alert_inspector ON alerts(assigned_inspector_id);
CREATE INDEX idx_alert_consumer ON alerts(consumer_id);

-- =====================================================================
-- DATABASE: phantomexpose_notification
-- =====================================================================
CREATE TABLE notifications (
    id           BIGSERIAL PRIMARY KEY,
    consumer_id  BIGINT,
    alert_id     BIGINT,
    type         VARCHAR(30),          -- ALERT, INSPECTION_REMINDER, GENERAL
    channel      VARCHAR(20),          -- EMAIL, SMS
    recipient    VARCHAR(150),
    subject      VARCHAR(255),
    message      VARCHAR(2000),
    sent         BOOLEAN NOT NULL DEFAULT FALSE,
    created_at   TIMESTAMP NOT NULL DEFAULT now()
);
CREATE INDEX idx_notification_alert ON notifications(alert_id);

-- =====================================================================
-- ER RELATIONSHIP SUMMARY (see docs/ER-diagram.md for the visual diagram)
-- =====================================================================
-- users (auth)              1---1  consumers (via consumer_number, cross-service by convention)
-- transformers               1---N  consumers
-- consumers                  1---1  meters
-- consumers/meters           1---N  meter_readings
-- consumers                  1---N  detection_results
-- detection_results          1---1  alerts (an alert is raised from one evaluation)
-- alerts                     1---N  notifications
