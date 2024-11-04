import azure.functions as func
import logging
from azure.cosmos import CosmosClient
import os
import json
from typing import Optional

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
    
@app.route(route="getmoviesummary")
def get_movie_summary(req: func.HttpRequest) -> func.HttpResponse:
    logging.info('Processing GetMovieSummary request')
    try:
        # Get movie title from query parameter
        title = req.params.get('title')
        if not title:
            return func.HttpResponse(
                "Please provide a movie title parameter",
                status_code=400
            )
            
        # Connect to Cosmos DB
        cosmos_client = CosmosClient.from_connection_string(os.environ["COSMOSDB_CONNECTION_STRING"])
        database = cosmos_client.get_database_client("moviedb")
        container = database.get_container_client("movies")

        # Find the movie in any year document
        movie = None
        query = "SELECT * FROM c"
        documents = list(container.query_items(query=query, enable_cross_partition_query=True))
        
        for doc in documents:
            for key, value in doc.items():
                if isinstance(value, dict) and 'movies' in value:
                    for m in value['movies']:
                        if m['title'].lower() == title.lower():
                            movie = m
                            break
            if movie:
                break

        if not movie:
            return func.HttpResponse(
                json.dumps({
                    "error": f"Movie '{title}' not found"
                }),
                status_code=404,
                mimetype="application/json"
            )

        # Connect to Azure OpenAI
        openai_endpoint = os.environ["OPENAI_API_ENDPOINT"].rstrip('/')
        openai_key = os.environ["OPENAI_API_KEY"]
        deployment_name = os.environ["OPENAI_DEPLOYMENT_NAME"]
        api_version = os.environ["OPENAI_API_VERSION"]

        headers = {
            "Content-Type": "application/json",
            "api-key": openai_key
        }

        # Prepare the prompt
        prompt = f"""Write a brief, engaging summary of the movie "{movie['title']}" ({movie['year']}).
                    This is a {movie['genre']} film.
                    Keep the summary concise, around 2-3 sentences."""

        # Prepare the API request
        payload = {
            "messages": [
                {"role": "system", "content": "You are a knowledgeable film critic who provides concise, engaging movie summaries."},
                {"role": "user", "content": prompt}
            ],
            "max_tokens": 150,
            "temperature": 0.7
        }

        # Call Azure OpenAI API
        import requests
        
        api_url = f"{openai_endpoint}/openai/deployments/{deployment_name}/chat/completions?api-version={api_version}"
        
        response = requests.post(
            api_url,
            headers=headers,
            json=payload,
            timeout=30
        )

        if response.status_code != 200:
            logging.error(f"OpenAI API error: {response.text}")
            return func.HttpResponse(
                json.dumps({
                    "error": "Error generating summary",
                    "title": movie['title']
                }),
                status_code=500,
                mimetype="application/json"
            )

        # Extract the generated summary
        summary = response.json()['choices'][0]['message']['content'].strip()

        # Return just the title and summary
        return func.HttpResponse(
            json.dumps({
                "title": movie['title'],
                "summary": summary
            }),
            mimetype="application/json"
        )

    except Exception as e:
        logging.error(f"Error in GetMovieSummary: {str(e)}")
        return func.HttpResponse(
            json.dumps({
                "error": "An error occurred while processing the request"
            }),
            status_code=500,
            mimetype="application/json"
        )
