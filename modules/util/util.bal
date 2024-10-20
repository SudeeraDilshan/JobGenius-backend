import ballerina/io;
import ballerina/uuid;
import ballerinax/mongodb;
import ballerinax/pinecone.vector;
import ballerinax/azure.openai.embeddings;







public isolated  function getJob(mongodb:Database JobGeniusDb, string id) returns Job|error {
    mongodb:Collection jobs = check JobGeniusDb->getCollection("Jobs");
    Job? result = check jobs->findOne({id: id});
    if result is () {
        return error("Failed to find a job with id " + id);
    }
    return result;
}

public isolated function searchJobs(mongodb:Database JobGeniusDb, Filter filter) returns Job[]|error {
    mongodb:Collection jobs = check JobGeniusDb->getCollection("Jobs");
    io:println(filter);
    stream<Job, error?> result = check jobs->find({
        position: filter.position == [] ? {"$ne": -1} : {"$in": filter.position},
        category: filter.category == [] ? {"$ne": -1} : {"$in": filter.category},
        engagement: filter.engagement == [] ? {"$ne": -1} : {"$in": filter.engagement},
        working_mode: filter.working_mode == [] ? {"$ne": -1} : {"$in": filter.working_mode},
        location: filter.location == "" ? {"$ne": -1} : {"$eq": filter.location},
        company: filter.company == "" ? {"$ne": -1} : {"$eq": filter.company}
    });

    return from Job job in result
        select job;
}



// query the pinecone vector service
public isolated  function queryVectorDb(string text, embeddings:Client embeddingsClient, vector:Client pineconeVectorClient) returns Job[]|error {
    string question = text;

    embeddings:Deploymentid_embeddings_body embeddingsBody = {
        input: question,
        model: "text-embedding-ada-002"
    };
    embeddings:Inline_response_200 embeddingsResult = check embeddingsClient->/deployments/["text-embedding-ada-002"]/embeddings.post("2023-05-15", embeddingsBody);
        vector:VectorData  v = [];
    foreach decimal i in embeddingsResult.data[0].embedding{
        v.push(<float>i);
    }
    vector:QueryResponse queryResponse = check pineconeVectorClient->/query.post({vector: v, topK: 10, includeMetadata: true});

    json[] data = check queryResponse.matches.toJson().ensureType();

    Job[] jobs = [];
    foreach var item in data {
        json job = check item.metadata;
        jobs.push({
            id: check job.id,
            position: check job.position,
            category: check job.category,
            engagement: check job.engagement,
            working_mode: check job.working_mode,
            location: check job.location,
            salary: check job.salary,
            description: check job.description,
            company: check job.company,
            experience: check job.experience,
            keypoints: check job.keypoints
        });


        
    }

    return jobs;
}

public isolated  function deleteJobFromPinecone(string id, vector:Client pineconeVectorClient) returns vector:DeleteResponse|error {
    vector:DeleteRequest deleteRequest = {
        ids:[id]
    };
    vector:DeleteResponse queryResponse = check pineconeVectorClient->/vectors/delete.post(deleteRequest);
    return queryResponse;
}

public isolated  function addVectorToPinecone(TextEmbeddingMetadata[] vectorResult, vector:Client pineconeVectorClient) returns error? {
    vector:Vector[] vector = [];
    foreach var item in vectorResult {
        vector:VectorData v =  item.embeddings;
        vector:VectorMetadata metadata =  item.metadata;

        string uuid1String = uuid:createType1AsString();

        vector:Vector vectorData = {
            id: uuid1String,
            values: v,
            metadata: metadata
        };
        vector.push(vectorData);

    }
    vector:UpsertResponse queryResponse = check pineconeVectorClient->/vectors/upsert.post({vectors: vector});
    io:println(queryResponse);
}


public isolated  function getEmbeddings(string query, embeddings:Client embeddingsClient) returns decimal[]|error {
    embeddings:Deploymentid_embeddings_body embeddingsBody = {
        input: query,
        model: "text-embedding-ada-002"
    };
    embeddings:Inline_response_200 embeddingsResult = check embeddingsClient->/deployments/["text-embedding-ada-002"]/embeddings.post("2023-05-15", embeddingsBody);
    return embeddingsResult.data[0].embedding;
}


public isolated  function generateTextForEmbeddings(Job job, embeddings:Client embeddingsClient) returns TextEmbeddingMetadata|error {

    vector:VectorMetadata metadata ={
        "id": job.id,
        "position": job.position,
        "category": job.category,
        "engagement": job.engagement,
        "working_mode": job.working_mode,
        "location": job.location,
        "salary": job.salary,
        "description": job.description,
        "company": job.company,
        "experience": job.experience,
        "keypoints": job.keypoints

    };

    // data will be used to generate embeddings
    json data = {
        "position": job.position,
        "category": job.category,
        "engagement": job.engagement,
        "working_mode": job.working_mode,
        "location": job.location,
        "salary": job.salary,
        "description": job.description,
        "company": job.company,
        "experience": job.experience,
        "keypoints": job.keypoints
    };
    
    decimal[] embeddings = check getEmbeddings(data.toString(), embeddingsClient);
    float[] v = [];
    foreach decimal i in embeddings {
        v.push(<float>i);
    }
        
    TextEmbeddingMetadata textEmbeddingMetadata = {
        query: data.toString(),
        metadata: metadata,
        embeddings: v
    };
    
    // io:println(result);
    return textEmbeddingMetadata;


}

