module restclient;

import vibe.http.rest;
import vibe.http.restutil;

import vibe.core.log;
import vibe.data.json;
import vibe.http.client;
import vibe.http.router;
import vibe.inet.url;
import vibe.textfilter.urlencode;
import vibe.utils.string;

import std.algorithm : filter;
import std.array;
import std.conv;
import std.exception;
import std.string;
import std.traits;

import std.stdio: writeln;


class ExRestInterfaceClient(I) : I
{
    //pragma(msg, "imports for "~I.stringof~":");
    //pragma(msg, generateModuleImports!(I)());
    mixin(generateModuleImports!I());

    alias void delegate(HTTPClientRequest req) RequestFilter;
    private {
        URL m_baseURL;
        MethodStyle m_methodStyle;
        RequestFilter m_requestFilter;
    }

    alias I BaseInterface;

    /** Creates a new REST implementation of I
    */
    this(string base_url, MethodStyle style = MethodStyle.lowerUnderscored)
    {
        enum uda = extractUda!(RootPath, I);
        static if (is(typeof(uda) == typeof(null)))
            m_baseURL = URL.parse(base_url);
        else
        {
            static if (uda.data == "")
                m_baseURL = URL.parse(base_url ~ "/" ~ adjustMethodStyle(I.stringof, style) ~ "/");
            else
            {
                auto path = uda.data;
                if (!path.startsWith("/"))
                    path = "/" ~ path;
                if (!path.endsWith("/"))
                    path = path ~ "/";
                m_baseURL = URL.parse(base_url ~ adjustMethodStyle(uda.data, style));
            }
        }
        m_methodStyle = style;
        mixin(generateRestInterfaceSubInterfaceInstances!I());
    }
    /// ditto
    this(URL base_url, MethodStyle style = MethodStyle.lowerUnderscored)
    {
        m_baseURL = base_url;
        m_methodStyle = style;
        mixin(generateRestInterfaceSubInterfaceInstances!I());
    }

    /** An optional request filter that allows to modify each request before it is made.
    */
    @property RequestFilter requestFilter() { return m_requestFilter; }
    /// ditto
    @property void requestFilter(RequestFilter v) {
        m_requestFilter = v;
        mixin(generateRestInterfaceSubInterfaceRequestFilter!I());
    }

    //pragma(msg, generateRestInterfaceSubInterfaces!(I)());
#line 1 "subinterfaces"
    mixin(generateRestInterfaceSubInterfaces!I());

    //pragma(msg, "restinterface:");
    //pragma(msg, generateRestInterfaceMethods!(I)());
#line 1 "restinterface"
    mixin(generateRestInterfaceMethods!I());

#line 307 "source/vibe/http/rest.d"
static assert(__LINE__ == 307);
    protected Json request(string verb, string name, Json params, bool[string] paramIsJson)
    const {
        URL url = m_baseURL;
        if( name.length ) url ~= Path(name);
        else if( !url.path.endsWithSlash ){
            auto p = url.path;
            p.endsWithSlash = true;
            url.path = p;
        }

        if( (verb == "GET" || verb == "HEAD") && params.length > 0 ){
            auto queryString = appender!string();
            bool first = true;
            foreach( string pname, p; params ){
                if( !first ) queryString.put('&');
                else first = false;
                filterURLEncode(queryString, pname);
                queryString.put('=');
                filterURLEncode(queryString, paramIsJson[pname] ? p.toString() : toRestString(p));
            }
            url.queryString = queryString.data();
        }

        Json ret;

        requestHTTP(url,
            (scope req){
                req.method = httpMethodFromString(verb);
                if( m_requestFilter ) m_requestFilter(req);
                if( verb != "GET" && verb != "HEAD" )
                    req.writeJsonBody(params);
            },
            (scope res){
                logDebug("REST call: %s %s -> %d, %s", verb, url.toString(), res.statusCode, ret.toString());
                ret = res.readJson();
                if( res.statusCode != HTTPStatus.OK ){
                    if( ret.type == Json.Type.Object && ret.statusMessage.type == Json.Type.String )
                        throw new HTTPStatusException(res.statusCode, ret.statusMessage.get!string);
                    else throw new HTTPStatusException(res.statusCode, httpStatusText(res.statusCode));
                }
            }
        );

        return ret;
    }
}


/// private
private HTTPServerRequestDelegate jsonMethodHandler(T, string method, alias Func)(T inst)
{
    alias ParameterTypeTuple!Func ParameterTypes;
    alias ReturnType!Func RetType;
    alias ParameterDefaultValueTuple!Func DefaultValues;
    enum paramNames = [ParameterIdentifierTuple!Func];

    void handler(HTTPServerRequest req, HTTPServerResponse res)
    {
        ParameterTypes params;

        foreach( i, P; ParameterTypes ){
            static assert(paramNames[i].length, "Parameter "~i.stringof~" of "~method~" has no name");
            static if( i == 0 && paramNames[i] == "id" ){
                logDebug("id %s", req.params["id"]);
                params[i] = fromRestString!P(req.params["id"]);
            } else static if( paramNames[i].startsWith("_") ){
                static if( paramNames[i] != "_dummy"){
                    enforce(paramNames[i][1 .. $] in req.params, "req.param[\""~paramNames[i][1 .. $]~"\"] was not set!");
                    logDebug("param %s %s", paramNames[i], req.params[paramNames[i][1 .. $]]);
                    params[i] = fromRestString!P(req.params[paramNames[i][1 .. $]]);
                }
            } else {
                alias DefaultValues[i] DefVal;
                if( req.method == HTTPMethod.GET ){
                    logDebug("query %s of %s" ,paramNames[i], req.query);
                    static if( is(DefVal == void) ){
                        enforce(paramNames[i] in req.query, "Missing query parameter '"~paramNames[i]~"'");
                    } else {
                        if( paramNames[i] !in req.query ){
                            params[i] = DefVal;
                            continue;
                        }
                    }
                    params[i] = fromRestString!P(req.query[paramNames[i]]);
                } else {
                    logDebug("%s %s", method, paramNames[i]);
                    enforce(req.contentType == "application/json", "The Content-Type header needs to be set to application/json.");
                    enforce(req.json.type != Json.Type.Undefined, "The request body does not contain a valid JSON value.");
                    enforce(req.json.type == Json.Type.Object, "The request body must contain a JSON object with an entry for each parameter.");
                    static if( is(DefVal == void) ){
                        enforce(req.json[paramNames[i]].type != Json.Type.Undefined, "Missing parameter "~paramNames[i]~".");
                    } else {
                        if( req.json[paramNames[i]].type == Json.Type.Undefined ){
                            params[i] = DefVal;
                            continue;
                        }
                    }
                    params[i] = deserializeJson!P(req.json[paramNames[i]]);
                }
            }
        }

        try {
            static if( is(RetType == void) ){
                __traits(getMember, inst, method)(params);
                res.writeJsonBody(Json.emptyObject);
            } else {
                auto ret = __traits(getMember, inst, method)(params);
                res.writeJsonBody(serializeToJson(ret));
            }
        } catch( HTTPStatusException e) {
            res.writeJsonBody(["statusMessage": e.msg], e.status);
        } catch( Exception e ){
            // TODO: better error description!
            res.writeJsonBody(["statusMessage": e.msg, "statusDebugMessage": sanitizeUTF8(cast(ubyte[])e.toString())], HTTPStatus.internalServerError);
        }
    }

    return &handler;
}

/// private
private string generateRestInterfaceSubInterfaces(I)()
{
    if (!__ctfe)
        assert(false);

    string ret;
    string[] tps;
    foreach( method; __traits(allMembers, I) ){
        foreach( overload; MemberFunctionsTuple!(I, method) ){
            alias FunctionTypeOf!overload FT;
            alias ParameterTypeTuple!FT PTypes;
            alias ReturnType!FT RT;
            static if( is(RT == interface) ){
                static assert(PTypes.length == 0, "Interface getters may not have parameters.");
                if (!tps.canFind(RT.stringof)) {
                    tps ~= RT.stringof;
                    string implname = RT.stringof~"Impl";
                    ret ~= format(
                        q{alias RestInterfaceClient!(%s) %s;},
                        fullyQualifiedName!RT,
                        implname
                    );
                    ret ~= "\n";
                    ret ~= format(
                        q{private %s m_%s;},
                        implname,
                        implname
                    );
                    ret ~= "\n";
                }
            }
        }
    }
    return ret;
}

/// private
private string generateRestInterfaceSubInterfaceInstances(I)()
{
    if (!__ctfe)
        assert(false);

    string ret;
    string[] tps;
    foreach( method; __traits(allMembers, I) ){
        foreach( overload; MemberFunctionsTuple!(I, method) ){
            alias FunctionTypeOf!overload FT;
            alias ParameterTypeTuple!FT PTypes;
            alias ReturnType!FT RT;
            static if( is(RT == interface) ){
                static assert(PTypes.length == 0, "Interface getters may not have parameters.");
                if (!tps.canFind(RT.stringof)) {
                    tps ~= RT.stringof;
                    string implname = RT.stringof~"Impl";

                    enum meta = extractHTTPMethodAndName!overload();
                    bool pathOverriden = meta[0];
                    HTTPMethod http_verb = meta[1];
                    string url = meta[2];

                    ret ~= format(
                        q{
                            if (%s)
                                m_%s = new %s(m_baseURL.toString() ~ PathEntry("%s").toString(), m_methodStyle);
                            else
                                m_%s = new %s(m_baseURL.toString() ~ adjustMethodStyle(PathEntry("%s").toString(), m_methodStyle), m_methodStyle);
                        },
                        pathOverriden,
                        implname, implname, url,
                        implname, implname, url
                    );
                    ret ~= "\n";
                }
            }
        }
    }
    return ret;
}

/// private
private string generateRestInterfaceSubInterfaceRequestFilter(I)()
{
    if (!__ctfe)
        assert(false);

    string ret;
    string[] tps;
    foreach( method; __traits(allMembers, I) ){
        foreach( overload; MemberFunctionsTuple!(I, method) ){
            alias FunctionTypeOf!overload FT;
            alias ParameterTypeTuple!FT PTypes;
            alias ReturnType!FT RT;
            static if( is(RT == interface) ){
                static assert(PTypes.length == 0, "Interface getters may not have parameters.");
                if (!tps.canFind(RT.stringof)) {
                    tps ~= RT.stringof;
                    string implname = RT.stringof~"Impl";

                    ret ~= format(
                        q{m_%s.requestFilter = m_requestFilter;},
                        implname
                    );
                    ret ~= "\n";
                }
            }
        }
    }
    return ret;
}

/// private
private string generateRestInterfaceMethods(I)()
{
    if (!__ctfe)
        assert(false);

    string ret;
    foreach( method; __traits(allMembers, I) ){
        foreach( overload; MemberFunctionsTuple!(I, method) ){
            alias FunctionTypeOf!overload FT;
            alias ReturnType!FT RT;
            alias ParameterTypeTuple!overload PTypes;
            alias ParameterIdentifierTuple!overload ParamNames;

            enum meta = extractHTTPMethodAndName!(overload)();
            enum pathOverriden = meta[0];
            HTTPMethod httpVerb = meta[1];
            string url = meta[2];

            // NB: block formatting is coded in dependency order, not in 1-to-1 code flow order

            static if( is(RT == interface) ){
                ret ~= format(
                    q{
                        override %s {
                            return m_%sImpl;
                        }
                    },
                    cloneFunction!overload,
                    RT.stringof
                );
            } else {
                string paramHandlingStr;
                string urlPrefix = `""`;

                // Block 2
                foreach( i, PT; PTypes ){
                    static assert(ParamNames[i].length, format("Parameter %s of %s has no name.", i, method));

                    // legacy :id special case, left for backwards-compatibility reasons
                    static if( i == 0 && ParamNames[0] == "id" ){
                        static if( is(PT == Json) )
                            urlPrefix = q{urlEncode(id.toString())~"/"};
                        else
                            urlPrefix = q{urlEncode(toRestString(serializeToJson(id)))~"/"};
                    }
                    else static if( !ParamNames[i].startsWith("_") ){
                        // underscore parameters are sourced from the HTTPServerRequest.params map or from url itself
                        paramHandlingStr ~= format(
                            q{
                                jparams__["%s"] = serializeToJson(%s);
                                jparamsj__["%s"] = %s;
                            },
                            ParamNames[i],
                            ParamNames[i],
                            ParamNames[i],
                            is(PT == Json) ? "true" : "false"
                        );
                    }
                }

                // Block 3
                string requestStr;

                static if( !pathOverriden ){
                    requestStr = format(
                        q{
                            url__ = %s ~ adjustMethodStyle(url__, m_methodStyle);
                        },
                        urlPrefix
                    );
                } else {
                    auto parts = url.split("/");
                    requestStr ~= `url__ = ""`;
                    foreach (i, p; parts) {
                        if (i > 0) requestStr ~= `~"/"`;
                        bool match = false;
                        if( p.startsWith(":") ){
                            foreach (pn; ParamNames) {
                                if (pn.startsWith("_") && p[1 .. pn.length] == pn[1 .. $]) {
                                    requestStr ~= `~urlEncode(toRestString(serializeToJson(`~pn~`)))`;
                                    requestStr ~= `~"`~ p[pn.length..$] ~ `"`;
                                    match = true;
                                    break;
                                }
                            }
                        }
                        if (!match) requestStr ~= `~"`~p~`"`;
                    }

                    requestStr ~= ";\n";
                }

                requestStr ~= format(
                    q{
                        auto jret__ = request("%s", url__ , jparams__, jparamsj__);
                    },
                    httpMethodString(httpVerb)
                );

                static if (!is(ReturnType!overload == void)){
                    requestStr ~= q{
                        typeof(return) ret__;
                        deserializeJson(ret__, jret__);
                        return ret__;
                    };
                }

                // Block 1
                ret ~= format(
                    q{
                        override %s {
                            Json jparams__ = Json.emptyObject;
                            bool[string] jparamsj__;
                            string url__ = "%s";
                            %s
                                %s
                        }
                    },
                    cloneFunction!overload,
                    url,
                    paramHandlingStr,
                    requestStr
                );
            }
        }
    }

    return ret;
}

private string toRestString(Json value)
{
    switch( value.type ){
        default: return value.toString();
        case Json.Type.Bool: return value.get!bool ? "true" : "false";
        case Json.Type.Int: return to!string(value.get!long);
        case Json.Type.Float: return to!string(value.get!double);
        case Json.Type.String: return value.get!string;
    }
}

private T fromRestString(T)(string value)
{
    static if( is(T == bool) ) return value == "true";
    else static if( is(T : int) ) return to!T(value);
    else static if( is(T : double) ) return to!T(value); // FIXME: formattedWrite(dst, "%.16g", json.get!double);
    else static if( is(T : string) ) return value;
    else static if( __traits(compiles, T.fromString("hello")) ) return T.fromString(value);
    else return deserializeJson!T(parseJson(value));
}

private string generateModuleImports(I)()
{
    if( !__ctfe )
        assert(false);
    auto modules = getRequiredImports!I();
    import std.algorithm;
    return join(map!(a => "static import " ~ a ~ ";")(modules), "\n");
}


private Tuple!(bool, HTTPMethod, string) extractHTTPMethodAndName(alias Func)()
{
    if (!__ctfe)
        assert(false);

    immutable httpMethodPrefixes = [
        HTTPMethod.GET    : [ "get", "query" ],
        HTTPMethod.PUT    : [ "put", "set" ],
        HTTPMethod.PATCH  : [ "update", "patch" ],
        HTTPMethod.POST   : [ "add", "create", "post" ],
        HTTPMethod.DELETE : [ "remove", "erase", "delete" ],
    ];

    string name = __traits(identifier, Func);
    alias typeof(&Func) T;

    Nullable!HTTPMethod udmethod;
    Nullable!string udurl;

    // Cases may conflict and are listed in order of priority

    // Workaround for Nullable incompetence
    enum uda1 = extractUda!(vibe.http.rest.OverridenMethod, Func);
    enum uda2 = extractUda!(vibe.http.rest.OverridenPath, Func);

    static if (!is(typeof(uda1) == typeof(null)))
        udmethod = uda1;
    static if (!is(typeof(uda2) == typeof(null)))
        udurl = uda2;

    // Everything is overriden, no further analysis needed
    if (!udmethod.isNull() && !udurl.isNull())
        return tuple(true, udmethod.get(), udurl.get());

    // Anti-copy-paste delegate
    typeof(return) udaOverride( HTTPMethod method, string url ){
        return tuple(
            !udurl.isNull(),
            udmethod.isNull() ? method : udmethod.get(),
            udurl.isNull() ? url : udurl.get()
        );
    }

    if (isPropertyGetter!T)
        return udaOverride(HTTPMethod.GET, name);
    else if(isPropertySetter!T)
        return udaOverride(HTTPMethod.PUT, name);
    else {
        foreach( method, prefixes; httpMethodPrefixes ){
            foreach (prefix; prefixes){
                if( name.startsWith(prefix) ){
                    string tmp = name[prefix.length..$];
                    return udaOverride(method, tmp);
                }
            }
        }

        if (name == "index")
            return udaOverride(HTTPMethod.GET, "");
        else
            return udaOverride(HTTPMethod.POST, name);
    }
}

