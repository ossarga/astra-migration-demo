DROP TABLE IF EXISTS demo_keyspace.demo_table;

CREATE TABLE IF NOT EXISTS demo_keyspace.demo_table(
    id int,
    day_window int,
    read_timestamp timestamp,
    value int,
    PRIMARY KEY ((id, day_window), read_timestamp)
);