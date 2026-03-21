import subprocess
import sys
from .base import Stage, StageResult, PipelineContext

PLAN_FILE = "tfplan"


def _stream_command(args: list) -> tuple:
    """Run a command, stream stdout in real time, return (returncode, stderr)."""
    print(f"[TerraformDeployer] Running: {' '.join(args)}")
    process = subprocess.Popen(
        args,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
    )
    # Stream stdout line by line
    for line in process.stdout:
        print(line, end="", flush=True)
    # Collect stderr after stdout is exhausted
    stderr_output = process.stderr.read()
    process.wait()
    return process.returncode, stderr_output


def _build_backend_config_flags(backend_config) -> list:
    """Build -backend-config flags based on provider."""
    if backend_config.provider == "azure":
        return [
            f"-backend-config=resource_group_name={backend_config.resource_group}",
            f"-backend-config=storage_account_name={backend_config.storage_account}",
            f"-backend-config=container_name={backend_config.container_name}",
            f"-backend-config=key={backend_config.blob_key}",
        ]
    elif backend_config.provider == "aws":
        return [
            f"-backend-config=bucket={backend_config.bucket}",
            f"-backend-config=key={backend_config.key}",
            f"-backend-config=region={backend_config.region}",
            "-backend-config=use_lockfile=true",
        ]
    return []


class TerraformDeployer(Stage):
    name = "TerraformDeployer"

    def run(self, ctx: PipelineContext) -> StageResult:
        if not ctx.backend_config:
            return StageResult(success=False, message="No backend_config in context")
        if not ctx.tfvars_path:
            return StageResult(success=False, message="No tfvars_path in context")

        backend_flags = _build_backend_config_flags(ctx.backend_config)

        # 1. terraform init
        init_cmd = ["terraform", "init"] + backend_flags
        rc, stderr = _stream_command(init_cmd)
        if rc != 0:
            return StageResult(
                success=False,
                message=f"terraform init failed (exit {rc}): {stderr.strip()}",
            )

        # 2. terraform plan
        plan_cmd = ["terraform", "plan", f"-var-file={ctx.tfvars_path}", f"-out={PLAN_FILE}"]
        rc, stderr = _stream_command(plan_cmd)
        if rc != 0:
            return StageResult(
                success=False,
                message=f"terraform plan failed (exit {rc}): {stderr.strip()}",
            )
        ctx.plan_file = PLAN_FILE

        # 3. terraform apply
        apply_cmd = ["terraform", "apply", PLAN_FILE]
        rc, stderr = _stream_command(apply_cmd)
        if rc != 0:
            return StageResult(
                success=False,
                message=f"terraform apply failed (exit {rc}): {stderr.strip()}",
            )

        ctx.apply_success = True
        return StageResult(success=True, message="Terraform deployment complete")
