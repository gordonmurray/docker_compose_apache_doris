CREATE DATABASE IF NOT EXISTS products;

-- Unique keys make re-running the sample producer update each fruit's price.
CREATE TABLE IF NOT EXISTS products.kafka_table (
    fruit VARCHAR(80) NOT NULL,
    price DECIMAL(10, 2) NOT NULL
)
ENGINE=OLAP
UNIQUE KEY(fruit)
DISTRIBUTED BY HASH(fruit) BUCKETS 3
PROPERTIES (
    "replication_num" = "${REPLICATION_NUM}",
    "enable_unique_key_merge_on_write" = "true"
);
