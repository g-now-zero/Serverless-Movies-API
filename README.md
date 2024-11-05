# Serverless-Movies-API

A serverless Azure-based API that provides basic movie information, cover image and AI-generated summaries.

### Examples
![GetMovies Endpoint](/screenshots/getmovies.png)

![GetMovieSummary Endpoint](/screenshots/getmoviesummary.png)

## Objective
Create a scalable, serverless API that provides movie information using Azure Functions, with AI-powered movie summaries.

## Architecture Overview

![Deployment Diagram](/diagrams/deployment-diagram.png)

The deployment process is fully automated through Terraform and shell scripts, managing:
- Infrastructure provisioning
- Function deployment
- Data seeding
- Movie cover uploads
- API configuration

## Requirements

### Prerequisites
- Azure Subscription
- Docker
- [VS Code with Dev Containers extension](https://marketplace.visualstudio.com/items?itemName=ms-vscode-remote.remote-containers)
- OMDB API Key (Used to fetch movie cover images - get one [here](http://www.omdbapi.com/apikey.aspx))

### Data Requirements
The system expects a CSV file in `/scripts/data/` with the following required columns:
- `Title`: Movie title (i.e. "The Dark Knight")
- `Genre`: Movie genre (i.e. "Action")
- `Year`: Release year (i.e. 2008)

An example movies.csv is provided in the repository with these columns. Additional columns in your CSV will be ignored.

Data workflow:
1. CSV data is processed and stored in Cosmos DB
2. Movie covers are fetched from OMDB API
3. Covers are stored in Blob Storage
4. The movie record is updated with the cover URL

## How To

### Development Setup

1. **Clone and Open Project**
   ```bash
   git clone https://github.com/g-now-zero/Serverless-Movies-API
   cd Serverless-Movies-API
   code .
   ```

2. **Start Dev Container**
   When VS Code opens:
   - Click the popup to "Reopen in Container", or
   - Press F1 and select "Dev Containers: Reopen in Container"
   
   The Dev Container will automatically set up your development environment.


### Deployment

**Deploy Infrastructure and Application**
   ```bash
   cd terraform
   ./deploy.sh
   ```

   Follow the prompts. 
   The deploy script handles everything:
   - Infrastructure provisioning (yes, Cosmos DB takes up to 12 min to deploy)
   - Application deployment
   - Data seeding from your CSV
   - Movie cover fetching from OMDB
   - API configuration

### Testing

Test the deployed API:
```bash
cd terraform
./testapim.sh
```

### Cleanup

Remove all Azure resources:
```bash
cd terraform
./cleanup.sh
```

## API Endpoints

The API provides three main endpoints:
- `GET /api/getmovies` - Returns all movies with their metadata and cover URLs
- `GET /api/getmoviesbyyear?year={year}` - Returns movies from a specific year
- `GET /api/getmoviesummary?title={title}` - Returns an AI-generated summary for a movie

### Data Structure
```json
{
    "id": "year_2008",
    "year": 2008,
    "t": {
        "movies": [
            {
                "title": "The Dark Knight",
                "genre": "Action",
                "year": 2008,
                "coverURL": "https://..."
            }
        ]
    }
}
```
