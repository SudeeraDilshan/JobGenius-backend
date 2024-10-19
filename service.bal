import ballerina/http;
import ballerina/io;
import ballerina/uuid;
import ballerinax/mongodb;

mongodb:ConnectionConfig mongoConfig = {
    connection: "mongodb+srv://janithravisankax:oId7hMtN4eME17ok@cluster0.k6xoa.mongodb.net/"
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
        Job job = {
            id: uuid:createType1AsString(),
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

    resource function delete jobs/[string id]() returns http:Ok|error {
        mongodb:Collection jobs = check self.JobGeniusDb->getCollection("Jobs");
        var deleteResult = check jobs->deleteOne({id: id});
        if (deleteResult.deletedCount == 0) {
            return error("Failed to delete the job with id " + id);
        }
        return http:OK;
    }

    resource function get getAllFields() returns string|error {
        mongodb:Collection jobs = check self.JobGeniusDb->getCollection("Jobs");

        stream<string, error?> positionsStream = check jobs->'distinct("category", {}, string);
        io:println(positionsStream);
        io:println("rrrrrrrrrr");
        string[] positions = check from var pos in positionsStream
            select pos;
        io:println(positions);

        // var val = positionsStream.next();
        // while (val is error?) {
        //     io:println("while loop");
        //     // io:println(val.value);
        //     val = positionsStream.next();
        // }
        // return from string val in positionsStream select val;
        return "hi";
        // stream<anydata, error?> categoriesStream = check jobs->'distinct("category", {}, anydata);
        // anydata[] categories = check from anydata cat in categoriesStream
        //     select cat;

        // stream<anydata, error?> engagementsStream = check jobs->'distinct("engagement", {}, anydata);
        // anydata[] engagements = check from anydata eng in engagementsStream
        //     select eng;

        // stream<anydata, error?> workingModesStream = check jobs->'distinct("working_mode", {}, anydata);
        // anydata[] workingModes = check from anydata mode in workingModesStream
        //     select mode;

        // stream<anydata, error?> locationsStream = check jobs->'distinct("location", {}, anydata);
        // anydata[] locations = check from anydata loc in locationsStream
        //     select loc;

        // stream<anydata, error?> companiesStream = check jobs->'distinct("company", {}, anydata);
        // anydata[] companies = check from anydata comp in companiesStream
        //     select comp;

        // json result = {
        //     positions: <json>positions
        //     // categories: <json>categories,
        //     // engagements: <json>engagements,
        //     // workingModes: <json>workingModes,
        //     // locations: <json>locations,
        //     // companies: <json>companies
        // };
        // io:println(result);
        // return result;
    }

    resource function get getJobsByCompany(@http:Query string? company = "TechCore") returns json|error {
        mongodb:Collection jobs = check self.JobGeniusDb->getCollection("Jobs");

        stream<Job, error?> jobsStream = check jobs->find({company: company});
        json[] jobArray = [];

        error? e = jobsStream.forEach(function(Job job) {
            jobArray.push(job);
        });

        check jobsStream.close();

        return jobArray;
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
        // salary: filter.salary==()?{"$ne":-1}:{"$gt":filter.salary},
        company: filter.company == "" ? {"$ne": -1} : {"$in": filter.company}
    });

    return from Job job in result
        select job;
}

