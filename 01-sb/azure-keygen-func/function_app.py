import azure.functions as func

app = func.FunctionApp(http_auth_level=func.AuthLevel.ANONYMOUS)

# -------------------------------------------------------------------------------------------------
# POST /api/keygen
# -------------------------------------------------------------------------------------------------
@app.route(route="keygen", methods=["POST"])
def submit_keygen(req: func.HttpRequest) -> func.HttpResponse:
    return func.HttpResponse(
        "submit_keygen stub",
        status_code=200
    )

# -------------------------------------------------------------------------------------------------
# GET /api/result/{request_id}
# -------------------------------------------------------------------------------------------------
@app.route(route="result/{request_id}", methods=["GET"])
def fetch_result(req: func.HttpRequest) -> func.HttpResponse:
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
    connection="SERVICEBUS_CONN_STR",
)
def worker_keygen(msg: func.ServiceBusMessage) -> None:
    # No return for SB triggers; just log for now.
    import logging
    logging.info("worker_keygen stub received message: %s", msg.get_body().decode("utf-8"))
