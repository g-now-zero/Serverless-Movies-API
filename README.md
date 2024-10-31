# Serverless-Movies-API

## Objective:
- Create an API with serverless functions that shows movie information.

## Planning steps:
### 1. Map out cloud infrastructure
Requirements:
- SDK to set up cloud infra
- NoSQL database, cloud storage and serverless functions
### 2. Data preparation
Requirements:
- Find movie data to be stored in the cloud NoSQL db
- Store movie cover images of each movie in cloud storage
### 3. Create serverless functions
- GetMovies: Returns a JSON list of all movies in db *response should have a url of the movie cover
- GetMoviesByYear: Returns a list of movies released in a specified year *year should be provided by client
- GetMovieSummary: Return a summary generated by AI for a specified movie.

## Infrastructure planning
**Cloud service provider**: *Azure*
- Considerations: Choosing due to familiarity and to take advantage of Student Account

**Azure Functions**: HTTP-triggered functions for the three end points
- Considerations: Pay-per-execution model which will work out well for resources

**Azure Cosmos DB**: NoSQL database for movie information

**Blob Storage**: cost-effective storage for storing the movie covers and each image gets a public url

**Azure OpenAI Service**: For the summary generation *which will connect to GetMovieSummary function

[Architecture diagram](/diagrams/architecture-diagram.png)

## Deployment Strategy
### Docker Container Setup
Container includes all necessary tools and data for deployment:
- Terraform (IaC)
- Azure CLI
- Project data (images and movie information)
- Deployment scripts

### Infrastructure as Code (Terraform)
Handles core Azure resource creation:
- Resource groups
- Cosmos DB account
- Blob Storage account
- Function Apps
- API Management service

## Data Structure Design
- Year-based documents with alphabetical subgrouping
```json
{
    "id": "<year>",
    "year": "<year>",
    "alphabetical": {
        "a": { "movies": ["title": "Nosferatu".
                          "genre": ""
                          "coverURL": "",
                          "generatedSummary": ""] },
        "b": { "movies": [] }
    }
}
```

#### Query flow
GetMovies:
-> Scan year documents, combine all alphabet sections

GetMoviesByYear:
-> Single document fetch by year

GetMovieSummary:
-> Year + alphabetical section lookup

## Deployment Strategy
**Azure CLI/Terraform docker container**: volume mounting if needed for any local file uploads



### TO-DO
- [X] Draw a diagram of the data flow through the chosen architecture
- [ ] Finish deployment strategy and upload subsequent diagram
- [ ] Find dataset
- [ ] Clean up dataset based on requirements
- [ ] Set up Azure infrastructure
    - [ ] Basic resources (Functions, Cosmos DB, Blob Storage)
- [ ] Implement db schema
- [ ] Create first endpoint