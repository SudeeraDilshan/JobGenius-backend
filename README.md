# JobGenius

JobGenius is an advanced job search platform that leverages cutting-edge AI technologies and Ballerina to provide personalized job recommendations and AI assistance for job seekers.

## Features

- **Manual Job Search**: Users can manually search for jobs based on various filters.
- **AI Assistance**: Chat with an AI to get personalized job recommendations.
- **User Login**: Secure user authentication and authorization.
- **Apply for Jobs**: Users can apply for jobs directly through the system.

## Key Components

- **[modules/util/util.bal](modules/util/util.bal)**: Contains utility functions for job management and AI integration.
- **[service.bal](service.bal)**: Defines the main service endpoints for job operations.

## Getting Started

1. **Clone the repository**:

    ```sh
    git clone <repository-url>
    cd JobGenius
    ```

2. **Build the project**:

    ```sh
    bal build
    ```

3. **Run the service**:

    ```sh
    bal run service.bal
    ```

3. **Add environment variables to `Config.toml`**:

    ```toml
    pineConeApiKey="${PINECONE_API_KEY}"
    pineCodeServiceUrl="${PINECONE_SERVICE_URL}"
    AzureEmbeddingsApiKey="${AZURE_EMBEDDINGS_API_KEY}"
    AzureEmbeddingsServiceUrl="${AZURE_EMBEDDINGS_SERVICE_URL}"
    mongodbConnectionUrl="${MONGODB_CONNECTION_URL}"
    secretKey="${SECRET_KEY}"

    [[ballerina.auth.users]]
    username="alice"
    password="${ALICE_PASSWORD}"
    scopes=["company"]

    [[ballerina.auth.users]]
    username="ldclakmal"
    password="${LDCLAKMAL_PASSWORD}"
    scopes=["company"]

    [[ballerina.auth.users]]
    username="eve"
    password="${EVE_PASSWORD}"
    scopes=["jobseeker"]

    [[ballerina.auth.users]]
    username="bob"
    password="${BOB_PASSWORD}"
    scopes=["jobseeker"]

    [[ballerina.auth.users]]
    username="admin"
    password="${ADMIN_PASSWORD}"
    scopes=["admin"]