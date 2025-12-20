import json
import os
import uuid
import logging

import azure.functions as func

from azure.identity import DefaultAzureCredential
from azure.servicebus import ServiceBusClient, ServiceBusMessage

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
    return func.HttpResponse(
        f"fetch_result stub: {request_id}",
        status_code=200
    )

# -------------------------------------------------------------------------------------------------
# Service Bus queue trigger (worker)
# -------------------------------------------------------------------------------------------------
@app.function_name(name="worker_keygen")
@app.service_bus_queue_trigger(
    arg_name="msg",
    queue_name="%SERVICEBUS_QUEUE_NAME%",
    connection="ServiceBusConnection",
)
def sb_keygen_processor(msg: func.ServiceBusMessage) -> None:
    import logging
    logging.info(
        "worker_keygen received message: %s",
        msg.get_body().decode("utf-8")
    )

    # TODO: parse JSON, generate keys, write to Cosmos
