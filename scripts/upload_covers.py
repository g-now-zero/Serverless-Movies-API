"""
Movie Cover Upload Script using OMDB API

This script fetches movie poster images from OMDB API and uploads them to Azure Blob Storage,
then updates the movie records in Cosmos DB with the poster URLs.

Required Environment Variables:
- STORAGE_CONNECTION_STRING: Azure Blob Storage connection string
- COSMOSDB_CONNECTION_STRING: Cosmos DB connection string
- OMDB_API_KEY: Your API key from http://www.omdbapi.com/apikey.aspx

Example usage:
    export OMDB_API_KEY="your_key_here"
    export STORAGE_CONNECTION_STRING="your_storage_connection"
    export COSMOSDB_CONNECTION_STRING="your_cosmos_connection"
    python upload_covers.py
"""

import os
import time
import logging
import requests
from azure.storage.blob import BlobServiceClient
from azure.cosmos import CosmosClient
from requests.adapters import HTTPAdapter
from urllib3.util import Retry

# Configure logging
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

class MoviePosterUploader:
    def __init__(self, omdb_key, storage_conn_str):
        self.api_key = omdb_key
        self.base_url = "http://www.omdbapi.com/"
        
        # Set up blob storage
        self.blob_service = BlobServiceClient.from_connection_string(storage_conn_str)
        self.container = self.blob_service.get_container_client("movie-images")
        
        # Configure session with retries
        self.session = requests.Session()
        retries = Retry(
            total=2,
            backoff_factor=1,
            status_forcelist=[429, 500, 502, 503, 504]
        )
        self.session.mount('http://', HTTPAdapter(max_retries=retries))
        self.session.mount('https://', HTTPAdapter(max_retries=retries))

    def get_movie_poster(self, title, year=None):
        """Get movie poster URL from OMDB API"""
        try:
            params = {
                "apikey": self.api_key,
                "t": title
            }
            if year:
                params["y"] = str(year)

            response = self.session.get(self.base_url, params=params)
            response.raise_for_status()
            data = response.json()

            if data.get("Response") == "True" and data.get("Poster") != "N/A":
                return data["Poster"]
            else:
                logger.warning(f"No poster found for {title} ({year})")
                return None

        except Exception as e:
            logger.error(f"Error getting poster for {title}: {str(e)}")
            return None

    def upload_poster_to_blob(self, poster_url, title, year):
        """Download poster and upload to blob storage"""
        try:
            # Download poster
            response = self.session.get(poster_url)
            if response.status_code != 200:
                return None

            # Create safe blob name
            safe_title = "".join(x for x in title if x.isalnum() or x in (' ', '-', '_'))
            blob_name = f"{safe_title}-{year}.jpg"

            # Upload to blob storage
            blob_client = self.container.get_blob_client(blob_name)
            blob_client.upload_blob(response.content, overwrite=True)

            return blob_client.url

        except Exception as e:
            logger.error(f"Error uploading poster for {title}: {str(e)}")
            return None

def main():

    try:
        # Initialize uploader and cosmos client
        omdb_api_key = os.getenv('OMDB_API_KEY')
        storage_conn_str = os.getenv('STORAGE_CONNECTION_STRING')
        cosmos_conn_str = os.getenv('COSMOSDB_CONNECTION_STRING')

        if not omdb_api_key or not storage_conn_str or not cosmos_conn_str:
            logger.error("Missing one or more required environment variables.")
            return

        uploader = MoviePosterUploader(omdb_api_key, storage_conn_str)
        cosmos_client = CosmosClient.from_connection_string(cosmos_conn_str)
        database = cosmos_client.get_database_client("moviedb")
        container = database.get_container_client("movies")

        # Get all documents
        documents = list(container.query_items(
            query="SELECT * FROM c",
            enable_cross_partition_query=True
        ))

        # Process each document
        for doc in documents:
            modified = False
            
            # Process each letter group
            for key, value in doc.items():
                if isinstance(value, dict) and 'movies' in value:
                    # Process each movie
                    for movie in value['movies']:
                        if 'coverURL' not in movie:  # Skip if already has cover
                            logger.info(f"Processing {movie['title']} ({movie['year']})")
                            
                            # Add delay to avoid rate limiting
                            time.sleep(.3)
                            
                            # Get and upload poster
                            poster_url = uploader.get_movie_poster(movie['title'], movie['year'])
                            if poster_url:
                                cover_url = uploader.upload_poster_to_blob(
                                    poster_url, 
                                    movie['title'], 
                                    movie['year']
                                )
                                if cover_url:
                                    movie['coverURL'] = cover_url
                                    modified = True
                                    logger.info(f"Added cover for {movie['title']}")
            
            # Update document if modified
            if modified:
                container.replace_item(item=doc['id'], body=doc)

        logger.info("Movie cover upload process completed")

    except Exception as e:
        logger.error(f"Error in main process: {str(e)}")

if __name__ == "__main__":
    main()