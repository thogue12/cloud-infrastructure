"""
Terraform Pipeline Entry Point
Usage: python pipeline.py
Configure the PipelineContext at the bottom of this file before running.
"""
import sys
from datetime import datetime, timezone

from stages.base import PipelineContext
from stages.tfvars_generator import TfvarsGenerator
from stages.azure_backend_provisioner import AzureBackendProvisioner
from stages.aws_backend_provisioner import AwsBackendProvisioner
from stages.docker_builder import DockerBuilder
from stages.security_scanner import SecurityScanner
from stages.terraform_deployer import TerraformDeployer
from stages.artifact_publisher import ArtifactPublisher

SUPPORTED_PROVIDERS = {"azure", "aws"}


def _now() -> str:
    return datetime.now(timezone.utc).isoformat()


def _log(msg: str):
    print(f"[{_now()}] {msg}", flush=True)


def run_pipeline(ctx: PipelineContext) -> int:
    provider = ctx.cloud_provider.lower() if ctx.cloud_provider else ""

    if provider not in SUPPORTED_PROVIDERS:
        _log(f"ERROR: Unsupported cloud_provider '{ctx.cloud_provider}'. Must be 'azure' or 'aws'.")
        return 1

    # Select the correct backend provisioner at runtime
    backend_provisioner = AzureBackendProvisioner() if provider == "azure" else AwsBackendProvisioner()

    stages = [
        TfvarsGenerator(),
        backend_provisioner,
        DockerBuilder(),
        SecurityScanner(),
        TerraformDeployer(),
        ArtifactPublisher(),
    ]

    try:
        for stage in stages:
            _log(f"STAGE START: {stage.name}")
            result = stage.run(ctx)
            _log(f"STAGE END:   {stage.name} — {'OK' if result.success else 'FAILED'}: {result.message}")
            if not result.success:
                _log(f"Pipeline halted at stage: {stage.name}")
                return 1
    except KeyboardInterrupt:
        _log("Pipeline interrupted by user (KeyboardInterrupt)")
        return 1

    _log("Pipeline completed successfully.")
    return 0


if __name__ == "__main__":
    # ----------------------------------------------------------------
    # Configure your pipeline run here
    # ----------------------------------------------------------------
    ctx = PipelineContext(
        cloud_provider="azure",          # "azure" or "aws"
        variables={
            "project_name": "my-project",
            "environment": "dev",
            "location": "eastus",
            "subnet_address": ["10.0.1.0/24"],
            "aks_subnet_address": ["10.0.2.0/24"],
            "vnet_address": ["10.0.0.0/16"],
            "should_delegate": False,
            "enable_nat_gateway": False,
            "node_count": 2,
        },
        github_repo="thogue12/cloud-platform-pipelines",
        github_branch="main",
        # Azure backend inputs (required when cloud_provider="azure")
        subscription_id="",
        storage_account_name="pythontfstateaccount",
        resource_group_name="tf_state",
        # AWS backend inputs (required when cloud_provider="aws")
        # s3_bucket_name="<your-bucket>",
        # aws_region="us-east-1",
    )
    # ----------------------------------------------------------------
    sys.exit(run_pipeline(ctx))
