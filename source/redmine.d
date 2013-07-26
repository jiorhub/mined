module redmine;

import vibe.http.rest;

template RedmineListResult() {
    int offset;
    int limit;
    int total_count;
}


struct Project {
    int id;
    string description;
    string name;
    string created_on;
    string updated_on;
    string identifier;
}

struct Status {
    int id;
    string name;
}

struct Author {
    int id;
    string name;
}

struct Tracker {
    int id;
    string name;
}

struct Issue {
    string description;
    Status status;
    string created_on;
    Author author;
    Tracker tracker;
    string subject;
}



struct  ProjectListResult{
    mixin RedmineListResult;
    Project[] projects;
}


struct ProjectResult {
    Project project;
}


struct  IssueListResult{
    mixin RedmineListResult;
    Issue[] issues;
}


interface IRedmineAPI {
    @path("projects.json")
    ProjectListResult getProjects(int limit, int offset);

    @path("projects/:id.json")
    ProjectResult getProject(int _id);

    @path("issues.json")
    IssueListResult getIssues(int limit, int offset, int query_id);
}
