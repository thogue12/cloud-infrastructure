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
        filename = f"{project_name}-{environment}.tfvars.json"

        try:
            with open(filename, "w") as f:
                json.dump(ctx.variables, f, indent=4)
        except OSError as e:
            return StageResult(success=False, message=f"Failed to write tfvars file: {e}")

        ctx.tfvars_path = os.path.abspath(filename)
        print(f"[TfvarsGenerator] tfvars written to: {ctx.tfvars_path}")
        return StageResult(success=True, message=f"tfvars written to {ctx.tfvars_path}")
