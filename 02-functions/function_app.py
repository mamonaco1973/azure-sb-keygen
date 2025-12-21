import json
import os
import uuid
import logging
import base64
import time

import azure.functions as func

from azure.identity import DefaultAzureCredential
from azure.servicebus import ServiceBusClient, ServiceBusMessage
from cryptography.hazmat.primitives.asymmetric import rsa, ed25519
from cryptography.hazmat.primitives import serialization
from azure.cosmos import CosmosClient, exceptions as cosmos_exceptions

app = func.FunctionApp(http_auth_level=func.AuthLevel.ANONYMOUS)

@app.route(route="keygen", methods=["POST"])
def keygen_post(req: func.HttpRequest) -> func.HttpResponse:
    try:
        body = req.get_json()
    except Exception:
        body = {}

    request_id = str(uuid.uuid4())

    msg = {
        "request_id": request_id,
        "key_type": body.get("key_type", "rsa"),
        "key_bits": body.get("key_bits", 2048),
    }

    sb_namespace = os.environ["SERVICEBUS_NAMESPACE_FQDN"]
    queue_name   = os.environ["SERVICEBUS_QUEUE_NAME"]

    credential = DefaultAzureCredential()

    try:
        with ServiceBusClient(
            fully_qualified_namespace=sb_namespace,
            credential=credential
        ) as client:
            with client.get_queue_sender(queue_name=queue_name) as sender:
                sender.send_messages(
                    ServiceBusMessage(
                        json.dumps(msg),
                        correlation_id=request_id,
                    )
                )
    except Exception:
        logging.exception("Failed to queue keygen request")
        return func.HttpResponse(
            json.dumps({"error": "failed_to_queue_request"}),
            status_code=500,
            mimetype="application/json",
        )

    return func.HttpResponse(
        json.dumps({"request_id": request_id, "status": "queued"}),
        status_code=202,
        mimetype="application/json",
    )

# -------------------------------------------------------------------------------------------------
# GET /api/result/{request_id}
# -------------------------------------------------------------------------------------------------
@app.route(route="result/{request_id}", methods=["GET"])
def keygen_get(req: func.HttpRequest) -> func.HttpResponse:
    request_id = req.route_params.get("request_id")
    if not request_id:
        return func.HttpResponse(
            json.dumps({"error": "Missing request_id"}),
            status_code=400,
            mimetype="application/json",
        )

    logging.info("Fetching result for request_id: %s", request_id)

    endpoint = os.environ["COSMOS_ENDPOINT"]
    db_name  = os.environ["COSMOS_DATABASE_NAME"]
    ctr_name = os.environ["COSMOS_CONTAINER_NAME"]

    try:
        credential = DefaultAzureCredential()
        client = CosmosClient(endpoint, credential=credential)
        container = client.get_database_client(db_name).get_container_client(ctr_name)

        # We stored id=request_id, so read by (id, partition_key)
        # If your container partition key is /id, this is correct:
        item = container.read_item(item=request_id, partition_key=request_id)

        return func.HttpResponse(
            json.dumps(item),
            status_code=200,
            mimetype="application/json",
        )

    except cosmos_exceptions.CosmosResourceNotFoundError:
        # Not found => pending (matches your DynamoDB behavior)
        return func.HttpResponse(
            json.dumps({"status": "pending", "request_id": request_id}),
            status_code=202,
            mimetype="application/json",
        )

    except Exception as e:
        logging.exception("Cosmos read_item failed: %s", e)
        return func.HttpResponse(
            json.dumps({"error": "Internal server error"}),
            status_code=500,
            mimetype="application/json",
        )

# ------------------------------------------------------------------------------
# SSH Key Generation Logic
# ------------------------------------------------------------------------------
def generate_keypair(key_type: str = "rsa", key_bits: int = 2048):
    """Generate SSH keypair and return (public, private) strings."""
    if key_type == "rsa":
        priv = rsa.generate_private_key(public_exponent=65537, key_size=key_bits)
    elif key_type == "ed25519":
        priv = ed25519.Ed25519PrivateKey.generate()
    else:
        logging.warning(f"Unknown key type '{key_type}', defaulting to RSA.")
        priv = rsa.generate_private_key(public_exponent=65537, key_size=key_bits)

    pub_ssh = priv.public_key().public_bytes(
        serialization.Encoding.OpenSSH,
        serialization.PublicFormat.OpenSSH
    ).decode()

    if key_type == "ed25519":
        priv_format = serialization.PrivateFormat.PKCS8
    else:
        priv_format = serialization.PrivateFormat.TraditionalOpenSSL

    priv_pem = priv.private_bytes(
        serialization.Encoding.PEM,
        priv_format,
        serialization.NoEncryption()
    ).decode()

    return pub_ssh, priv_pem

# -------------------------------------------------------------------------------------------------
# Service Bus queue trigger (worker)
# -------------------------------------------------------------------------------------------------
@app.function_name(name="keygen_worker")
@app.service_bus_queue_trigger(
    arg_name="msg",
    queue_name="%SERVICEBUS_QUEUE_NAME%",
    connection="ServiceBusConnection",
)
def keygen_processor(msg: func.ServiceBusMessage) -> None:
    try:
        raw = msg.get_body().decode("utf-8")
        body = json.loads(raw)

        # Prefer request_id in payload; fall back to SB correlation_id if present
        request_id = (
            body.get("request_id")
            or getattr(msg, "correlation_id", None)
            or "unknown"
        )

        key_type = body.get("key_type", "rsa")
        key_bits = body.get("key_bits", 2048)
        try:
            key_bits = int(key_bits)
        except Exception:
            key_bits = 2048

        logging.info("Processing request %s (%s-%s)", request_id, key_type, key_bits)

        # ----------------------------------------------------------------------
        # Generate SSH keypair
        # ----------------------------------------------------------------------
        pub, priv = generate_keypair(key_type, key_bits)

        # ----------------------------------------------------------------------
        # Prepare result document for Cosmos DB
        # ----------------------------------------------------------------------
        result = {
            "id": request_id,   # Cosmos requires an "id"
            "request_id": request_id,
            "status": "complete",
            "key_type": key_type,
            "public_key_b64": base64.b64encode(pub.encode()).decode(),
            "private_key_b64": base64.b64encode(priv.encode()).decode(),

            # Cosmos TTL is seconds-to-live (relative) when TTL is enabled
            "ttl": 86400,

            # Optional: if you still want an absolute expiry timestamp for debugging
            "expires_at": int(time.time()) + 86400,
        }

        # ----------------------------------------------------------------------
        # Store result in Cosmos DB (RBAC / Managed Identity)
        # ----------------------------------------------------------------------
        endpoint = os.environ["COSMOS_ENDPOINT"]
        db_name  = os.environ["COSMOS_DATABASE_NAME"]
        ctr_name = os.environ["COSMOS_CONTAINER_NAME"]

        credential = DefaultAzureCredential()

        # Key change: use token credential (RBAC), not account key
        client = CosmosClient(endpoint, credential=credential)
        container = client.get_database_client(db_name).get_container_client(ctr_name)

        container.upsert_item(result)

        logging.info("Stored result in Cosmos for %s", request_id)

    except Exception as e:
        logging.exception("Failed processing message: %s", e)
        raise
