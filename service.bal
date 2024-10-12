import ballerina/http;
import ballerina/uuid;
import ballerinax/mongodb;
import ballerina/io;


mongodb:ConnectionConfig mongoConfig = {
    connection: "mongodb+srv://janithravisankax:oId7hMtN4eME17ok@cluster0.k6xoa.mongodb.net/"
};

mongodb:Client mongoDb = check new (mongoConfig);


service /api on new http:Listener(9090) {
    private final mongodb:Database JobGeniusDb;

    function init() returns error? {
        
        string[] dbs = check mongoDb->listDatabaseNames();
        io:println("Available databases: ", dbs);
        
        self.JobGeniusDb = check mongoDb->getDatabase("JobGeniusDb");
    }

    resource function get jobs(@http:Query Filter? filter) returns Job[]|error {
        mongodb:Collection jobs = check self.JobGeniusDb->getCollection("Jobs");
        stream<Job, error?> result = check jobs->find();
        return from Job job in result
            select job;
    }

    resource function post jobs(@http:Payload JobInput jobInput) returns Job|error {
        mongodb:Collection jobs = check self.JobGeniusDb->getCollection("Jobs");
        Job job = {
            id: uuid:createType1AsString(),
            position: jobInput.position,
            category: jobInput.category,
            engagement: jobInput.engagement,
            working_mode: jobInput.working_mode,
            location: jobInput.location,
            salary: jobInput.salary,
            description: jobInput.description,
            company: jobInput.company
        };
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

    resource function delete jobs/[string id]() returns http:Ok|error {
        mongodb:Collection jobs = check self.JobGeniusDb->getCollection("Jobs");
        var deleteResult = check jobs->deleteOne({id: id});
        if (deleteResult.deletedCount == 0) {
            return error("Failed to delete the job with id " + id);
        }
        return http:OK;
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
