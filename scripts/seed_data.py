"""
Movie Data Seeding Script for Cosmos DB

Setup:
1. Place your CSV file in the /scripts/data/ directory
2. Ensure your CSV has these required columns (case-insensitive):
   - Title  : Movie title (e.g., "The Dark Knight")
   - Genre  : Movie genre (e.g., "Action")
   - Year   : Release year (e.g., 2008)
   
Requirements:
- Azure Cosmos DB connection string set as environment variable: COSMOSDB_CONNECTION_STRING
- CSV file placed in /scripts/data/ directory
"""
import os
import csv
from collections import defaultdict
from azure.cosmos import CosmosClient
import sys
from collections import defaultdict
import string
from pathlib import Path

REQUIRED_COLUMNS = {'Title', 'Genre', 'Year'}
DATA_DIR = Path(__file__).parent / 'data'

def validate_csv(file_path):
    """Validate CSV has required columns"""
    try:
        with open(file_path, 'r') as f:
            reader = csv.reader(f)
            headers = [h.strip() for h in next(reader)]  # Get headers and strip whitespace
            
            # Check for required columns (case-insensitive)
            headers_lower = [h.lower() for h in headers]
            missing_columns = [col for col in REQUIRED_COLUMNS 
                             if col.lower() not in headers_lower]
            
            if missing_columns:
                print(f"Error: Missing required columns: {', '.join(missing_columns)}")
                print(f"Required columns are: {', '.join(REQUIRED_COLUMNS)}")
                return False, None
            
            # Create mapping of actual header names to required names
            header_mapping = {}
            for required_col in REQUIRED_COLUMNS:
                idx = headers_lower.index(required_col.lower())
                header_mapping[required_col] = headers[idx]
                
            return True, header_mapping
    except FileNotFoundError:
        print(f"Error: Could not find CSV file at {file_path}")
        return False, None
    except Exception as e:
        print(f"Error reading CSV: {str(e)}")
        return False, None

def find_csv_file():
    """Find first CSV file in data directory"""
    try:
        DATA_DIR.mkdir(exist_ok=True)  # Create data directory if it doesn't exist
        csv_files = list(DATA_DIR.glob('*.csv'))
        
        if not csv_files:
            print(f"No CSV files found in {DATA_DIR}")
            print("Please place a CSV file in the data directory with the following columns:")
            print(', '.join(REQUIRED_COLUMNS))
            return None
            
        if len(csv_files) > 1:
            print(f"Warning: Multiple CSV files found. Using {csv_files[0].name}")
            
        return csv_files[0]
    except Exception as e:
        print(f"Error accessing data directory: {str(e)}")
        return None

def group_movies_by_year_and_alpha(file_path, header_mapping):
    """Read CSV and group movies by year and first letter"""
    # Initialize years dictionary with letter groups for each year
    years = defaultdict(lambda: defaultdict(lambda: {"movies": []}))
    
    print(f"Reading CSV file from: {file_path}")
    
    try:
        with open(file_path, 'r', encoding='utf-8') as f:
            movies = csv.DictReader(f)
            for movie in movies:
                try:
                    # Extract and validate movie data
                    year = int(movie[header_mapping['Year']])
                    title = movie[header_mapping['Title']].strip()
                    genre = movie[header_mapping['Genre']].strip()
                    
                    if not all([year, title, genre]):  # Skip if any required field is empty
                        print(f"Skipping movie due to missing data: {movie}")
                        continue
                        
                    # Get the group for the title (first letter, num, or etc)
                    first_char = title[0].lower()
                    if first_char.isalpha():
                        group = first_char
                    elif first_char.isnumeric():
                        group = 'num'
                    else:
                        group = 'etc'
                    
                    # Create the movie data
                    movie_data = {
                        "title": title,
                        "genre": genre.capitalize(),
                        "year": year
                    }
                    
                    # Add to the appropriate group
                    years[year][group]["movies"].append(movie_data)
                    
                except (ValueError, KeyError) as e:
                    print(f"Warning: Skipping row due to invalid data: {movie}")
                    print(f"Error: {str(e)}")
                    continue
        
        print(f"Successfully processed CSV. Found {len(years)} unique years")
        return dict(years)  # Convert defaultdict to regular dict for serialization
            
    except Exception as e:
        print(f"Error processing CSV file: {str(e)}")
        import traceback
        print(f"Traceback: {traceback.format_exc()}")
        return {}

def clear_database(container):
    """
    Checks if data exists in the container and clears it if found.
    """
    try:
        print("Checking database contents...")
        
        # Query to check if any documents exist using a simpler query
        items = list(container.query_items(
            query="SELECT * FROM c",
            enable_cross_partition_query=True
        ))
        
        count = len(items)
        print(f"Found {count} documents in database")
        
        if count > 0:
            print(f"\nFound {count} existing documents in database.")
            print("Clearing database before seeding...")
            
            # Delete all documents
            for item in items:
                try:
                    print(f"Deleting document with id: {item['id']}")
                    container.delete_item(
                        item['id'],
                        partition_key=item['year']
                    )
                except Exception as e:
                    print(f"Error deleting document {item['id']}: {str(e)}")
                    return False
                    
            print(f"Successfully cleared {count} documents from database.")
        else:
            print("\nDatabase is empty. Proceeding with seeding...")
            
        return True
        
    except Exception as e:
        print(f"\nError in clear_database: {str(e)}")
        print(f"Error type: {type(e)}")
        import traceback
        print(f"Traceback: {traceback.format_exc()}")
        return False

def create_cosmos_documents():
    """Create and seed documents in Cosmos DB"""
    try:
        # Find CSV file
        csv_file = find_csv_file()
        if not csv_file:
            return
            
        # Validate CSV structure
        is_valid, header_mapping = validate_csv(csv_file)
        if not is_valid:
            return
        
        # Get and verify connection string
        connection_string = os.getenv("COSMOSDB_CONNECTION_STRING")
        if not connection_string:
            print("Error: COSMOSDB_CONNECTION_STRING environment variable is not set")
            return
        
        print(f"Connecting to Cosmos DB...")
        print(f"Connection string available: {bool(connection_string)}")
        
        # Initialize Cosmos client
        client = CosmosClient.from_connection_string(connection_string)
        database = client.get_database_client("moviedb")
        container = database.get_container_client("movies")
        
        print("Successfully connected to Cosmos DB")
        
        # Clear existing data
        if not clear_database(container):
            print("Failed to clear database. Aborting seeding process.")
            return
        
        # Group movies
        print("Reading and grouping movies from CSV...")
        years_data = group_movies_by_year_and_alpha(csv_file, header_mapping)
        
        # Create and upload documents
        print("\nBeginning document upload...")
        for year, data in years_data.items():
            document = {
                "id": f"year_{year}",
                "year": year,
                **data  # Spread the letter groups directly
            }
            
            try:
                container.upsert_item(document)
                print(f"Added document for year: {year}")
            except Exception as e:
                print(f"Error adding document for year {year}: {str(e)}")
                
        print("\nSeeding completed successfully!")
        
    except Exception as e:
        print(f"Error in create_cosmos_documents: {str(e)}")
        print(f"Error type: {type(e)}")
        import traceback
        print(f"Traceback: {traceback.format_exc()}")
        print("Please ensure COSMOSDB_CONNECTION_STRING environment variable is set correctly")

if __name__ == "__main__":
    create_cosmos_documents()