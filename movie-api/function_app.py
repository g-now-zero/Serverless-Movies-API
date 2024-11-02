import azure.functions as func
import datetime
import json
import logging
from azure.cosmos import CosmosClient
import os

app = func.FunctionApp()

# Initialize Cosmos DB client
cosmos_client = CosmosClient.from_connection_string(os.environ["COSMOSDB_CONNECTION_STRING"])
database = cosmos_client.get_database_client("moviedb")
container = database.get_container_client("movies")

@app.route(route="GetMovies", auth_level=func.AuthLevel.Function)
def GetMovies(req: func.HttpRequest) -> func.HttpResponse:
    logging.info('Testing Cosmos DB connectivity')

    try:
        movies = list(container.query_items(
            query="SELECT * FROM movies c",
            enable_cross_partition_query=True
        ))

        return func.HttpResponse(
            json.dumps({"status": "connected", "count": len(movies)}),
            mimetype="application/json"
        )

    except Exception as e:
        logging.error(f"Connection test failed: {str(e)}")
        return func.HttpResponse(
            f"Failed to connect to Cosmos DB: {str(e)}",
            status_code=500
        )
