# Apache Doris with Docker Compose

Run Apache Doris locally and stream data from Kafka into a table you can query
with SQL. The default setup uses one frontend, one backend and one Kafka broker.
An optional configuration provides three frontends and three backends.

Images are pinned to **Doris 4.0.8** and **Kafka 4.1.2**. Kafka runs in KRaft mode,
without ZooKeeper.

## Requirements

- Docker Engine or Docker Desktop with **Docker Compose v2.24.4 or newer**.
- Git and Bash. The frontend image includes a MySQL client.
- At least **8 GiB of memory available to Docker** for the default setup,
  preferably more, plus space for the images and data. Container memory limits
  total 7 GiB for the default setup and 19 GiB for the larger cluster.
- AMD64 with AVX2 support, or ARM64. Use the native image for your machine.

On a Linux Docker host, raise the memory mapping limit before starting:

```bash
sudo sysctl -w vm.max_map_count=2000000
```

To retain the setting after a reboot:

```bash
printf 'vm.max_map_count=2000000\n' | sudo tee /etc/sysctl.d/99-doris.conf
sudo sysctl --system
```

With Docker Desktop, this setting applies inside its Linux VM. If startup reports
a low limit, configure it there. See the
[Doris deployment guide](https://doris.apache.org/docs/4.x/getting-started/quick-start/).

## Quick start

```bash
git clone https://github.com/gordonmurray/docker_compose_apache_doris.git
cd docker_compose_apache_doris
```

To change ports or the network subnet, copy `.env.example` to `.env` and edit it
before running the demo. See [Configuration](#configuration).

```bash
./scripts/demo.sh
```

The script waits for healthy services, creates `kafka_topic` and
`products.kafka_table`, starts the `products.kafka_fruit` Routine Load job, and
sends three sample messages. It then queries their prices:

```text
apples   0.60
bananas  0.30
oranges  0.45
```

Rerunning the demo updates the sample rows using a unique key on `fruit`; prices
use `DECIMAL(10,2)`. A new ingestion job reads the topic from the beginning.
An existing paused job is resumed once services are ready, retaining its saved
Kafka offsets. If it pauses again, inspect the cause before retrying.

To start only the services, leaving any paused ingestion job paused:

```bash
docker compose up -d --wait --wait-timeout 300
```

## Connect and query

| Interface | Default address |
| --- | --- |
| Doris Web UI | <http://localhost:8030> |
| MySQL protocol | `127.0.0.1:9030` |
| Kafka, inside the Compose network | `kafka:9092` |

This local setup uses Doris user `root` with an empty password. Published ports
bind to `127.0.0.1`; Kafka and backend ports remain inside the Docker network.

Open a SQL session using the bundled client:

```bash
docker compose exec fe mysql -h127.0.0.1 -P9030 -uroot
```

Or connect with a MySQL client installed on your host:

```bash
mysql -h127.0.0.1 -P9030 -uroot
```

Run these queries in either SQL session:

```sql
SHOW FRONTENDS;
SHOW BACKENDS;
SELECT * FROM products.kafka_table ORDER BY fruit;
SHOW ROUTINE LOAD FOR products.kafka_fruit;
```

From another terminal, send a message and query the table again after a few seconds:

```bash
printf 'pears,0.75\n' | docker compose exec -T kafka \
  /opt/kafka/bin/kafka-console-producer.sh \
  --bootstrap-server kafka:9092 --topic kafka_topic
```

Use Kafka commands through `docker compose exec`. The broker advertises
`kafka:9092`, which is resolvable inside Docker; host producers would need a
separate external listener.

## Verify the pipeline

```bash
./scripts/smoke-test.sh
```

The smoke test runs the demo, checks frontend and backend membership, sends a
unique message, verifies its price in Doris, and removes the test row.

GitHub Actions validates both Compose configurations and shell scripts, then
tests ingestion and data persistence after recreating the default containers.
The larger cluster is configuration-checked in CI; run its smoke test on a
machine with enough memory.

## Stop, restart or reset

Named volumes store Doris metadata, backend storage, logs and Kafka data.
Stop and restart without deleting data:

```bash
docker compose down
./scripts/demo.sh
```

To **delete all data in the default setup**:

```bash
docker compose down --volumes
```

## Optional larger cluster

The larger configuration uses three frontends, three backends and three table
replicas. It has a separate Compose project and volumes. Stop the default setup
first to release the shared ports and subnet:

```bash
docker compose down
./scripts/demo.sh --cluster
./scripts/smoke-test.sh --cluster
```

Use the same project name and both files for subsequent cluster commands:

```bash
docker compose -p trying-doris-cluster \
  -f docker-compose.yml -f docker-compose.cluster.yml ps

docker compose -p trying-doris-cluster \
  -f docker-compose.yml -f docker-compose.cluster.yml \
  exec fe mysql -h127.0.0.1 -P9030 -uroot
```

To stop the larger cluster and return to the default setup:

```bash
docker compose -p trying-doris-cluster \
  -f docker-compose.yml -f docker-compose.cluster.yml down
./scripts/demo.sh
```

Add `--volumes` to the larger cluster's `down` command only to delete its data.
Keep the projects separate: removing frontends from a persisted cluster by
switching Compose files can prevent it from reaching quorum.

## Configuration

[`.env.example`](.env.example) contains the image versions, host ports and network
prefix. Copy it to `.env` to override the defaults. Choose an unused private `/24`
subnet before the first start. Doris registers nodes by IP, so changing the
subnet requires fresh volumes in this demo.

[`fe/conf/fe.conf`](fe/conf/fe.conf) and [`be/conf/be.conf`](be/conf/be.conf)
contain configuration overrides. The startup script applies them to the image's
configuration while preserving its Java options and setting smaller JVM heaps.
Restart the services after editing these files.

The original 2023 setup used `/data/...` bind mounts and Doris 2.0-alpha.
This setup uses fresh named volumes and does not migrate or delete those old
files. If you need to retain an old database, follow the
[official upgrade guidance](https://doris.apache.org/docs/4.x/admin-manual/cluster-management/upgrade/).

## Troubleshooting

```bash
docker compose ps --all
docker compose logs --tail=100
```

- For startup failures, check memory, `vm.max_map_count` and AVX2 support on AMD64.
- Doris logs are in `/opt/apache-doris/fe/log` and `/opt/apache-doris/be/log`
  inside the corresponding containers.
- For a paused ingestion job, inspect `SHOW ROUTINE LOAD FOR products.kafka_fruit;`,
  fix the reported cause, then run `RESUME ROUTINE LOAD FOR products.kafka_fruit;`.
- A timeout leaves containers and data available for inspection. Fix the cause
  and rerun the script; it never resets volumes automatically.

Originally inspired by
[Empowering cyber security by enabling seven times faster log analysis](https://doris.apache.org/blog/empowering-cyber-security-by-enabling-seven-times-faster-log-analysis).
