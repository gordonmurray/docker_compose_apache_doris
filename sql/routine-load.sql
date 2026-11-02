CREATE ROUTINE LOAD products.kafka_fruit ON kafka_table
COLUMNS TERMINATED BY ",",
COLUMNS (fruit, price)
PROPERTIES (
    "desired_concurrent_number" = "1",
    "max_batch_interval" = "5",
    "strict_mode" = "true",
    "format" = "csv"
)
FROM KAFKA (
    "kafka_broker_list" = "kafka:9092",
    "kafka_topic" = "kafka_topic",
    "property.kafka_default_offsets" = "OFFSET_BEGINNING"
);
