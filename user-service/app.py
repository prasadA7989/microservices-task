
import os

from flask import Flask, jsonify
from prometheus_client import Counter, generate_latest, CONTENT_TYPE_LATEST
from flask import Response

app = Flask(__name__)

REQUEST_COUNT = Counter(
    "microservice_requests_total",
    "Total requests handled by the service",
    ["service", "endpoint"]
)

SERVICE_NAME = "user-service"


@app.route("/")
def home():
    REQUEST_COUNT.labels(SERVICE_NAME, "/").inc()

    return jsonify({
        "service": SERVICE_NAME,
        "message": "User Service Version-2 is running"
    })


@app.route("/health")
def health():
    return jsonify({
        "service": SERVICE_NAME,
        "status": "healthy"
    }), 200


@app.route("/metrics")
def metrics():
    return Response(
        generate_latest(),
        mimetype=CONTENT_TYPE_LATEST
    )


if __name__ == "__main__":
    port = int(os.environ.get("PORT", 5000))
    app.run(host="0.0.0.0", port=port)
