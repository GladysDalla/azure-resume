import azure.functions as func
import logging
import os
from azure.identity import DefaultAzureCredential
from azure.keyvault.secrets import SecretClient
from azure.cosmos import CosmosClient, PartitionKey, exceptions

# Initialize the function app
app = func.FunctionApp(http_auth_level=func.AuthLevel.ANONYMOUS)

# --- Environment Variables ---
# The Bicep template sets these as App Settings in the Function App.
KEY_VAULT_URI = f"https://{os.environ['KEY_VAULT_NAME']}.vault.azure.net/"
COSMOS_DB_SECRET_NAME = "CosmosDbConnectionString"
DATABASE_NAME = 'AzureResume'
CONTAINER_NAME = 'Counter'

# --- Securely Fetch Connection String from Key Vault ---
# Use DefaultAzureCredential which automatically uses the Function App's Managed Identity
credential = DefaultAzureCredential()
secret_client = SecretClient(vault_url=KEY_VAULT_URI, credential=credential)

try:
    # Retrieve the secret from Key Vault
    retrieved_secret = secret_client.get_secret(COSMOS_DB_SECRET_NAME)
    cosmos_connection_string = retrieved_secret.value
    
    # Initialize the Cosmos DB client
    cosmos_client = CosmosClient.from_connection_string(cosmos_connection_string)
    database = cosmos_client.get_database_client(DATABASE_NAME)
    container = database.get_container_client(CONTAINER_NAME)

except Exception as e:
    logging.error(f"Failed to connect to Key Vault or Cosmos DB: {e}")
    # Set clients to None so the function can handle the error gracefully
    cosmos_client = None
    container = None


@app.route(route="get_visitor_count")
def get_visitor_count(req: func.HttpRequest) -> func.HttpResponse:
    """
    This function retrieves and increments the visitor counter from Cosmos DB.
    It uses a Managed Identity to securely access the connection string from Key Vault.
    """
    logging.info('Python HTTP trigger function processed a request.')

    if not container:
        # If the connection failed during startup, return an error
        return func.HttpResponse(
             "Error: Could not connect to the database. Please check the function logs.",
             status_code=500
        )

    try:
        # The counter document has a fixed ID of '1'
        item_id = '1'
        
        # Read the existing item
        item = container.read_item(item=item_id, partition_key=item_id)
        
        # Increment the count
        item['count'] += 1
        
        # Update the item in the database
        container.upsert_item(body=item)
        
        # Return the new count
        return func.HttpResponse(f'{{"count": {item["count"]}}}', status_code=200, mimetype="application/json")

    except exceptions.CosmosResourceNotFoundError:
        # If the counter item doesn't exist, create it
        new_item = {'id': '1', 'count': 1}
        container.create_item(body=new_item)
        return func.HttpResponse(f'{{"count": {new_item["count"]}}}', status_code=200, mimetype="application/json")
        
    except Exception as e:
        logging.error(f"An error occurred: {e}")
        return func.HttpResponse("An error occurred while processing your request.", status_code=500)

