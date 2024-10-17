import ballerina/http;
import ballerina/uuid;
import ballerinax/mongodb;
import ballerina/io;

// mongodb:Client mongoDb = check new ({
//     connection: {
//         serverAddress: {
//             host: "localhost",
//             port: 27017
//         }
//     // Uncomment and update the auth details if needed
//     // auth: {
//     //     username: "teamdacker",
//     //     password: "TeamDacker123",
//     //     database: "JobGeniusDb"
//     // }
//     }
// });

mongodb:ConnectionConfig mongoConfig = {
    connection: "mongodb+srv://janithravisankax:oId7hMtN4eME17ok@cluster0.k6xoa.mongodb.net/"
};

mongodb:Client mongoDb = check new (mongoConfig);

service /api on new http:Listener(9090) {
    private final mongodb:Database JobGeniusDb;

    function init() returns error? {
        string[] dbs = check mongoDb->listDatabaseNames();
        io:println(dbs);
        self.JobGeniusDb = check mongoDb->getDatabase("JobGeniusDb");
    }

    resource function get jobs(
        @http:Query string[]? category,
        @http:Query int? salary,
        @http:Query string[]? position,
        @http:Query string[]? engagement,
        @http:Query string[]? working_mode,
        @http:Query string[]? location,
        @http:Query string[]? company
    ) returns Job[]|error {
        Filter filter = {
            category: category==[""]?[]:category,
            salary: salary==()?0:salary,
            position: position==[""]?[]:position,
            engagement: engagement==[""]?[]:engagement,
            working_mode: working_mode==[""]?[]:working_mode,
            location: location==[""]?[]:location,
            company: company==[""]?[]:company
        };

        return searchJobs(self.JobGeniusDb, filter);
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
            // experience: "2 years",
            // keypoints: "Java, Spring Boot, Microservices"
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

isolated function searchJobs(mongodb:Database JobGeniusDb, Filter filter) returns Job[]|error{
    mongodb:Collection jobs = check JobGeniusDb->getCollection("Jobs");
    io:println(filter);
    stream<Job, error?> result = check jobs->find({
        position: filter.position==[]?{"$nin":[]}:{"$in":filter.position},
        category: filter.category==[]?{"$nin":[]}:{"$in":filter.category},
        engaement: filter.engagement==[]?{"$nin":[]}:{"$in":filter.engagement},
        working_mode: filter.working_mode==[]?{"$nin":[]}:{"$in":filter.working_mode},
        location: filter.location==[]?{"$nin":[]}:{"$in":filter.location},
        salary: filter.salary==()?{"$nin":[]}:{"$gt":filter.salary},
        company: filter.company==[]?{"$nin":[]}:{"$in":filter.company}
    });

    return from Job job in result
           select job;
}

