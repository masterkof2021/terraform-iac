#!/usr/bin/env python3
"""Ejecuta Pulumi con credenciales temporales de AWS CLI, solo en memoria.

Uso: python scripts/pulumi-session.py --aws-profile proyecto [argumentos de pulumi]
Necesario cuando Pulumi no reconoce directamente login_session de `aws login`.
"""
import argparse
import json
import os
import subprocess
import sys

parser = argparse.ArgumentParser(add_help=False)
parser.add_argument("--aws-profile", default=os.environ.get("AWS_PROFILE", "default"))
args, pulumi_args = parser.parse_known_args()
if not pulumi_args:
    sys.exit("Uso: pulumi-session.py --aws-profile PERFIL [argumentos de pulumi]")
result = subprocess.run(
    ["aws", "configure", "export-credentials", "--profile", args.aws_profile, "--format", "process"],
    capture_output=True, text=True,
)
if result.returncode:
    sys.stderr.write(result.stderr)
    sys.exit(result.returncode)
credentials = json.loads(result.stdout)
env = os.environ.copy()
env["AWS_ACCESS_KEY_ID"] = credentials["AccessKeyId"]
env["AWS_SECRET_ACCESS_KEY"] = credentials["SecretAccessKey"]
if credentials.get("SessionToken"):
    env["AWS_SESSION_TOKEN"] = credentials["SessionToken"]
else:
    env.pop("AWS_SESSION_TOKEN", None)
env.pop("AWS_PROFILE", None)
env.setdefault("AWS_REGION", "us-east-2")
env.setdefault("AWS_DEFAULT_REGION", "us-east-2")
sys.exit(subprocess.run(["pulumi", *pulumi_args], env=env).returncode)
