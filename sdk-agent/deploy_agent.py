"""Deploy a hosted agent from a prebuilt container image with the Azure AI Projects SDK.

Creates a new version of the hosted agent in an existing Foundry project and waits until
the version is active. Equivalent of `azd deploy` for a prebuilt image.

Every setting is a command-line option or an environment variable; nothing is hardcoded.
"""

import argparse
import os
import sys
import time

from azure.ai.projects import AIProjectClient
from azure.ai.projects.models import (
    ContainerConfiguration,
    HostedAgentDefinition,
    ProtocolVersionRecord,
)
from azure.identity import DefaultAzureCredential


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument(
        "--project-endpoint",
        default=os.getenv("FOUNDRY_PROJECT_ENDPOINT"),
        help="Foundry project endpoint, https://<account>.services.ai.azure.com/api/projects/<project> "
        "(env: FOUNDRY_PROJECT_ENDPOINT). Required.",
    )
    parser.add_argument(
        "--image",
        default=os.getenv("AGENT_IMAGE"),
        help="Prebuilt image, <registry>.azurecr.io/<repo>:<tag> or @sha256:<digest> (env: AGENT_IMAGE). Required.",
    )
    parser.add_argument(
        "--agent-name",
        default=os.getenv("AGENT_NAME"),
        help="Agent name. An existing name creates a new version of that agent (env: AGENT_NAME). Required.",
    )
    parser.add_argument(
        "--model-deployment",
        default=os.getenv("MODEL_DEPLOYMENT_NAME"),
        help="Name of the model deployment in the Foundry account, passed to the agent as "
        "AZURE_AI_MODEL_DEPLOYMENT_NAME (env: MODEL_DEPLOYMENT_NAME). Required unless "
        "AZURE_AI_MODEL_DEPLOYMENT_NAME is given with --env.",
    )
    parser.add_argument(
        "--env",
        dest="extra_env",
        action="append",
        default=[],
        metavar="KEY=VALUE",
        help="Extra environment variable for the container. Can be repeated.",
    )
    parser.add_argument("--cpu", default=os.getenv("AGENT_CPU", "0.5"))
    parser.add_argument("--memory", default=os.getenv("AGENT_MEMORY", "1Gi"))
    parser.add_argument(
        "--registry-connection",
        default=os.getenv("AGENT_REGISTRY_CONNECTION"),
        help="Optional project connection used to authenticate to the registry "
        "(env: AGENT_REGISTRY_CONNECTION). Usually not needed: the platform pulls with the project identity.",
    )
    parser.add_argument("--timeout", type=int, default=600, help="Seconds to wait for the version to be active.")
    parser.add_argument("--invoke", metavar="PROMPT", help="Send a test prompt once the agent is active.")
    args = parser.parse_args()

    env = {"PYTHONNOUSERSITE": "1"}
    if args.model_deployment:
        env["AZURE_AI_MODEL_DEPLOYMENT_NAME"] = args.model_deployment
    for item in args.extra_env:
        key, sep, value = item.partition("=")
        if not sep or not key:
            parser.error(f"--env expects KEY=VALUE, got '{item}'")
        env[key] = value
    args.environment_variables = env

    missing = [
        flag
        for flag, value in (
            ("--project-endpoint", args.project_endpoint),
            ("--image", args.image),
            ("--agent-name", args.agent_name),
        )
        if not value
    ]
    if "AZURE_AI_MODEL_DEPLOYMENT_NAME" not in env:
        missing.append("--model-deployment")
    if missing:
        parser.error("missing required value(s): " + ", ".join(missing))
    return args


def wait_until_active(client: AIProjectClient, name: str, version: str, timeout: int):
    deadline = time.monotonic() + timeout
    while True:
        details = client.agents.get_version(agent_name=name, agent_version=version)
        status = getattr(details.status, "value", details.status)
        print(f"  status: {status}")
        if status == "active":
            return details
        if status in ("failed", "deleting", "deleted"):
            sys.exit(f"Agent version {name}:{version} ended in status '{status}'.")
        if time.monotonic() > deadline:
            sys.exit(f"Timed out waiting for {name}:{version} to become active.")
        time.sleep(10)


def main() -> None:
    args = parse_args()

    container = ContainerConfiguration(image=args.image)
    if args.registry_connection:
        container.registry_connection_id = args.registry_connection

    definition = HostedAgentDefinition(
        cpu=args.cpu,
        memory=args.memory,
        container_configuration=container,
        protocol_versions=[ProtocolVersionRecord(protocol="responses", version="2.0.0")],
        environment_variables=args.environment_variables,
    )

    with AIProjectClient(
        endpoint=args.project_endpoint,
        credential=DefaultAzureCredential(),
        allow_preview=True,
    ) as client:
        print(f"Creating a version of '{args.agent_name}' from {args.image}")
        created = client.agents.create_version(
            agent_name=args.agent_name,
            definition=definition,
            description=f"Hosted container agent using pre-built image {args.image}",
        )
        print(f"Created {created.name}:{created.version}, waiting for activation...")
        details = wait_until_active(client, created.name, created.version, args.timeout)
        print(f"Agent {details.name}:{details.version} is active.")

        if args.invoke:
            openai_client = client.get_openai_client(agent_name=args.agent_name)
            response = openai_client.responses.create(input=args.invoke)
            print(f"Response: {response.output_text}")


if __name__ == "__main__":
    main()
