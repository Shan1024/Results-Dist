import ballerina/config;
import ballerina/websub;
import ballerinax/java.jdbc;

import maryamzi/websub.hub.mysqlstore;

websub:Hub? hub = ();

public function main() returns error? {
    // create database connection to persist subscribers
    jdbc:Client db = new ({
        url: config:getAsString("eclk.hub.db.url"),
        username: config:getAsString("eclk.hub.db.username"),
        password: config:getAsString("eclk.hub.db.password"),
        dbOptions: {
            useSSL: config:getAsString("eclk.hub.db.useSsl")
        }
    });

    byte[]? key = ();
    string encryptionKey = config:getAsString("eclk.hub.db.encryptionkey");
    if (encryptionKey.trim() != "") {
        key = encryptionKey.toBytes();
    }

    // create the datastore for the websub hub
    mysqlstore:MySqlHubPersistenceStore persistenceStore = check new (db, key);

    // start the hub
    var hubStartUpResult =
        check websub:startHub(<@untainted> mediaListener, // weird BUG in ballerina compiler
                                "/websub", "/hub",
                                serviceAuth = {
                                    enabled: true
                                },
                                publisherResourceAuth = {
                                    enabled: true,
                                    scopes: ["publish"]
                                },
                                subscriptionResourceAuth = {
                                    enabled: true,
                                    scopes: ["subscribe"]
                                },
                                hubConfiguration = {
                                    leaseSeconds: 604800,
                                    hubPersistenceStore: persistenceStore,
                                    clientConfig: {
                                        // TODO: finalize
//                                        retryConfig: {
//                                            count:  1,
//                                           intervalInMillis: 5000
//                                        },
                                        //followRedirects: {
                                        //    enabled: true,
                                        //    maxCount: 5
                                        //},
                                        timeoutInMillis: 5*60000 // Check
                                    }
                                });

    if hubStartUpResult is websub:HubStartedUpError {
        return error(ERROR_REASON, message = hubStartUpResult.message);
    } else {
        hub = hubStartUpResult;
        check registerTopic(hubStartUpResult, JSON_TOPIC);
        check registerTopic(hubStartUpResult, IMAGE_PDF_TOPIC);
        check registerTopic(hubStartUpResult, AWAIT_RESULTS_TOPIC);
    }
}

function registerTopic(websub:Hub hub, string topic) returns error? {
    var result = hub.registerTopic(topic);
    if (result is error) {
        string? message = result.detail()?.message;
        if (message is string && message.indexOf("topic already exists") != ()) {
            // Ignore failures due to topic already being there; no harm
            return;
        }
        return result;
    }
}
