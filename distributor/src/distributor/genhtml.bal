import ballerina/time;
import ballerina/math;
import ballerina/lang.'string;

map<string> electionCode2Name = {
    "2019PRE": "PRESIDENTIAL ELECTION - NOVEMBER 16, 2019",
    "2015-PRE-REPLAY-000": "PRESIDENTIAL ELECTION - 08/01/2015 RESULT REPLAY",
    "2015-PRE-REPLAY-001": "PRESIDENTIAL ELECTION - 08/01/2015 RESULT REPLAY",
    "2015-PRE-REPLAY-002": "PRESIDENTIAL ELECTION - 08/01/2015 RESULT REPLAY",
    "2015-PRE-REPLAY-003": "PRESIDENTIAL ELECTION - 08/01/2015 RESULT REPLAY",
    "2015-PRE-REPLAY-004": "PRESIDENTIAL ELECTION - 08/01/2015 RESULT REPLAY",
    "2015-PRE-REPLAY-005": "PRESIDENTIAL ELECTION - 08/01/2015 RESULT REPLAY",
    "2015-PRE-REPLAY-006": "PRESIDENTIAL ELECTION - 08/01/2015 RESULT REPLAY",
    "2015-PRE-REPLAY-007": "PRESIDENTIAL ELECTION - 08/01/2015 RESULT REPLAY",
    "2015-PRE-REPLAY-008": "PRESIDENTIAL ELECTION - 08/01/2015 RESULT REPLAY",
    "2015-PRE-REPLAY-009": "PRESIDENTIAL ELECTION - 08/01/2015 RESULT REPLAY",
    "2015-PRE-REPLAY-010": "PRESIDENTIAL ELECTION - 08/01/2015 RESULT REPLAY",
    "2015-PRE-REPLAY-011": "PRESIDENTIAL ELECTION - 08/01/2015 RESULT REPLAY",
    "2015-PRE-REPLAY-012": "PRESIDENTIAL ELECTION - 08/01/2015 RESULT REPLAY",
    "2015-PRE-REPLAY-013": "PRESIDENTIAL ELECTION - 08/01/2015 RESULT REPLAY",
    "2015-PRE-REPLAY-014": "PRESIDENTIAL ELECTION - 08/01/2015 RESULT REPLAY",
    "2015-PRE-REPLAY-015": "PRESIDENTIAL ELECTION - 08/01/2015 RESULT REPLAY"
};

function generateHtml (string electionCode, map<json> result, boolean sorted) returns string|error {
    boolean firstRound = (result.'type == PRESIDENTIAL_RESULT);
    string electionName = electionCode2Name[electionCode] ?: ("Presidential Election - " + electionCode);
    electionName +=  firstRound ? " (FIRST PREFERENCES)" : " (REVISED WITH 2nd/3rd PREFERENCES)";

    string timeNow = check time:format(time:currentTime(), "yyyy-MM-dd'T'HH:mm:ss.SSSZ");

    string head = "<head>";
    head += "<title>Sri Lanka Elections Commission</title>";
    head += "<link rel=\"stylesheet\" href=\"https://maxcdn.bootstrapcdn.com/bootstrap/3.4.0/css/bootstrap.min.css\">";
    head += "</head>";
    string body = "<body style='margin: 5%'>";
    body += "<div class='container-fluid'>";
    body += "<h1>" + electionName + "</h1>";

    string resultType = "";
    match <string>result.level {
        LEVEL_PD => { resultType = <string>result.ed_name + " ELECTORAL DISTRICT, " + <string>result.pd_name + " POLLING DIVISION (" + 
                                   <string>result.pd_code + ") RESULT"; }
        LEVEL_ED => { resultType = <string>result.ed_name + " ELECTORAL DISTRICT RESULT"; }
        LEVEL_NI => { resultType =  "CUMULATIVE RESULTS AT " + <string>result.timestamp; }
        LEVEL_NF => { resultType = "ALL ISLAND RESULT"; }
    }
    body += "<p>" + resultType.toUpperAscii() + "</p>";
    body += "<p>Votes received by each candidate" + (sorted ? ", sorted highest to lowest" : "") + "</p>";

    if firstRound {
        body += "<table class='table'><tr><th>Name of Candidate</th><th class='text-center'>Party Abbreviaton</th><th class='text-right'>Votes Received</th><th class='text-right'>Percentage</th></tr>";
    } else {
        body += "<table class='table'><tr><th>Name of Candidate</th><th class='text-center'>Party Abbreviaton</th><th class='text-right'>1st Preferences</th><th class='text-right'>2nd Preferences</th><th class='text-right'>3rd Preferences</th><th class='text-right'>Total Votes Received</th><th class='text-right'>Percentage</th></tr>";
    }
    json[] partyResults = sorted ? sortPartyResults(<json[]>result.by_party) : <json[]>result.by_party;
    foreach json j in partyResults {
        map<json> pr = <map<json>> j; // value is a json object
        if firstRound {
            body += "<tr><td>" + <string>pr.candidate + "</td><td class='text-center'>" + <string>pr.party_code + "</td><td class='text-right'>" + commaFormatInt(<int>pr.votes) + "</td><td class='text-right'>" + <string>pr.percentage + "%</td></tr>";
        } else {
            body += "<tr><td>" + <string>pr.candidate + "</td><td class='text-center'>" + <string>pr.party_code 
                               + "</td><td class='text-right'>" + commaFormatInt(<int>pr.votes1st) 
                               + "</td><td class='text-right'>" + commaFormatInt(<int>pr.votes2nd) 
                               + "</td><td class='text-right'>" + commaFormatInt(<int>pr.votes3rd) 
                               + "</td><td class='text-right'>" + commaFormatInt(<int>pr.votes) 
                               + "</td><td class='text-right'>" + <string>pr.percentage + "%</td></tr>";
        }
    }
    body += "</table>";
    body += "</div>";

    body += "<div class='container-fluid'>";
    body += "  <div class='col-md-4 col-md-offset-2'>Total Valid Votes</div>" + 
            "    <div class='col-md-2 text-right'>" + commaFormatInt(<int>result.summary.valid) + 
            "    </div><div class='col-md-2 text-right'>" + <string>result.summary.percent_valid + "%</div><div class='col-md-2'></div>";
    body += "  <div class='col-md-4 col-md-offset-2'>Rejected Votes</div>" + 
            "    <div class='col-md-2 text-right'>" + commaFormatInt(<int>result.summary.rejected) + 
            "    </div><div class='col-md-2 text-right'>" + <string>result.summary.percent_rejected + "%</div><div class='col-md-2'></div>";
    body += "  <div class='col-md-4 col-md-offset-2'>Total Polled</div>" + 
            "    <div class='col-md-2 text-right'>" + commaFormatInt(<int>result.summary.polled) + 
            "    </div><div class='col-md-2 text-right'>" + <string>result.summary.percent_polled + "%</div><div class='col-md-2'></div>";
    body += "  <div class='col-md-4 col-md-offset-2'>Registered No. of Electors</div>" + 
            "    <div class='col-md-2 text-right'>" + commaFormatInt(<int>result.summary.electors) + 
            "    </div><div class='col-md-2'></div>";
    body += "</div>";
    body += "</body>";
    return "<html>" + head + body + "</html>";
}

function sortPartyResults (json[] unsorted) returns json[] {
    return unsorted.sort(function (json r1, json r2) returns int {
        int n1 = <int>r1.votes;
        int n2 = <int>r2.votes;
        return (n1 < n2) ? 1 : (n1 == n2 ? 0 : -1);
    });
}

function commaFormatInt (int n) returns string {
    string minus = n < 0 ? "-" : "";
    int num = math:absInt(n);
    string numStr = num.toString();
    string[] parts = [];
    while numStr.length() > 3 {
		string part = numStr.substring(numStr.length()-3);
		parts.unshift(part);
		numStr = numStr.substring(0,numStr.length()-3);
	}
	if numStr.length() > 0 {
        parts.unshift(numStr); 
    }
    string res = 'string:'join(",", ... parts);
	return minus + res;
}
