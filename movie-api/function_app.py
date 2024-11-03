import azure.functions as func
import logging
from azure.cosmos import CosmosClient
import os
import json

app = func.FunctionApp()

@app.route(route="getmovies")
def get_movies(req: func.HttpRequest) -> func.HttpResponse:
    logging.info('Testing Cosmos DB connectivity')

    try:
        cosmos_client = CosmosClient.from_connection_string(os.environ["COSMOSDB_CONNECTION_STRING"])
        database = cosmos_client.get_database_client("moviedb")
        container = database.get_container_client("movies")

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
