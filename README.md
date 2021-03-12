# experiment-flink-pulsar-debezium
An exploration of [Flink](https://flink.apache.org/) +
[Pulsar](https://pulsar.apache.org/) + [Debezium](https://debezium.io/). This
exploration primarily leverages the [Flink Table
API](https://ci.apache.org/projects/flink/flink-docs-stable/dev/table/tableApi.html)
via the [Flink SQL
Client](https://ci.apache.org/projects/flink/flink-docs-stable/dev/table/sqlClient.html).

The following tools were used in this exploration:

- [Flink Pulsar connector](https://github.com/streamnative/pulsar-flink): to
  connect Flink to Pulsar
- [Flink Debezium
  format](https://ci.apache.org/projects/flink/flink-docs-stable/dev/table/connectors/formats/debezium.html):
  to interpret the Debezium data format
- [Pulsar IO CDC Debezium source
  connector](https://pulsar.apache.org/docs/en/io-cdc-debezium/): to
  change-data-capture a changelog from a Postgres database into Pulsar
- [Flink SQL
  Client](https://ci.apache.org/projects/flink/flink-docs-stable/dev/table/sqlClient.html):
  to easily work with Flink SQL without needing to write a Flink program in
  Java/Scala
- [PostgreSQL](https://www.postgresql.org/): to play the role of a standard
  relational database. As a source or sink.

And, here's another exploration that omits messaging middleware altogether:
[experiment-flink-cdc-connectors](https://github.com/ypt/experiment-flink-cdc-connectors)

## Why?
The general theme of "I want to get state from Point-A to Point-B, maybe
transform it along the way, and continue to keep it updated, in near real-time"
is a fairly common story that can take a variety of forms.
1. data integration amongst microservices
1. analytic datastore loading and updating
1. cache maintenance
1. search index syncing

Given these use cases, some interesting questions to explore are:
1. Fundamentally, how well does a stream processing paradigm speak to these use
   cases? (I believe it does quite well.
   [[1](https://www.confluent.io/blog/using-logs-to-build-a-solid-data-infrastructure-or-why-dual-writes-are-a-bad-idea/),
   [2](https://www.confluent.io/blog/turning-the-database-inside-out-with-apache-samza/),
   [3](https://engineering.linkedin.com/distributed-systems/log-what-every-software-engineer-should-know-about-real-time-datas-unifying)])
1. How about Flink and its ecosystem?
1. From a technological lens: how's performance, scalability, and fault
   tolerence?
1. From a usability lens: what types of personas might be successful using
   various types of solutions? For example, how easy to use and powerful are
   Flink's [Table
   API](https://ci.apache.org/projects/flink/flink-docs-release-1.12/dev/table/)
   and [SQL
   Client](https://ci.apache.org/projects/flink/flink-docs-release-1.12/dev/table/sqlClient.html),
   vs its more expressive [lower level
   API's](https://ci.apache.org/projects/flink/flink-docs-release-1.12/dev/datastream_api.html).
   And what types of personas might be good fits for each?

## Hands on examples with the Flink Pulsar connector
We'll start with a system like this

![System
diagram](/docs/system-diagram-1.svg?raw=true&sanitize=true
"System diagram")

Then we'll build up a system like this - layering in CDC via Debezium.

![System
diagram](/docs/system-diagram-2.svg?raw=true&sanitize=true
"System diagram")

Build and start the system
```sh
docker-compose build
docker-compose up
```

Start Flink SQL Client
```sh
docker-compose exec flink-sql-client ./sql-client.sh
```

In the Flink SQL Client, define a [Dynamic Table](https://ci.apache.org/projects/flink/flink-docs-stable/dev/table/streaming/dynamic_tables.html).
```sql
-- Flink SQL Client

CREATE TABLE pulsartest (
  `physical_1` STRING,
  `physical_2` INT,
  `eventTime` TIMESTAMP(3) METADATA,
  `properties` MAP<STRING, STRING> METADATA ,
  `topic` STRING METADATA VIRTUAL,
  `sequenceId` BIGINT METADATA VIRTUAL,
  `key` STRING ,
  `physical_3` BOOLEAN
) WITH (
  'connector' = 'pulsar',
  'topic' = 'persistent://public/default/avrotest',
  'key.format' = 'raw',
  'key.fields' = 'key',
  'value.format' = 'avro',
  'service-url' = 'pulsar://pulsar:6650',
  'admin-url' = 'http://pulsar:8080',
  'scan.startup.mode' = 'earliest'
);

SELECT * FROM pulsartest;

INSERT INTO pulsartest
VALUES
 ('data 1', 1, TIMESTAMP '2020-03-08 13:12:11.123', MAP['k11', 'v11', 'k12', 'v12'], 'key1', TRUE),
 ('data 2', 2, TIMESTAMP '2020-03-09 13:12:11.123', MAP['k21', 'v21', 'k22', 'v22'], 'key2', FALSE),
 ('data 3', 3, TIMESTAMP '2020-03-10 13:12:11.123', MAP['k31', 'v31', 'k32', 'v32'], 'key3', TRUE);

SELECT * FROM pulsartest;
```


List Pulsar topics
```sh
docker-compose exec pulsar /pulsar/bin/pulsar-admin topics list public/default

# persistent://public/default/avrotest
```

Subscribe to the Pulsar topic
```sh
docker-compose exec pulsar /pulsar/bin/pulsar-client consume -s "mysubscription" persistent://public/default/avrotest -n 0
```

In the Flink SQL Client, insert a few more rows and observe what happens. Observe
that the data is binary. This is because the `value.format` that we used is
`avro`.

Now let's try `value.format` as `json`.
```sql
-- Flink SQL Client

CREATE TABLE pulsarjsontest (
  `physical_1` STRING,
  `physical_2` INT,
  `eventTime` TIMESTAMP(3) METADATA,
  `properties` MAP<STRING, STRING> METADATA ,
  `topic` STRING METADATA VIRTUAL,
  `sequenceId` BIGINT METADATA VIRTUAL,
  `key` STRING ,
  `physical_3` BOOLEAN
) WITH (
  'connector' = 'pulsar',
  'topic' = 'persistent://public/default/jsontest', -- NOTE
  'key.format' = 'raw',
  'key.fields' = 'key',
  'value.format' = 'json', -- NOTE
  'service-url' = 'pulsar://pulsar:6650',
  'admin-url' = 'http://pulsar:8080',
  'scan.startup.mode' = 'earliest'
);
```

Subscribe a Pulsar consumer to the new topic
```sh
docker-compose exec pulsar /pulsar/bin/pulsar-client consume -s "mysubscription" persistent://public/default/jsontest -n 0
```

Insert data
```sql
-- Flink SQL Client

INSERT INTO pulsarjsontest
VALUES
 ('data 1', 1, TIMESTAMP '2020-03-08 13:12:11.123', MAP['k11', 'v11', 'k12', 'v12'], 'key1', TRUE),
 ('data 2', 2, TIMESTAMP '2020-03-09 13:12:11.123', MAP['k21', 'v21', 'k22', 'v22'], 'key2', FALSE),
 ('data 3', 3, TIMESTAMP '2020-03-10 13:12:11.123', MAP['k31', 'v31', 'k32', 'v32'], 'key3', TRUE);
```

The Pulsar consumer output now looks like this
```
----- got message -----
key:[a2V5MQ==], properties:[k11=v11, k12=v12], content:{"physical_1":"data 1","physical_2":1,"key":"key1","physical_3":true}
----- got message -----
key:[a2V5Mg==], properties:[k21=v21, k22=v22], content:{"physical_1":"data 2","physical_2":2,"key":"key2","physical_3":false}
----- got message -----
key:[a2V5Mw==], properties:[k31=v31, k32=v32], content:{"physical_1":"data 3","physical_2":3,"key":"key3","physical_3":true}
```

We can write directly to Pulsar using other means, too. For example, using the [Pulsar client CLI](https://pulsar.apache.org/docs/en/reference-cli-tools/#pulsar-client).
```sh
# get into pulsar container shell
docker-compose exec pulsar bash

# use pulsar-client to send a message into the topic
./bin/pulsar-client produce persistent://public/default/jsontest -f <(echo '{"physical_1":"data 1","physical_2":1,"key":"key1","physical_3":true}')
```

Try a Flink query and see the new row appear
```sql
-- Flink SQL Client

SELECT * from pulsarjsontest;
```

## Upserting using the `upsert-pulsar` connector
The `pulsar` connector simply appends rows. If you'd like to have your table
update existing rows, you can leverage the
[`upsert-pulsar`](https://github.com/streamnative/pulsar-flink#upsert-pulsar)
connector.

```sql
-- Flink SQL Client

CREATE TABLE pulsarjsontestupsert (
  `physical_1` STRING,
  `physical_2` INT,
  `eventTime` TIMESTAMP(3) METADATA,
  `properties` MAP<STRING, STRING> METADATA ,
  `topic` STRING METADATA VIRTUAL,
  `sequenceId` BIGINT METADATA VIRTUAL,
  `key` STRING ,
  `physical_3` BOOLEAN,
  PRIMARY KEY (key) NOT ENFORCED -- NOTE: added this
) WITH (
  'connector' = 'upsert-pulsar', -- NOTE: this changed from pulsar to upsert-pulsar
  'topic' = 'persistent://public/default/jsontest',
  'key.format' = 'raw',
  'value.format' = 'json',
  'service-url' = 'pulsar://pulsar:6650',
  'admin-url' = 'http://pulsar:8080'
);
```

For reference, the following properties are available:

- admin-url
- connector
- key.fields-prefix
- key.format
- key.raw.charset
- key.raw.endianness
- properties
- property-version
- service-url
- sink.parallelism
- topic
- value.fields-include
- value.format
- value.json.fail-on-missing-field
- value.json.ignore-parse-errors
- value.json.map-null-key.literal
- value.json.map-null-key.mode
- value.json.timestamp-format.standard

Try a Flink SQL query with the new table
```sql
-- Flink SQL Client

SELECT * FROM pulsarjsontestupsert;
```

Insert and update via Pulsar messages
```sh
# pulsar container shell, docker-compose exec pulsar bash

# these should translate into inserts
./bin/pulsar-client produce persistent://public/default/jsontest -f <(echo '{"physical_1":"data 1","physical_2":100,"key":"key1","physical_3":false}')
./bin/pulsar-client produce persistent://public/default/jsontest -f <(echo '{"physical_1":"data 1","physical_2":100,"key":"key2","physical_3":false}')

# this should translate into an update
./bin/pulsar-client produce persistent://public/default/jsontest -f <(echo '{"physical_1":"updated","physical_2":1,"key":"key1","physical_3":true}')

# TODO: How do we delete a row? These don't seem to work. Look more into this
# ./bin/pulsar-client produce persistent://public/default/jsontest -k key2 -f <(echo)
# ./bin/pulsar-client produce persistent://public/default/jsontest -k key3 -f <(echo)
```

## Is it possible to connect to multiple Pulsar topics with the table environment?

As of `v2.7.5.2` of `pulsar-flink`, the `upsert-pulsar` connector doesn't seem
to work with multiple topics via `topic-pattern`.
```sql
-- Flink SQL Client

CREATE TABLE pulsarmultitopictest (
  `physical_1` STRING,
  `physical_2` INT,
  `eventTime` TIMESTAMP(3) METADATA,
  `properties` MAP<STRING, STRING> METADATA ,
  `topic` STRING METADATA VIRTUAL,
  `sequenceId` BIGINT METADATA VIRTUAL,
  `key` STRING ,
  `physical_3` BOOLEAN,
  PRIMARY KEY (key) NOT ENFORCED
) WITH (
  'connector' = 'upsert-pulsar', -- NOTE
  'topic-pattern' = 'persistent://public/default/multitopictest.*', -- NOTE
  'key.format' = 'raw',
  'value.format' = 'json',
  'service-url' = 'pulsar://pulsar:6650',
  'admin-url' = 'http://pulsar:8080'
);

SELECT * FROM pulsarmultitopictest;

-- [ERROR] Could not execute SQL statement. Reason:
-- org.apache.flink.table.api.ValidationException: One or more required options are missing.

-- Missing required options are:

-- topic
```

The appending `pulsar` connector seems to work with `topic-pattern` though

```sql
-- Flink SQL Client

CREATE TABLE pulsarmultitopictest (
  `physical_1` STRING,
  `physical_2` INT,
  `eventTime` TIMESTAMP(3) METADATA,
  `properties` MAP<STRING, STRING> METADATA ,
  `topic` STRING METADATA VIRTUAL,
  `sequenceId` BIGINT METADATA VIRTUAL,
  `key` STRING ,
  `physical_3` BOOLEAN
) WITH (
  'connector' = 'pulsar', -- NOTE
  'topic-pattern' = 'persistent://public/default/multitopictest.*', -- NOTE
  'key.format' = 'raw',
  'key.fields' = 'key',
  'value.format' = 'json',
  'service-url' = 'pulsar://pulsar:6650',
  'admin-url' = 'http://pulsar:8080',
  'scan.startup.mode' = 'earliest'
);

SELECT * FROM pulsarmultitopictest;
```

Now send some messages to various topics that match `topic-pattern`.
```sh
# inside Pulsar container, docker-compose exec pulsar bash

./bin/pulsar-client produce persistent://public/default/multitopictest1 -f <(echo '{"physical_1":"data 1","physical_2":100,"key":"key1","physical_3":false}')

./bin/pulsar-client produce persistent://public/default/multitopictest2 -f <(echo '{"physical_1":"data 1","physical_2":100,"key":"key1","physical_3":false}')

./bin/pulsar-client produce persistent://public/default/multitopictest3 -f <(echo '{"physical_1":"data 1","physical_2":100,"key":"key1","physical_3":false}')
```

Note that the Flink SQL query does **NOT** return these rows.

Stop the query, and rerun it again

```sql
-- Flink SQL Client

SELECT * FROM pulsarmultitopictest;
```

_Now_ the `topic-pattern` detects the matched topics and displays the rows.

**Takeaway**: The appending `pulsar` connector can source from multiple topics.
However, it seems like topic detection happens at job startup?

## Can we use the Debezium value format with the Flink Pulsar connector?
The Flink [Debezium value
format](https://ci.apache.org/projects/flink/flink-docs-release-1.12/dev/table/connectors/formats/debezium.html)
is intended to interpret the data format that Debezium provides.

To experiment with this, let's bring up another piece of the system (Pulsar IO
Postgres Source Connector) so that our system now looks like this.

![System
diagram](/docs/system-diagram-2.svg?raw=true&sanitize=true
"System diagram")

Start the [Pulsar IO](https://pulsar.apache.org/docs/en/io-overview/) Postgres [Debezium source connector](https://pulsar.apache.org/docs/en/io-debezium-source/) in the running Pulsar container.
This will start the Postgres → Pulsar change-data-capture connection.
```sh
docker-compose exec pulsar /pulsar/bin/pulsar-admin source localrun --source-config-file /debezium-postgres-source-config.yaml
```

> Note: This leverages ["local run
> mode"](https://pulsar.apache.org/docs/en/functions-deploy/#local-run-mode). In
> production deployments, you'd likely want to leverage ["cluster
> mode"](https://pulsar.apache.org/docs/en/functions-deploy/#cluster-mode).

List Pulsar topics
```sh
docker-compose exec pulsar /pulsar/bin/pulsar-admin topics list public/default

# "persistent://public/default/source-db1.public.users"
# "persistent://public/default/debezium-postgres-source-debezium-offset-topic"
# "persistent://public/default/debezium-postgres-topic"
```

Insert some data into Postgres
```sql
-- source-db1 psql, docker-compose exec source-db1 psql experiment experiment

INSERT INTO users (full_name) VALUES ('bob');
```

For reference: a Debezium message look like this:
```json
{
  "before": null,
  "after": {
    "id": 2,
    "full_name": "bob"
  },
  "source": {
    "version": "1.0.0.Final",
    "connector": "postgresql",
    "name": "source-db1",
    "ts_ms": 1615476804970,
    "snapshot": "false",
    "db": "experiment",
    "schema": "public",
    "table": "users",
    "txId": 561,
    "lsn": 23439752,
    "xmin": null
  },
  "op": "c",
  "ts_ms": 1615476806822
}
```

Set up Flink dynamic table
```sql
-- Flink SQL Client

CREATE TABLE pulsardebeziumtest (
  `full_name` STRING,
  `id` BIGINT,
  `eventTime` TIMESTAMP(3) METADATA,
  `properties` MAP<STRING, STRING> METADATA ,
  `topic` STRING METADATA VIRTUAL,
  `sequenceId` BIGINT METADATA VIRTUAL,
  PRIMARY KEY (id) NOT ENFORCED
) WITH (
  'connector' = 'upsert-pulsar', -- NOTE
  'topic' = 'persistent://public/default/source-db1.public.users',
  'key.format' = 'raw',
  'value.format' = 'debezium-json', -- NOTE
  'service-url' = 'pulsar://pulsar:6650',
  'admin-url' = 'http://pulsar:8080'
);

SELECT * from pulsardebeziumtest

-- [ERROR] Could not execute SQL statement. Reason:
-- org.apache.flink.table.api.ValidationException: 'upsert-Pulsar' connector doesn't support 'debezium-json' as value format, because 'debezium-json' is not in insert-only mode.
```

> Note: The relevant `pulsar-flink` code is
> [here](https://github.com/streamnative/pulsar-flink/blob/branch-2.7.5/pulsar-flink-connector/src/main/java/org/apache/flink/streaming/connectors/pulsar/table/UpsertPulsarDynamicTableFactory.java#L241).

Now, let's try the appending `pulsar` connector instead

```sql
-- Flink SQL Client

CREATE TABLE pulsardebeziumappendtest (
  `id` BIGINT,
  `full_name` STRING,
  `eventTime` TIMESTAMP(3) METADATA FROM 'value.source.timestamp' VIRTUAL,
  `origin_table` STRING METADATA FROM 'value.source.table' VIRTUAL,
  `source_schema` STRING METADATA FROM 'value.source.schema' VIRTUAL,
  `source_database` STRING METADATA FROM 'value.source.database' VIRTUAL,

  `properties` MAP<STRING, STRING> METADATA,
  `topic` STRING METADATA VIRTUAL,
  `sequenceId` BIGINT METADATA VIRTUAL
) WITH (
  'connector' = 'pulsar', -- NOTE
  'topic' = 'persistent://public/default/source-db1.public.users',
  'value.format' = 'debezium-json', -- NOTE
  'service-url' = 'pulsar://pulsar:6650',
  'admin-url' = 'http://pulsar:8080',
  'scan.startup.mode' = 'earliest'
);
```

For reference, for usage as columns, the `DynamicTableSource` class
`org.apache.flink.streaming.connectors.pulsar.table.PulsarDynamicTableSource`
supports the following metadata keys:

- value.schema
- value.ingestion-timestamp
- value.source.timestamp
- value.source.database
- value.source.schema
- value.source.table
- value.source.properties
- topic
- messageId
- sequenceId
- publishTime
- eventTime
- properties

See here for available Debezium format metadata and how to map them to table
columns:
https://ci.apache.org/projects/flink/flink-docs-stable/dev/table/connectors/formats/debezium.html#available-metadata

Now try again, now using one table set up with the `pulsar` append mode
connector to insert into another table with `upsert-pulsar` upsert mode
connector. Using `upsert-kafka` as a reference (https://ci.apache.org/projects/flink/flink-docs-release-1.12/dev/table/connectors/upsert-kafka.html)

```sql
-- Flink SQL Client

-- Create an append mode table with incoming data from Debezium
CREATE TABLE pulsardebeziumappendtest (
  `id` BIGINT,
  `full_name` STRING,
  `eventTime` TIMESTAMP(3) METADATA FROM 'value.source.timestamp' VIRTUAL,
  `origin_table` STRING METADATA FROM 'value.source.table' VIRTUAL,
  `source_schema` STRING METADATA FROM 'value.source.schema' VIRTUAL,
  `source_database` STRING METADATA FROM 'value.source.database' VIRTUAL,

  `properties` MAP<STRING, STRING> METADATA,
  `topic` STRING METADATA VIRTUAL,
  `sequenceId` BIGINT METADATA VIRTUAL
) WITH (
  'connector' = 'pulsar',
  'topic' = 'persistent://public/default/source-db1.public.users',
  'value.format' = 'debezium-json',
  'service-url' = 'pulsar://pulsar:6650',
  'admin-url' = 'http://pulsar:8080',
  'scan.startup.mode' = 'earliest'
);

-- Create an upsert mode table
CREATE TABLE pulsardebeziumupsertest (
  `id` BIGINT,
  `full_name` STRING,
  `eventTime` TIMESTAMP(3) METADATA,
  `properties` MAP<STRING, STRING> METADATA,
  `topic` STRING METADATA VIRTUAL,
  `sequenceId` BIGINT METADATA VIRTUAL,
  PRIMARY KEY (id) NOT ENFORCED
) WITH (
  'connector' = 'upsert-pulsar',
  'topic' = 'persistent://public/default/upserttest',
  'key.format' = 'raw',
  'value.format' = 'json',
  'service-url' = 'pulsar://pulsar:6650',
  'admin-url' = 'http://pulsar:8080'
);
```

```sql
-- source-db1 psql

INSERT INTO users (full_name) VALUES ('bob');
INSERT INTO users (full_name) VALUES ('bob 2');
UPDATE users SET full_name = 'bobby' WHERE id = 1;
-- DELETE FROM users WHERE id = 1 -- TODO: this doesn't show up in pulsardebeziumappendtest. Look more into this.
```

```sql
-- Flink SQL Client

-- Get the most recent row per key from the append mode table
-- and use that as an insert query into the upsert mode table
--
-- https://ci.apache.org/projects/flink/flink-docs-release-1.12/dev/table/sql/queries.html#deduplication

INSERT INTO pulsardebeziumupsertest (id, full_name, eventTime, properties)
SELECT
  id,
  full_name,
  eventTime,
  MAP['k11', 'v11', 'k12', 'v12'] -- TODO: proper values for the below
FROM (
  SELECT
    id,
    full_name,
    eventTime,
    ROW_NUMBER() OVER (       -- ROW_NUMBER assigns a unique, sequential number to each row, starting with one.
      PARTITION BY id         -- the partitioning / deduplicate key
      ORDER BY eventTime DESC -- the ordering column. It must be a time attribute
    ) as row_num
  FROM pulsardebeziumappendtest)
WHERE row_num = 1;

SELECT * FROM pulsardebeziumupsertest;
```

```sql
-- source-db1 psql

-- INSERT works as expected
INSERT INTO users (full_name) VALUES ('bob');
INSERT INTO users (full_name) VALUES ('bob 2');

-- UPDATE works too
UPDATE users SET full_name = 'bobby' WHERE id = 1;

-- TODO: DELETE breaks the job, unfortunately.
-- I might be doing something weird, though. Look into this some more.
-- DELETE FROM users WHERE id = 1
-- Caused by: java.lang.RuntimeException: Can not retract a non-existent record. This should never happen.
```

## What if I want to work more directly with JSON, instead of the Debezium formatter
Let's try setting up the connector with `value.format=json`.

Again, for reference, a Debezium message look like this:
```json
{
  "before": null,
  "after": {
    "id": 2,
    "full_name": "bob"
  },
  "source": {
    "version": "1.0.0.Final",
    "connector": "postgresql",
    "name": "source-db1",
    "ts_ms": 1615476804970,
    "snapshot": "false",
    "db": "experiment",
    "schema": "public",
    "table": "users",
    "txId": 561,
    "lsn": 23439752,
    "xmin": null
  },
  "op": "c",
  "ts_ms": 1615476806822
}
```

```sql
-- Flink SQL Client

CREATE TABLE pulsardebeziumappendtest (
  `before` STRING,
  `after` STRING,
  `source` STRING,
  `op` STRING,

  -- Accessing nested fields from the json
  `source` ROW(`schema` STRING, `db` STRING, `name` STRING),

  -- Flattening nested fields
  `source_schema` AS source.schema,
  `source_db` AS source.db,
  `source_name` AS source.name,

  -- Pulsar metadata fields
  `eventTime` TIMESTAMP(3) METADATA,
  `properties` MAP<STRING, STRING> METADATA,
  `topic` STRING METADATA VIRTUAL,
  `sequenceId` BIGINT METADATA VIRTUAL
) WITH (
  'connector' = 'pulsar',
  'topic' = 'persistent://public/default/source-db1.public.users',
  'value.format' = 'json', -- NOTE
  'service-url' = 'pulsar://pulsar:6650',
  'admin-url' = 'http://pulsar:8080',
  'scan.startup.mode' = 'earliest'
);

SELECT
  *,
  -- Nested fields can be accessed like this
  source.schema,
  source.db,
  source.name
FROM pulsardebeziumappendtest;
```

## A sidenote on GPDR

One challenge with a message bus middleware based approach will be harmonizing
bootstrapping/backfilling ("I need enough changelog data to rebuild state") with
GPDR data deletion requirements ("There is some state that I want to remove
everywhere").

Aside from the "encrypt and throw away key" approach (which has its tradeoffs),
there is another approach - based on compaction + tombstones. While [Kafka's
approach to compaction](https://kafka.apache.org/documentation/#compaction) (the
most recent message per non-deleted key is retained forever, and tombstoned keys
are deleted everywhere) should work for this purpose, [Pulsar's approach to
compaction](https://pulsar.apache.org/docs/en/concepts-topic-compaction/) (a
separate compacted topic is maintained in parallel with the original
non-compacted topic) is problematic until the ability to configure lifecycle
(i.e. retention policy) of both compacted and original topic independently is
implemented. As of Pulsar `2.7.0`, this capability is not yet available.

## Future explorations
- Pulsar changelog topics + GPDR + lifecycle policies
- How might we consolidate/merge multiple (logically same, but physically
  independent) source tables from distinct Postgres nodes and schemas into one
  logical dynamic table? For example: With a Postgres + schema per tenant
  database structure. Also, an analogous demuxing at a sink.

## Reference of useful commands
List Pulsar topics
```sh
docker-compose exec pulsar /pulsar/bin/pulsar-admin topics list public/default
```

Delete Pulsar topic
```sh
docker-compose exec pulsar /pulsar/bin/pulsar-admin topics delete persistent://public/default/source-db1.public.users
```

## Resources
- [Flink](https://flink.apache.org/)
- [Pulsar](https://pulsar.apache.org/)
- [Debezium](https://debezium.io/)
- Flink + Debezium
  - [Flink Debezium Format](https://ci.apache.org/projects/flink/flink-docs-stable/dev/table/connectors/formats/debezium.html)
  - [flink-cdc-connectors](https://github.com/ververica/flink-cdc-connectors) (not used in this exploration)
  - [FLIP-95](https://cwiki.apache.org/confluence/display/FLINK/FLIP-95%3A+New+TableSource+and+TableSink+interfaces)
  - [FLIP-105](https://cwiki.apache.org/confluence/pages/viewpage.action?pageId=147427289)
- Flink + Pulsar
  - [Flink Pulsar connector](https://github.com/streamnative/pulsar-flink)
  - [FLIP-72](https://cwiki.apache.org/confluence/display/FLINK/FLIP-72%3A+Introduce+Pulsar+Connector)
- [Flink SQL
Client](https://ci.apache.org/projects/flink/flink-docs-stable/dev/table/sqlClient.html)
- [Pulsar IO CDC Debezium source
  connector](https://pulsar.apache.org/docs/en/io-cdc-debezium/)
