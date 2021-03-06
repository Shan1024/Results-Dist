import ballerina/auth;
import ballerina/http;
import ballerina/log;
import ballerina/mime;
import ballerina/time;
import ballerina/xmlutils;
import ballerina/file;
import ballerina/websub;

const LEVEL_PD = "POLLING-DIVISION";
const LEVEL_ED = "ELECTORAL-DISTRICT";
const LEVEL_NI = "NATIONAL-INCREMENTAL";
const LEVEL_NF = "NATIONAL-FINAL";

# Show a website for media people to get a list of all released results with
# links to each json value and the image with the signed official document.
@http:ServiceConfig {
    basePath: "/"
}
service mediaWebsite on mediaListener {
    @http:ResourceConfig {
        path: "/",
        methods: ["GET"]
    }
    resource function showAll (http:Caller caller, http:Request req) returns error? {
        string head = "<head>";
        head += "<title>Sri Lanka Elections Commission</title>";
        head += "<link rel=\"stylesheet\" href=\"https://maxcdn.bootstrapcdn.com/bootstrap/3.4.0/css/bootstrap.min.css\">";
        head += "</head>";

        string body = "<body style='margin: 5%'>";
        body += "<div class='container-fluid'>";
        body = body + "<h1>Released Results Data for Media Partners</h1>";
        string tt = check time:format(time:currentTime(), "yyyy-MM-dd'T'HH:mm:ss.SSSZ");
        body += "<p>Current time: " + tt + "</p>";
        
        body += generateResultsTable(PRESIDENTIAL_PREFS_RESULT);
        body += generateResultsTable(PRESIDENTIAL_RESULT);
        body = body + "<p/>";
        body = body + "<p>All  results released so far as single JSON value: "
                    + "<a href='/allresults'>All Results</a>";
        body = body + "</div>";
        body = body + "</body>";
        string doc = "<html>" + head + body + "</html>";

        http:Response hr = new;
        hr.setPayload(doc);
        hr.setContentType(mime:TEXT_HTML);
        return caller->ok(hr);
    }

    resource function allresults (http:Caller caller, http:Request req) returns error? {
        json[] results = [];

        // return results in reverse order
        int i = resultsCache.length();
        while i > 0 { // show non-incremental results in reverse order of release
            i = i - 1;
            if resultsCache[i].jsonResult.level != "NATIONAL-INCREMENTAL" {
                results.push(resultsCache[i].jsonResult);
            }
        }
        return caller->ok(results);
    }

    @http:ResourceConfig {
        path: "/result/{election}/{seqNo}",
        methods: ["GET"]
    }
    resource function data (http:Caller caller, http:Request req, string election, int seqNo) returns error? {
        // what's the format they want? we'll default to json if they don't say or get messy
        string format = req.getQueryParamValue ("format") ?: "json";
        if format != "xml" && format != "json" && format != "html" {
            format = "json";
        }

        // find the result object and send it in the format they want
        foreach Result r in resultsCache {
            if r.election == election && r?.sequenceNo == seqNo {
                if format == "json" {
                    return caller->ok(r.jsonResult);
                } else if format == "html" {
                    http:Response hr = new;
                    boolean sorted = (r.jsonResult.level == LEVEL_NF) ? true : false;
                    hr.setTextPayload(<@untainted>check generateHtml(election, r.jsonResult, sorted));
                    hr.setContentType("text/html");
                    return caller->ok(hr);
                } else { // xml
                    // put the result json object into a wrapper object to get a parent element
                    // NOTE: this code must match the logic in the subscriber saving code as
                    // both add this object wrapper with the property named "result". Bit
                    // dangerous as someone can forget to change both together - hence this comment!
                    json j = { result: r.jsonResult };
                    return caller->ok(check xmlutils:fromJSON(j));
                }
            }
        }

        // bad request
        http:Response res = new;
        res.statusCode = http:STATUS_NOT_FOUND;
        return caller->respond(res);
    }

    @http:ResourceConfig {
        path: "/release/{election}/{seqNo}",
        methods: ["GET"]
    }
    resource function releaseDoc (http:Caller caller, http:Request req, string election, int seqNo) returns error? {
        http:Response hr = new;

        // find image of the release doc and return it (if its there - may not have appeared yet)
        foreach Result r in resultsCache {
            if r.election == election && r?.sequenceNo == seqNo {
                byte[]? imageData = r.imageData;
                string? imageMediaType = r.imageMediaType;

                if imageData is byte[] && imageMediaType is string {
                    hr.setBinaryPayload(imageData);
                    hr.setContentType(imageMediaType);
                    return caller->ok(hr);
                } else {
                    return caller->ok("No official release available (yet)");
                }
            }
        }

        // bad request
        http:Response res = new;
        res.statusCode = http:STATUS_NOT_FOUND;
        return caller->respond(res);
    }

    # Hook for subscriber to be sent some info to display. Can put some HTML content into 
    # web/info.html and it'll get shown at subscriber startup
    # + return - error if problem
    resource function info(http:Caller caller, http:Request request) returns error? {
        removeSubscriptionsForUsername(request);

        http:Response hr = new;
        hr.setFileAsPayload("web/info.txt", "text/plain");
        check caller->ok(hr);
    }

    # Hook for subscriber to check whether their version is still active. If version is active
    # then must have file web/active-{versionNo}. If its missing will return 404.
    # + return - error if problem
    @http:ResourceConfig {
        path: "/isactive/{versionNo}",
        methods: ["GET"]
    }
    resource function isactive(http:Caller caller, http:Request request, string versionNo) returns error? {
        if file:exists("web/active-" + <@untainted> versionNo) {
            return caller->ok("Still good");
        } else {
            http:Response hr = new;
            hr.statusCode = http:STATUS_NOT_FOUND;
            hr.setTextPayload("This version is no longer active; please upgrade (see status message).");
            return caller->respond(hr);
        }
    }

    @http:ResourceConfig {
        path: "/sms",
        methods: ["POST"],
        body: "smsRecipient",
        auth: {
            scopes: ["ECAdmin"]
        }
    }
    resource function smsRegistration (http:Caller caller, http:Request req, Recipient smsRecipient) returns error? {
        string|error validatedNo = validate(smsRecipient.mobile);
        if validatedNo is error {
            http:Response res = new;
            res.statusCode = http:STATUS_BAD_REQUEST;
            res.setPayload(<string> validatedNo.detail()?.message);
            return caller->respond(res);
        }

        // If the load is high, we might need to sync following db/map update
        string|error status = registerAsSMSRecipient(smsRecipient.username.trim(), <string> validatedNo);
        if status is error {
            http:Response res = new;
            res.statusCode = http:STATUS_INTERNAL_SERVER_ERROR;
            res.setPayload(<@untainted> <string> status.detail()?.message);
            return caller->respond(res);
        }
        return caller->ok(<@untainted> <string> status);
    }

    @http:ResourceConfig {
        path: "/sms",
        methods: ["DELETE"],
        body: "smsRecipient",
        auth: {
            scopes: ["ECAdmin"]
        }
    }
    resource function smsDeregistration (http:Caller caller, http:Request req, Recipient smsRecipient) returns error? {
        string|error validatedNo = validate(smsRecipient.mobile);
        if validatedNo is error {
            http:Response res = new;
            res.statusCode = http:STATUS_BAD_REQUEST;
            res.setPayload(<string> validatedNo.detail()?.message);
            return caller->respond(res);
        }

        // If the load is high, we might need to sync following db/map update
        string|error status = unregisterAsSMSRecipient(smsRecipient.username.trim(), <string> validatedNo);
        if status is error {
            http:Response res = new;
            res.statusCode = http:STATUS_INTERNAL_SERVER_ERROR;
            res.setPayload(<string> status.detail()?.message);
            return caller->respond(res);
        }
        return caller->ok(<string> status);
    }
}

# Print the results
# 
# + return - HTML string for results of the given type from the results cache
function generateResultsTable(string 'type) returns string {
    string tab = "";
    int i = resultsCache.length();
    boolean first = true;
    while i > 0 { // show results in reverse order of release
        i = i - 1;
        Result r = resultsCache[i];
        if r.'type != 'type {
            continue;
        }
        if first {
            first = false;
            match 'type {
                PRESIDENTIAL_RESULT => { tab = "<h2>First Preference Results</h2>"; }
                PRESIDENTIAL_PREFS_RESULT => { tab = "<h2>Revised Results with Second/Third Preferences</h2>"; }
            }
            tab += "<table class='table'><tr><th>Election</th><th>Sequence No</th><th>Release Time</th><th>Code</th><th>Level</th><th>Electoral District</th><th>Polling Division</th><th>JSON</th><th>XML</th><th>HTML</th><th>Document</th></tr>";
        }
        string election = r.election;
        string seqNo = r.jsonResult.sequence_number.toString();
        string timestamp = r.jsonResult.timestamp.toString();
        string code = "";
        string level = r.jsonResult.level.toString();
        // figure out and ED / PD name if needed
        string edName = "";
        string pdName = "";
        match level {
            LEVEL_PD => { 
                code = r.jsonResult.pd_code.toString(); //  has 2 digit ED code and 1 letter PD code
                edName = r.jsonResult.ed_name.toString();
                pdName = r.jsonResult.pd_name.toString();
            }
            LEVEL_ED => { 
                code = r.jsonResult.ed_code.toString();
                edName = r.jsonResult.ed_name.toString();
            }
            LEVEL_NI => { }
            LEVEL_NF => {
                code = r.code.toString();
            }
        }

        tab = tab + "<tr>" +
                    "<td>" + election + "</td>" +
                    "<td>" + seqNo + "</td>" +
                    "<td>" + timestamp + "</td>" +
                    "<td>" + code + "</td>" +
                    "<td>" + level + "</td>" +
                    "<td>" + edName + "</td>" +
                    "<td>" + pdName + "</td>" +
                    "<td><a href='/result/" + r.election + "/" + seqNo + "?format=json'>JSON</a>" + "</td>" +
                    "<td><a href='/result/" + r.election + "/" + seqNo + "?format=xml'>XML</a>" + "</td>" +
                    "<td><a href='/result/" + r.election + "/" + seqNo + "?format=html'>HTML</a>" + "</td>" +
                    "<td><a href='/release/" + r.election + "/" + seqNo + "'>Release</a>" + "</td>" +
                    "</tr>";
    }
    tab = tab + "</table>";
    return tab;
}

function removeSubscriptionsForUsername(http:Request request) {
    if (!request.hasHeader(http:AUTH_HEADER)) {
        return;
    }

    websub:Hub hubVar = <websub:Hub> hub;
    string headerValue = request.getHeader(http:AUTH_HEADER);
        
    if !(headerValue.startsWith(auth:AUTH_SCHEME_BASIC)) {
        return;
    }

    string credential = headerValue.substring(5, headerValue.length()).trim();

    var result = auth:extractUsernameAndPassword(credential);

    if (result is [string, string]) {
        [string, string][username, _] = result;
        
        removeSubscription(username, resultCallbackMap, JSON_TOPIC, hubVar);
        removeSubscription(username, imageCallbackMap, IMAGE_PDF_TOPIC, hubVar);
        removeSubscription(username, awaitResultsCallbackMap, AWAIT_RESULTS_TOPIC, hubVar);
    } else {
        log:printError("Error extracting credentials to remove subscription", result);
    }
}

function removeSubscription(string username, map<string> callbackMap, string topic, websub:Hub hub) {
    if !callbackMap.hasKey(username) {
        return;
    }

    string existingCallback = callbackMap.get(username);
    log:printInfo("Removing existing subscription callback: " + existingCallback + ", for username: " +
                    username + ", and topic: " + topic);
    error? remResult = hub.removeSubscription(topic, existingCallback);
    if (remResult is error) {
        log:printError("error removing existing subscription for username: " + username, remResult);
    }
    removeUserCallback(username, topic, existingCallback);
}
