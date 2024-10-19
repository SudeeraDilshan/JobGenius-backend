import ballerina/http;
import ballerina/io;
import ballerina/uuid;
import ballerinax/mongodb;
import ballerinax/pinecone.vector;
import ballerinax/azure.openai.embeddings;


configurable string pineConeApiKey = ?;
configurable string pineCodeServiceUrl = ?;
configurable string AzureEmbeddingsApiKey = ?;
configurable string AzureEmbeddingsServiceUrl = ?;
configurable string mongodbConnectionUrl = ?;



vector:Client pineconeVectorClient = check new ({
    apiKey: pineConeApiKey
}, serviceUrl = pineCodeServiceUrl);

final embeddings:Client embeddingsClient = check new (
    config = {auth: {apiKey: AzureEmbeddingsApiKey}},
    serviceUrl = AzureEmbeddingsServiceUrl
);



mongodb:ConnectionConfig mongoConfig = {
    connection: mongodbConnectionUrl
};

mongodb:Client mongoDb = check new (mongoConfig);

@http:ServiceConfig {
    cors: {
        allowOrigins: ["http://localhost:5173"]
    }
}

service /api on new http:Listener(9090) {
    private final mongodb:Database JobGeniusDb;

    function init() returns error? {
        string[] dbs = check mongoDb->listDatabaseNames();
        io:println(dbs);
        self.JobGeniusDb = check mongoDb->getDatabase("JobGeniusDb");
    }

    resource function get jobs(
            @http:Query string[]? category = [],
            // @http:Query int? salary=0,
            @http:Query string[]? position = [],
            @http:Query string[]? engagement = [],
            @http:Query string[]? working_mode = [],
            @http:Query string? location = "",
            @http:Query string? company = ""
    ) returns Job[]|error {
        // io:println(filter)
        Filter filter = {
            category: category,
            // salary: salary,
            position: position,
            engagement: engagement,
            working_mode: working_mode,
            location: location,
            company: company
        };

        return searchJobs(self.JobGeniusDb, filter);
    }

    resource function post jobs(@http:Payload JobInput jobInput) returns Job|error {
        mongodb:Collection jobs = check self.JobGeniusDb->getCollection("Jobs");

        string id = uuid:createType1AsString();

        

        Job job = {
            id: id,
            position: jobInput.position,
            category: jobInput.category,
            engagement: jobInput.engagement,
            working_mode: jobInput.working_mode,
            location: jobInput.location,
            salary: jobInput.salary,
            description: jobInput.description,
            company: jobInput.company,
            experience: "2 years",
            keypoints: "Java, Spring Boot, Microservices"
        };

        TextEmbeddingMetadata jobText = check generateTextForEmbeddings(job);

        check addVectorToPinecone([jobText]);

        io:println(job);
        check jobs->insertOne(job);
        return job;
    }

    resource function get jobs/[string id]() returns Job|error {
        return getJob(self.JobGeniusDb, id);
    }

    resource function put jobs/[string id](@http:Payload JobUpdate jobUpdate) returns Job|error {
        mongodb:Collection jobs = check self.JobGeniusDb->getCollection("Jobs");

        mongodb:UpdateResult updateResult = check jobs->updateOne({id}, {set: jobUpdate});
        if updateResult.modifiedCount != 1 {
            return error(string `Failed to update the job with id ${id}`);
        }
        return getJob(self.JobGeniusDb, id);
    }

    resource function delete jobs/[string id]() returns vector:DeleteResponse|http:Ok|error {
        mongodb:Collection jobs = check self.JobGeniusDb->getCollection("Jobs");

        //delete from mongodb
        var deleteResult = check jobs->deleteOne({id: id});   

        //delete from pinecone 
        vector:DeleteResponse delVec = check deleteJobFromPinecone(id);
        if (deleteResult.deletedCount == 0) {
            return error("Failed to delete the job with id " + id);
        }

        return delVec;
    }

    resource function get getJobsByCompany(@http:Query string? company = "TechCore") returns json|error {
        mongodb:Collection jobs = check self.JobGeniusDb->getCollection("Jobs");

        stream<Job, error?> jobsStream = check jobs->find({company: company});
        json[] jobArray = [];

        check jobsStream.forEach(function(Job job) {
            jobArray.push(job);
        });

        check jobsStream.close();

        return jobArray;
    }

    resource function post queryJobs(@http:Payload string text) returns Job[]|error {
        return queryVectorDb(text);
    }

}

isolated function getJob(mongodb:Database JobGeniusDb, string id) returns Job|error {
    mongodb:Collection jobs = check JobGeniusDb->getCollection("Jobs");
    Job? result = check jobs->findOne({id: id});
    if result is () {
        return error("Failed to find a job with id " + id);
    }
    return result;
}

isolated function searchJobs(mongodb:Database JobGeniusDb, Filter filter) returns Job[]|error {
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
function queryVectorDb(string text) returns Job[]|error {
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

function deleteJobFromPinecone(string id) returns vector:DeleteResponse|error {
    vector:DeleteRequest deleteRequest = {
        ids:[id]
    };
    vector:DeleteResponse queryResponse = check pineconeVectorClient->/vectors/delete.post(deleteRequest);
    return queryResponse;
}

function addVectorToPinecone(TextEmbeddingMetadata[] vectorResult) returns error? {
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


isolated function getEmbeddings(string query) returns decimal[]|error {
    embeddings:Deploymentid_embeddings_body embeddingsBody = {
        input: query,
        model: "text-embedding-ada-002"
    };
    embeddings:Inline_response_200 embeddingsResult = check embeddingsClient->/deployments/["text-embedding-ada-002"]/embeddings.post("2023-05-15", embeddingsBody);
    return embeddingsResult.data[0].embedding;
}

// function queryByID(string id) returns string|error{
//     vector:QueryResponse queryResponse = check pineconeVectorClient->/query.post({"metadata": {id: id}, topK: 1, includeMetadata: true});
//     json[] data = check queryResponse.matches.toJson().ensureType();
//     string id2 = check data[0].metadata.id;
//     return id2;
// }

isolated function generateTextForEmbeddings(Job job) returns TextEmbeddingMetadata|error {

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
    
    decimal[] embeddings = check getEmbeddings(data.toString());
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

