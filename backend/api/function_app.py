import azure.functions as func
import logging
import json

app = func.FunctionApp(http_auth_level=func.AuthLevel.ANONYMOUS)

@app.route(route="GetResumeCounter")
@app.cosmos_db_input(
    arg_name="inputDocument",
    database_name="AzureResume",
    container_name="Counter",
    connection="CosmosDbConnectionString",
    id="1" # We only need the ID to find the document now
)
@app.cosmos_db_output(
    arg_name="outputDocument",
    database_name="AzureResume",
    container_name="Counter",
    connection="CosmosDbConnectionString"
)
def GetResumeCounter(req: func.HttpRequest, inputDocument: func.DocumentList, outputDocument: func.Out[func.Document]) -> func.HttpResponse:
    """
    This function increments a visitor counter in Cosmos DB and returns the original count.
    """
    logging.info('Python HTTP trigger function processed a request.')

    if not inputDocument:
        # The document no longer needs a separate partitionKey field
        counter_json = {
            "id": "1",
            "count": 1
        }
        outputDocument.set(func.Document.from_json(json.dumps(counter_json)))
        return_json = {"count": 1}
    else:
        current_counter_json = inputDocument[0]
        current_count = current_counter_json.get('count', 0)
        
        new_count = current_count + 1
        current_counter_json['count'] = new_count
        
        outputDocument.set(current_counter_json)
        
        return_json = {"count": current_count}

    return func.HttpResponse(
        body=json.dumps(return_json),
        mimetype="application/json",
        status_code=200
    )