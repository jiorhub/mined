module app;
import vibe.d;
import redmine;
import restclient;

import std.stdio: writeln;

class Application {
    private static final string USERNAME = "";
    private static final string PASSWORD = "";
    private static final int QUERY = 171;

    ExRestInterfaceClient!IRedmineAPI api;

    this(URLRouter router) {
        api = new ExRestInterfaceClient!IRedmineAPI("http://milofon.org/milofon/");
        api.requestFilter = delegate(HTTPClientRequest req) {
            addBasicAuth(req, USERNAME, PASSWORD);
        };
        initRoutes(router);
    }

    private void initRoutes(URLRouter router) {
        router.get("/", &index);
        router.get("/issues", &issues);
        router.get("/static/*", serveStaticFiles("./static/", new HTTPFileServerSettings("/static/")));
    }

    private void index(HTTPServerRequest req, HTTPServerResponse res) {
        auto projects = api.getProjects(100, 0).projects;
        res.renderCompat!("index.dt", HTTPServerRequest, "req", Project[], "projects")(req, projects);
    }

    private void issues(HTTPServerRequest req, HTTPServerResponse res) {
        auto issues = api.getIssues(20, 0, 171).issues;
        res.renderCompat!("issues.dt", HTTPServerRequest, "req", Issue[], "issues")(req, issues);
    }
}


shared static this() {
    setLogLevel(LogLevel.debug_);

    auto router = new URLRouter;
    auto app = new Application(router);
    auto settings = new HTTPServerSettings;
    settings.port = 8000;

    listenHTTP(settings, router);
}