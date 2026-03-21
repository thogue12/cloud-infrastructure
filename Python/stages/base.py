from abc import ABC, abstractmethod
from dataclasses import dataclass, field
from typing import Optional, Literal


@dataclass
class BackendConfig:
    provider: Literal["azure", "aws"]
    # Azure fields
    storage_account: Optional[str] = None
    container_name: Optional[str] = None
    blob_key: Optional[str] = None
    resource_group: Optional[str] = None
    # AWS fields
    bucket: Optional[str] = None
    key: Optional[str] = None
    region: Optional[str] = None


@dataclass
class ScanResult:
    tool: str  # "tfsec" | "checkov" | "trivy"
    passed: bool
    findings: list


@dataclass
class StageResult:
    success: bool
    message: str


@dataclass
class PipelineContext:
    # inputs (set before pipeline starts)
    variables: dict
    cloud_provider: str
    github_repo: str
    github_branch: str
    # Azure-specific inputs
    subscription_id: Optional[str] = None
    storage_account_name: Optional[str] = None
    resource_group_name: Optional[str] = None
    # AWS-specific inputs
    s3_bucket_name: Optional[str] = None
    aws_region: Optional[str] = None

    # outputs (populated by stages)
    tfvars_path: Optional[str] = None
    backend_config: Optional[BackendConfig] = None
    container_id: Optional[str] = None
    scan_results: list = field(default_factory=list)
    plan_file: Optional[str] = None
    apply_success: bool = False
    commit_sha: Optional[str] = None


class Stage(ABC):
    name: str = "base"

    @abstractmethod
    def run(self, ctx: PipelineContext) -> StageResult:
        ...
