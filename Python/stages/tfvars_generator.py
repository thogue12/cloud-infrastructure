import json
import os
from .base import Stage, StageResult, PipelineContext

REQUIRED_KEYS = [
    "project_name",
    "environment",
    "location",
    "subnet_address",
    "aks_subnet_address",
    "vnet_address",
    "should_delegate",
    "enable_nat_gateway",
    "node_count",
]

# Maps cloud_provider to the top-level cloud directory name
CLOUD_DIR_MAP = {
    "azure": "Azure",
    "aws": "AWS",
}


class TfvarsGenerator(Stage):
    name = "TfvarsGenerator"

    def run(self, ctx: PipelineContext) -> StageResult:
        # Validate all required keys are present
        for key in REQUIRED_KEYS:
            if key not in ctx.variables:
                return StageResult(
                    success=False,
                    message=f"Missing required variable: {key}",
                )

        project_name = ctx.variables["project_name"]
        environment = ctx.variables["environment"]
        cloud_dir = CLOUD_DIR_MAP.get(ctx.cloud_provider.lower(), ctx.cloud_provider.capitalize())

        # Build output path: <Cloud>/Environments/<environment>/clients/<project_name>.tfvars.json
        output_dir = os.path.join(cloud_dir, "Environments", environment, "clients")
        os.makedirs(output_dir, exist_ok=True)
        filepath = os.path.join(output_dir, f"{project_name}.tfvars.json")

        try:
            with open(filepath, "w") as f:
                json.dump(ctx.variables, f, indent=4)
        except OSError as e:
            return StageResult(success=False, message=f"Failed to write tfvars file: {e}")

        ctx.tfvars_path = os.path.abspath(filepath)
        print(f"[TfvarsGenerator] tfvars written to: {ctx.tfvars_path}")
        return StageResult(success=True, message=f"tfvars written to {ctx.tfvars_path}")
