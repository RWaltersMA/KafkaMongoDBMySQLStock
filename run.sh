#!/bin/bash

set -e
(
if lsof -Pi :27017 -sTCP:LISTEN -t >/dev/null ; then
    echo "Please terminate the local mongod on 27017"
    exit 1
fi
)

echo "Starting docker ."
docker-compose up -d --build
function clean_up {
    echo "\n\nSHUTTING DOWN\n\n"
    curl --output /dev/null -X DELETE http://localhost:8083/connectors/mysql-atlas-sink || true
    echo "Removed MySQL topic to Atlas Sink"
    curl --output /dev/null -X DELETE http://localhost:8083/connectors/mongo-atlas-sink || true
    echo "Removed Mongo topic to Atlas Sink"
    docker-compose exec mongo1 /usr/bin/mongo --eval "db.dropDatabase()"
    echo "Dropped database on Mongo1"
    docker-compose down -v
    if [[ -z "$1" ]]; then
      echo "NOTE: Data from the demo was left on the MongoDB Atlas cluster.\nIf you would like a clean demo make sure to remove data in the StockData collection.\n\nBye!\n"
    fi
}

sleep 5
echo "\n\nWaiting for the systems to be ready.."
function test_systems_available {
  COUNTER=0
  until $(curl --output /dev/null --silent --head --fail http://localhost:$1); do
      printf '.'
      sleep 2
      let COUNTER+=1
      if [[ $COUNTER -gt 30 ]]; then
        MSG="\nWARNING: Could not reach configured kafka system on http://localhost:$1 \nNote: This script requires curl.\n"

          if [[ "$OSTYPE" == "darwin"* ]]; then
            MSG+="\nIf using OSX please try reconfiguring Docker and increasing RAM and CPU. Then restart and try again.\n\n"
          fi

        echo -e $MSG
        clean_up "$MSG"
        exit 1
      fi
  done
}

test_systems_available 8082
test_systems_available 8083

trap clean_up EXIT

echo -e "\nConfiguring the MongoDB ReplicaSet...\n"
docker-compose exec mongo1 /usr/bin/mongo --eval '''rsconf = { _id : "rs0", members: [ { _id : 0, host : "mongo1:27017", priority: 1.0 }]};
rs.initiate(rsconf);'''

echo "\nCleaning up local MongoDB databases (dropping Stocks database):"
docker-compose exec mongo1 /usr/bin/mongo --eval '''db.runCommand( { dropDatabase: 1 } );''' Stocks

echo "\nKafka Topics:"
curl -X GET "http://localhost:8082/topics" -w "\n"

echo "\nKafka Connectors:"
curl -X GET "http://localhost:8083/connectors/" -w "\n"

sleep 2
echo "\nAdding MongoDB Kafka Source Connector for the 'stocks.stockdata' collection:"
curl -X POST -H "Content-Type: application/json" --data '
  {"name": "mongo-source-stockdata",
   "config": {
     "tasks.max":"1",
     "connector.class":"com.mongodb.kafka.connect.MongoSourceConnector",
     "key.converter":"org.apache.kafka.connect.json.JsonConverter",
     "key.converter.schemas.enable":false,
     "value.converter":"org.apache.kafka.connect.json.JsonConverter",
     "value.converter.schemas.enable":false,
     "publish.full.document.only": true,
     "connection.uri":"mongodb://mongo1:27017,mongo2:27017,mongo3:27017",
     "topic.prefix":"stockdata",
     "database":"Stocks",
     "collection":"StockData"
}}' http://localhost:8083/connectors -w "\n"

echo "\nAdding MongoDB Kafka Sink Connector for the 'stockdata' topic into the 'stocks.stockdata' collection in Atlas"
curl -X POST -H "Content-Type: application/json" --data '
  {"name": "mongo-atlas-sink",
   "config": {
     "connector.class":"com.mongodb.kafka.connect.MongoSinkConnector",
     "tasks.max":"1",
     "topics":"stockdata.Stocks.StockData",
     "connection.uri":"'"$1"'",
     "database":"Stocks",
     "collection":"StockData",
     "key.converter":"org.apache.kafka.connect.json.JsonConverter",
     "key.converter.schemas.enable":false,
     "value.converter":"org.apache.kafka.connect.json.JsonConverter",
     "value.converter.schemas.enable":false,
     "timeseries.timefield":"tx_time",
     "timeseries.timefield.auto.convert":"true"
}}' http://localhost:8083/connectors -w "\n"

echo "\nAdding MongoDB Kafka Sink Connector for the MySQL topic into the 'stocks.stockdata' collection in Atlas"
curl -X POST -H "Content-Type: application/json" --data '
  {"name": "mysql-atlas-sink",
   "config": {
     "connector.class":"com.mongodb.kafka.connect.MongoSinkConnector",
     "tasks.max":"1",
     "topics":"mysqlstock.Stocks.StockData",
     "connection.uri":"'"$1"'",
     "database":"Stocks",
     "collection":"StockData",
     "key.converter":"io.confluent.connect.avro.AvroConverter",
     "key.converter.schema.registry.url":"http://schema-registry:8081",
     "value.converter":"io.confluent.connect.avro.AvroConverter",
     "value.converter.schema.registry.url":"http://schema-registry:8081",
     "transforms": "ExtractField",
     "transforms.ExtractField.type":"org.apache.kafka.connect.transforms.ExtractField$Value",
     "transforms.ExtractField.field":"after",
     "timeseries.timefield":"tx_time",
     "timeseries.timefield.auto.convert":"true"
}}' http://localhost:8083/connectors -w "\n"



sleep 3
echo "\nAdding Debezium MySQL Source Connector for the 'Stocks.StockData' table:"
curl -X POST -H "Content-Type: application/json" --data '
{
  "name": "mysql-connector",
  "config": {
        "connector.class": "io.debezium.connector.mysql.MySqlConnector",
    "tasks.max": "1",
    "database.hostname": "mysqlstock",
    "database.port": "3306",
    "database.user": "mysqluser",
    "database.password": "pass@word1",
    "database.server.id": "223344",
    "database.server.name": "mysqlstock",
    "database.whitelist": "Stocks",
    "database.history.kafka.bootstrap.servers": "broker:29092",
    "database.history.kafka.topic": "dbhistory.StockData",
    "key.converter": "io.confluent.connect.avro.AvroConverter",
    "value.converter": "io.confluent.connect.avro.AvroConverter",
    "key.converter.schema.registry.url": "http://schema-registry:8081",
    "value.converter.schema.registry.url": "http://schema-registry:8081"
  }
}}' http://localhost:8083/connectors -w "\n"


sleep 2
echo "\nKafka Connectors: \n"
curl -X GET "http://localhost:8083/connectors/" -w "\n"

echo '''

==============================================================================================================
To see the list of stocks navigate to
http://127.0.0.1:9021 on your host/client

==============================================================================================================

Use <ctrl>-c to quit'''

read -r -d '' _ </dev/tty


