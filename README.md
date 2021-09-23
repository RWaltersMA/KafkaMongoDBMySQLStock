# Overview
This repository is used for the demo for the Confluent Data in Motion - MongoDB session

After cloning the repository

`sh build.sh`

this will build a MySQL image and two other images that generate the ficticious stock data.

Next start the environment

`sh run.sh "MONGODB CONNECTION STRING GOES HERE"`

Don't forget the quotes.  (e.g. `sh run.sh "mongodb+srv://USERNAME:PASSWORD@stock.lkyil.mongodb.net/Stocks?retryWrites=true&w=majority"`)

If successful you will have the Confluent Portal http://127.0.0.1:9021/

There are two connectors configured one for the local MysQL and one for local MongoDB.  If you connect to the portal you can see a stockdata.stock topic that will contain data from both databases.  These data will be written to MongoDB Atlas (the connection string you supplied on the run command above)




