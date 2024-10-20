import ballerina/http;
import ballerina/io;
import ballerina/uuid;
import ballerinax/mongodb;
import ballerinax/pinecone.vector;
import ballerinax/azure.openai.embeddings;
import ballerina/jwt;
import JobGeniusApp.util;
import ballerina/crypto;
import ballerina/auth;




configurable string pineConeApiKey = ?;
configurable string pineCodeServiceUrl = ?;
configurable string AzureEmbeddingsApiKey = ?;
configurable string AzureEmbeddingsServiceUrl = ?;
configurable string mongodbConnectionUrl = ?;
configurable string secretKey = ?;



final vector:Client pineconeVectorClient = check new ({
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



listener http:Listener secureEDP = new(
    port=8080

);

http:FileUserStoreConfig config = {};
final http:ListenerFileUserStoreBasicAuthHandler handler = new (config);




service /api on secureEDP {
    private final mongodb:Database JobGeniusDb;

    

    function init() returns error? {
        string[] dbs = check mongoDb->listDatabaseNames();
        io:println(dbs);
        self.JobGeniusDb = check mongoDb->getDatabase("JobGeniusDb");
    }





    isolated resource function get jobs(
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

        return util:searchJobs(self.JobGeniusDb, filter);
    }

    isolated resource function post jobs(@http:Payload JobInput jobInput) returns Job|error {
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

        TextEmbeddingMetadata jobText = check util:generateTextForEmbeddings(job, embeddingsClient);

        check util:addVectorToPinecone([jobText], pineconeVectorClient);

        io:println(job);
        check jobs->insertOne(job);
        return job;
    }

    isolated  resource function get jobs/[string id]() returns Job|error {
        return util:getJob(self.JobGeniusDb, id);
    }

    isolated resource function put jobs/[string id](@http:Payload JobUpdate jobUpdate) returns Job|error {
        mongodb:Collection jobs = check self.JobGeniusDb->getCollection("Jobs");

        mongodb:UpdateResult updateResult = check jobs->updateOne({id}, {set: jobUpdate});
        if updateResult.modifiedCount != 1 {
            return error(string `Failed to update the job with id ${id}`);
        }
        return util:getJob(self.JobGeniusDb, id);
    }

    isolated resource function delete jobs/[string id]() returns vector:DeleteResponse|http:Ok|error {
        mongodb:Collection jobs = check self.JobGeniusDb->getCollection("Jobs");

        //delete from mongodb
        var deleteResult = check jobs->deleteOne({id: id});   

        //delete from pinecone 
        vector:DeleteResponse delVec = check util:deleteJobFromPinecone(id, pineconeVectorClient);
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

    isolated resource function post queryJobs(@http:Payload string text, @http:Header string Authorization) returns Job[]|error|http:Unauthorized|http:Forbidden {
        auth:UserDetails|http:Unauthorized authn = handler.authenticate(Authorization);
        if authn is http:Unauthorized {
            return authn;
        }
        http:Forbidden? authz = handler.authorize(<auth:UserDetails>authn, "admin");
        if authz is http:Forbidden {
            return authz;
        }
        return util:queryVectorDb(text, embeddingsClient, pineconeVectorClient);
    }



    resource function post login(@http:Payload LoginRequest loginrequest, @http:Header string Authorization) returns string|error? {

        auth:UserDetails|http:Unauthorized authn = handler.authenticate(Authorization);
        if authn is http:Unauthorized {
            return error("Unauthorized");
        }
        http:Forbidden? authz = handler.authorize(<auth:UserDetails>authn, ["company", "jobseeker"]);
        if authz is http:Forbidden {
            return error("Forbidden");
        }

    }
}

function jwtIssue(string username, string role) returns string|error {
    jwt:IssuerConfig issuerConfig = {
        username: username,
        issuer: "wso2",
        audience: "vEwzbcasJVQm1jVYHUHCjhxZ4tYa",
        expTime: 3600,
        signatureConfig: {
            config: {
                keyFile: "private.key"
            }
        }
    };

    return jwt:issue(issuerConfig);
}

function jwtVerify(string token) returns jwt:Payload|error {
    jwt:ValidatorConfig validatorConfig = {
        issuer: "wso2",
        audience: "vEwzbcasJVQm1jVYHUHCjhxZ4tYa",
        signatureConfig: {
            certFile: "public.cert"
        }
    };
    jwt:Payload result = check jwt:validate(token, validatorConfig);
    return result;
}

function passwordHash(string password) returns byte[]|error {
    string input = password;
    byte[] data = input.toBytes();
    string secret = secretKey;
    byte[] key = secret.toBytes();
    byte[] hmac = check crypto:hmacSha256(data, key);
    return hmac;
}

type userCredentials record {
    string username;
    string password;
};

function authenticate(string hash) returns userCredentials|error {
    [string, string] [username, password] = check auth:extractUsernameAndPassword(hash);
    userCredentials user = {
        username: username,
        password: password
    };
    return user;
}



