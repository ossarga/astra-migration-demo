DROP KEYSPACE IF EXISTS test_keyspace;

CREATE KEYSPACE IF NOT EXISTS test_keyspace
    WITH REPLICATION = { 'class' : 'NetworkTopologyStrategy', '##DATACENTER_REPLICATION##' : 1 }
    AND durable_writes = true;

CREATE TABLE IF NOT EXISTS test_keyspace.test_table(
    key int,
    value text,
    PRIMARY KEY (key)
);