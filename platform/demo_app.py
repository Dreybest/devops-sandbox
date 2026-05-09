#!/usr/bin/env python3
import os
from flask import Flask, jsonify

app = Flask(__name__)

ENV_ID = os.getenv("SANDBOX_ENV_ID", "unknown")
ENV_NAME = os.getenv("SANDBOX_ENV_NAME", "unnamed")


@app.get("/")
def home():
    return jsonify(
        {
            "message": "DevOps sandbox app is running",
            "env_id": ENV_ID,
            "env_name": ENV_NAME,
        }
    )


@app.get("/health")
def health():
    return jsonify(
        {
            "status": "ok",
            "env_id": ENV_ID,
        }
    ), 200


if __name__ == "__main__":
    app.run(host="0.0.0.0", port=80, debug=False)
