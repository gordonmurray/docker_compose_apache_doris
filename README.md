# Trying out Apache Doris

![Static Badge](https://img.shields.io/badge/Just_testing-Not_production_ready-red)

A small Docker Compose project for trying Apache Doris and streaming data from
Kafka. Originally put together in 2023 after reading
[Empowering cyber security by enabling seven times faster log analysis](https://doris.apache.org/blog/empowering-cyber-security-by-enabling-seven-times-faster-log-analysis).

Updated to **Doris 4.0.8**, the release labelled Stable on the
[Apache Doris download page](https://doris.apache.org/download/) when this refresh
was made. The images are pinned to that version, rather than a moving `latest` tag.
Kafka uses the official `apache/kafka:4.1.2` image in KRaft mode, without ZooKeeper.

## Requirements

- Docker Engine or Docker Desktop with **Docker Compose v2.24.4 or newer**.
- Bash. A local MySQL client is optional; the scripts use the one in the FE image.
- For the default demo, allow at least **8 GiB of memory for Docker**, preferably
  more, and enough disk space for the images and data. The configured container
  memory limits total 7 GiB. The larger cluster's limits total 19 GiB.
- The official Doris images provide AMD64 and ARM64 builds. An AMD64 CPU needs
  AVX2 support. Use a native image for your machine.

On a Linux Docker host, raise the memory mapping limit before starting:

```bash
sudo sysctl -w vm.max_map_count=2000000
```

To retain the setting after a reboot:

```bash
printf 'vm.max_map_count=2000000\n' | sudo tee /etc/sysctl.d/99-doris.conf
sudo sysctl --system
```

With Docker Desktop, the setting applies inside its Linux VM. If startup reports
that the limit is too low, configure it there rather than on the macOS or Windows
host. Consult the [Doris deployment guide](https://doris.apache.org/docs/4.x/getting-started/quick-start/).

## Run the demo

```bash
./scripts/demo.sh
```

This starts one frontend, one backend and Kafka, waits for readiness, creates
`kafka_topic` and `products.kafka_table`, starts a Routine Load job, and sends
three sample messages. It waits until the corresponding prices can be queried:

```text
apples   0.60
bananas  0.30
oranges  0.45
```

The table uses a unique key on `fruit`, so repeating the demo updates the sample
prices rather than adding duplicate rows. Prices use `DECIMAL(10,2)`.
The job reads from the beginning of the Kafka topic on its first creation, so
messages produced before the consumer starts are included.

Running the demo also resumes its paused `products.kafka_fruit` job once all
services are ready. Doris can pause the job while containers restart. Resuming
retains its saved Kafka offsets; it does not recreate the job or reset the topic.
The script makes one resume attempt, so persistent ingestion errors still need
to be investigated. To leave a job paused, start only the services instead.

To start just the services:

```bash
docker compose up -d --wait --wait-timeout 300
```

## Connect and explore

| Interface | Address |
| --- | --- |
| Doris Web UI | <http://localhost:8030> |
| MySQL protocol | `127.0.0.1:9030` |
| Kafka, within the Compose network | `kafka:9092` |

Doris uses `root` with an empty password for this local demo. Published ports bind
to `127.0.0.1`. Kafka and BE ports are available only inside the Docker network.
This configuration is intended for local experimentation.

```bash
# Use the client already included in the frontend image.
docker compose exec fe mysql -h127.0.0.1 -P9030 -uroot

# Or use an installed MySQL client on the host.
mysql -h127.0.0.1 -P9030 -uroot
```

Try these queries:

```sql
SHOW FRONTENDS;
SHOW BACKENDS;
SELECT * FROM products.kafka_table ORDER BY fruit;
SHOW ROUTINE LOAD FOR products.kafka_fruit;
```

Send another message, then query again after a few seconds:

```bash
printf 'pears,0.75\n' | docker compose exec -T kafka \
  /opt/kafka/bin/kafka-console-producer.sh \
  --bootstrap-server kafka:9092 --topic kafka_topic
```

The broker advertises `kafka:9092`, which is resolvable by the Doris containers.
Use the bundled Kafka commands through `docker compose exec`; a host producer
would need a separate external Kafka listener.

## Verify the pipeline

```bash
./scripts/smoke-test.sh
```

The smoke test runs the demo, checks FE and BE membership, produces a uniquely
named message, waits for its exact price in Doris, and removes the test row.
Polling is bounded and failures print cluster and Routine Load diagnostics.

GitHub Actions validates both Compose configurations, checks the Bash scripts,
and runs the default smoke test. It also recreates the containers without
removing volumes, checks that the three sample rows survived, then tests ingestion
again. The larger cluster is configuration-checked in CI; run its smoke test on
a machine with enough memory.

## Optional three-frontend, three-backend cluster

Stop the default project first to release its ports and subnet. Its volumes are
retained. The larger configuration uses a separate project and separate volumes:

```bash
docker compose down
./scripts/demo.sh --cluster
./scripts/smoke-test.sh --cluster
```

The larger demo creates the table with **three replicas** instead of one. This is
still a single-machine learning environment. Run further commands with the same
project name and both files:

```bash
docker compose -p trying-doris-cluster \
  -f docker-compose.yml -f docker-compose.cluster.yml ps

docker compose -p trying-doris-cluster \
  -f docker-compose.yml -f docker-compose.cluster.yml \
  exec fe mysql -h127.0.0.1 -P9030 -uroot
```

To return to the default demo, stop the larger project with the same arguments
and `down`, then run `./scripts/demo.sh`. Do not remove followers from a running
cluster by merely switching Compose files: its persisted FE membership needs its
quorum. The separate project names keep these two experiments independent.

## Configuration and data

Optionally copy `.env.example` to `.env` to change the image versions, host ports
or network prefix. Choose an unused private `/24` subnet before the first start.
The Doris entrypoints register nodes by IP, so changing that subnet with existing
metadata is not supported by this demo; use fresh volumes for a different subnet.

The mounted files in `fe/conf` and `be/conf` contain small configuration overrides.
`scripts/start-doris.sh` applies these to the image's writable configuration and
reduces JVM heaps while retaining the release's other Java options. The official
entrypoints handle node registration and derive the matching network settings.
Restart the services after changing configuration files.

Doris metadata, backend storage, logs and Kafka data use named Docker volumes.
Stopping and recreating containers preserves them:

```bash
docker compose down
./scripts/demo.sh
```

For an intentional **reset that deletes all data in the default demo**:

```bash
docker compose down --volumes
```

To delete the larger demo's data, use its explicit project and both Compose files:

```bash
docker compose -p trying-doris-cluster \
  -f docker-compose.yml -f docker-compose.cluster.yml down --volumes
```

These commands do not touch the old 2023 setup's `/data/...` bind-mounted files.
This refresh starts a new demo; it does not migrate a 2.0-alpha database. Preserve
any old data separately and follow the
[official upgrade guidance](https://doris.apache.org/docs/4.x/admin-manual/cluster-management/upgrade/)
if it needs to be retained.

## Troubleshooting

- Inspect `docker compose ps --all` and `docker compose logs --tail=100` if startup
  fails. Check the host's `vm.max_map_count`, available memory and AVX2 support.
- FE and BE logs are also inside their containers under
  `/opt/apache-doris/fe/log` and `/opt/apache-doris/be/log`.
- If Routine Load pauses, inspect `SHOW ROUTINE LOAD FOR products.kafka_fruit;` for its
  reason, fix the cause, then use `RESUME ROUTINE LOAD FOR products.kafka_fruit;`.
- A timeout can be rerun after fixing the underlying problem. The scripts leave
  containers and data in place for inspection; they never reset volumes for you.
