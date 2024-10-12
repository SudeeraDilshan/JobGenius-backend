public type JobInput record {|
    string position;
    string category;
    string engagement;
    string working_mode;
    string location;
    string salary;
    string description;
    string company;    
|};

public type JobUpdate record {|
    string position?;
    string category?;
    string engagement?;
    string working_mode?;
    string location?;
    string salary?;
    string description?;
    string company?;  
|};

public type Job record {|
    readonly string id;
    string position;
    string category;
    string engagement;
    string working_mode;
    string location;
    string salary;
    string description;
    string company;
|};

public type Filter record {|
    string position?;
    string category?;
    string engagement?;
    string working_mode?;
    string location?;
    string salary?;
    string description?;
    string company?;
|};