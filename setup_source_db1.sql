CREATE TABLE users (
  id BIGSERIAL PRIMARY KEY,
  full_name VARCHAR
);
-- NOTE: REPLICA IDENDITY needs to be set to FULL
-- https://ci.apache.org/projects/flink/flink-docs-stable/dev/table/connectors/formats/debezium.html#consuming-data-
-- https://debezium.io/documentation/reference/1.2/connectors/postgresql.html#postgresql-replica-identity
ALTER TABLE users REPLICA IDENTITY FULL;
