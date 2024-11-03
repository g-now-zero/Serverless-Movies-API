import azure.functions as func
import logging
from azure.cosmos import CosmosClient
import os
import json

app = func.FunctionApp()

@app.route(route="getmovies")
def get_movies(req: func.HttpRequest) -> func.HttpResponse:
    logging.info('Processing GetMovies request')

    try:
        cosmos_client = CosmosClient.from_connection_string(os.environ["COSMOSDB_CONNECTION_STRING"])
        database = cosmos_client.get_database_client("moviedb")
        container = database.get_container_client("movies")

        # Get all documents
        query = "SELECT * FROM c"
        documents = list(container.query_items(query=query, enable_cross_partition_query=True))
        
        # Extract movies from all letter groups
        all_movies = []
        for doc in documents:
            for key, value in doc.items():
                if isinstance(value, dict) and 'movies' in value:
                    all_movies.extend(value['movies'])
        
        # Sort by title and remove duplicates (if any)
        unique_movies = {movie['title']: movie for movie in all_movies}.values()
        sorted_movies = sorted(unique_movies, key=lambda x: x['title'])

        return func.HttpResponse(
            json.dumps({
                "movies": sorted_movies,
                "total": len(sorted_movies)
            }),
            mimetype="application/json"
        )

    except Exception as e:
        logging.error(f"Error in GetMovies: {str(e)}")
        return func.HttpResponse(
            f"An error occurred while retrieving movies: {str(e)}",
            status_code=500
        )

@app.route(route="getmoviesbyyear")
def get_movies_by_year(req: func.HttpRequest) -> func.HttpResponse:
    logging.info('Processing GetMoviesByYear request')

    try:
        # Get year from query parameter
        year = req.params.get('year')
        if not year:
            return func.HttpResponse(
                "Please provide a year parameter",
                status_code=400
            )
            
        try:
            year = int(year)
        except ValueError:
            return func.HttpResponse(
                "Year must be a valid number",
                status_code=400
            )

        # Connect to Cosmos DB
        cosmos_client = CosmosClient.from_connection_string(os.environ["COSMOSDB_CONNECTION_STRING"])
        database = cosmos_client.get_database_client("moviedb")
        container = database.get_container_client("movies")

        # Get the document for the specified year
        try:
            doc = container.read_item(
                item="year_" + str(year),
                partition_key=year
            )
        except:
            return func.HttpResponse(
                json.dumps({
                    "movies": [],
                    "total": 0,
                    "message": f"No movies found for year {year}"
                }),
                mimetype="application/json"
            )

        # Extract movies from all letter groups
        all_movies = []
        for key, value in doc.items():
            if isinstance(value, dict) and 'movies' in value:
                all_movies.extend(value['movies'])

        # Sort by title
        sorted_movies = sorted(all_movies, key=lambda x: x['title'])

        return func.HttpResponse(
            json.dumps({
                "movies": sorted_movies,
                "total": len(sorted_movies),
                "year": year
            }),
            mimetype="application/json"
        )

    except Exception as e:
        logging.error(f"Error in GetMoviesByYear: {str(e)}")
        return func.HttpResponse(
            f"An error occurred while retrieving movies: {str(e)}",
            status_code=500
        )
    