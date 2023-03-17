DROP KEYSPACE IF EXISTS demo_keyspace;

CREATE KEYSPACE IF NOT EXISTS demo_keyspace
    WITH REPLICATION = { 'class' : 'NetworkTopologyStrategy', 'datacenter1' : 1 }
    AND durable_writes = true;

CREATE TABLE IF NOT EXISTS demo_keyspace.demo_table(
   id int,
   day_window int,
   read_timestamp timestamp,
   value int,
   PRIMARY KEY ((id, day_window), read_timestamp)
);