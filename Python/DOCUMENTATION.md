# Cloud Platform Pipeline — Full Documentation

## Table of Contents

1. [Overview](#overview)
2. [Prerequisites](#prerequisites)
3. [Project Structure](#project-structure)
4. [Quick Start — Deploying Azure Resources](#quick-start)
5. [PipelineContext — The Shared Data Object](#pipelinecontext)
6. [Data Flow Diagram](#data-flow-diagram)
7. [Stage Reference](#stage-reference)
   - [Stage 1: TfvarsGenerator](#stage-1-tfvarsgenerator)
   - [Stage 2: AzureBackendProvisioner](#stage-2-azurebackendprovisioner)
   - [Stage 2 (alt): AwsBackendProvisioner](#stage-2-alt-awsbackendprovisioner)
   - [Stage 3: DockerBuilder](#stage-3-dockerbuilder)
   - [Stage 4: SecurityScanner](#stage-4-securityscanner)
   - [Stage 5: TerraformDeployer](#stage-5-terraformdeployer)
   - [Stage 6: ArtifactPublisher](#stage-6-artifactpublisher)
8. [Base Classes and Data Models](#base-classes-and-data-models)
9. [Error Handling Reference](#error-handling-reference)
10. [Python Terraform Library Reference](#python-terraform-library-reference)
11. [Extending the Pipeline](#extending-the-pipeline)
12. [Troubleshooting](#troubleshooting)

---

## Overview

This pipeline is a Python orchestrator that automates the full lifecycle of a Terraform
infrastructure deployment. It replaces the ad-hoc scripts (`main.py`,
`build-docker-image.py`, `buikd-az-storage.py`) with a single, structured entry point.

The pipeline runs six stages in a fixed, sequential order. Each stage is a self-contained
Python class. If any stage fails, the pipeline halts immediately — no subsequent stage runs.
This is called a "hard-stop gate" model.

```
TfvarsGenerator
      |
AzureBackendProvisioner  (or AwsBackendProvisioner)
      |
DockerBuilder
      |
SecurityScanner  <-- security gate: Terraform never runs if this fails
      |
TerraformDeployer
      |
ArtifactPublisher
```

All data is passed between stages through a single shared object called `PipelineContext`.
No stage writes to global state or reads from environment variables directly (except
`ArtifactPublisher` which reads `GITHUB_TOKEN`).

---

## Prerequisites

### System Requirements

| Requirement | Version | Notes |
|---|---|---|
| Python | 3.10+ | `python3 --version` to check |
| Terraform | 1.6+ | Must be on your `PATH`. S3 native locking requires >= 1.6 |
| Docker Desktop | Any recent | Must be running before you execute the pipeline |
| Git | Any | Used by DockerBuilder to clone the Dockerfile repo |
| Azure CLI | Any | Required for local authentication via `az login` |

### Python Packages

Install all dependencies from the repo root:

```bash
pip install -r requirements.txt
```

The `requirements.txt` contains:

| Package | Used By | Purpose |
|---|---|---|
| `azure-mgmt-storage` | AzureBackendProvisioner | Create/check Azure storage accounts |
| `azure-mgmt-resource` | (available for extension) | Azure resource group management |
| `azure-identity` | AzureBackendProvisioner | `DefaultAzureCredential` authentication |
| `azure-storage-blob` | (available for extension) | Direct blob operations |
| `PyGithub` | ArtifactPublisher | Push files to GitHub via the Contents API |
| `GitPython` | DockerBuilder | Clone the Dockerfile repository |
| `docker` | DockerBuilder, SecurityScanner | Build images, start containers, run exec |
| `boto3` | AwsBackendProvisioner | Create/check S3 buckets |
| `checkov` | (installed in Docker image) | IaC security scanning |
| `hypothesis` | (test suite) | Property-based testing |

### Authentication Setup

**Azure (required for Azure deployments):**

```bash
az login
```

`DefaultAzureCredential` will automatically pick up your CLI session. No environment
variables needed for local development. In CI/CD, set these instead:

```bash
export AZURE_CLIENT_ID="<service-principal-app-id>"
export AZURE_CLIENT_SECRET="<service-principal-secret>"
export AZURE_TENANT_ID="<your-tenant-id>"
```

**GitHub (required for ArtifactPublisher):**

```bash
export GITHUB_TOKEN="ghp_your_personal_access_token"
```

The token needs `repo` scope (read + write contents on the target repository).

**AWS (required for AWS deployments only):**

```bash
export AWS_ACCESS_KEY_ID="AKIA..."
export AWS_SECRET_ACCESS_KEY="..."
export AWS_DEFAULT_REGION="us-east-1"
```

Or configure `~/.aws/credentials` via `aws configure`.

---

## Project Structure

```
Python/
  pipeline.py                      # Entry point — configure and run from here
  DOCUMENTATION.md                 # This file
  stages/
    __init__.py                    # Makes stages/ a Python package
    base.py                        # Shared data models and Stage ABC
    tfvars_generator.py            # Stage 1: write .tfvars.json
    azure_backend_provisioner.py   # Stage 2a: provision Azure storage backend
    aws_backend_provisioner.py     # Stage 2b: provision AWS S3 backend
    docker_builder.py              # Stage 3: build security-scanner Docker image
    security_scanner.py            # Stage 4: run tflint, checkov, trivy
    terraform_deployer.py          # Stage 5: terraform init/plan/apply
    artifact_publisher.py          # Stage 6: push tfvars to GitHub
  tests/
    __init__.py
    (test files go here)
```

---

## Quick Start — Deploying Azure Resources

This is the fastest path to a working deployment.

### Step 1 — Install dependencies

```bash
pip install -r requirements.txt
```

### Step 2 — Authenticate

```bash
az login
export GITHUB_TOKEN="ghp_your_token_here"
```

### Step 3 — Configure pipeline.py

Open `Python/pipeline.py` and edit the `PipelineContext` block at the bottom of the file.
This is the only file you need to touch for a standard deployment.

```python
ctx = PipelineContext(
    cloud_provider="azure",

    # These become the contents of your .tfvars.json file.
    # All 9 keys are required — the pipeline will halt with a clear error
    # if any are missing.
    variables={
        "project_name": "my-platform",      # used in resource names and the tfvars filename
        "environment": "dev",               # dev | test | prod
        "location": "eastus",               # Azure region
        "subnet_address": ["10.0.1.0/24"],  # address space for the general subnet
        "aks_subnet_address": ["10.0.2.0/24"],  # dedicated AKS node subnet
        "vnet_address": ["10.0.0.0/16"],    # overall VNet address space
        "should_delegate": False,           # whether to add subnet delegation
        "enable_nat_gateway": False,        # whether to attach a NAT gateway
        "node_count": 2,                    # number of AKS nodes
    },

    # GitHub repo where the tfvars file will be committed after deployment
    github_repo="your-org/your-repo",
    github_branch="main",

    # Azure backend — the storage account that holds your Terraform state file.
    # The pipeline creates this automatically if it doesn't exist.
    subscription_id="xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx",
    storage_account_name="mytfstateaccount",   # must be globally unique, 3-24 chars, lowercase
    resource_group_name="my-resource-group",   # must already exist
)
```

### Step 4 — Run

```bash
cd Python
python3 pipeline.py
```

### What you will see

```
[2026-03-21T01:49:00Z] STAGE START: TfvarsGenerator
[TfvarsGenerator] tfvars written to: /path/to/my-platform-dev.tfvars.json
[2026-03-21T01:49:00Z] STAGE END:   TfvarsGenerator — OK: tfvars written to ...

[2026-03-21T01:49:00Z] STAGE START: AzureBackendProvisioner
[AzureBackendProvisioner] Storage account already exists, skipping creation.
[2026-03-21T01:49:02Z] STAGE END:   AzureBackendProvisioner — OK: Azure backend provisioned successfully

[2026-03-21T01:49:02Z] STAGE START: DockerBuilder
[DockerBuilder] Cloning https://github.com/thogue12/cloud-platform-pipelines.git on branch main...
[DockerBuilder] Building image 'security-scanner'...
...build output...
[DockerBuilder] Container started: a1b2c3d4e5f6
[2026-03-21T01:52:10Z] STAGE END:   DockerBuilder — OK: Docker image built and container started

[2026-03-21T01:52:10Z] STAGE START: SecurityScanner
[SecurityScanner] tflint: PASS
[SecurityScanner] checkov: PASS
[SecurityScanner] trivy: PASS
[2026-03-21T01:52:45Z] STAGE END:   SecurityScanner — OK: All security scans passed

[2026-03-21T01:52:45Z] STAGE START: TerraformDeployer
[TerraformDeployer] Running: terraform init -backend-config=...
...terraform output...
[2026-03-21T01:55:00Z] STAGE END:   TerraformDeployer — OK: Terraform deployment complete

[2026-03-21T01:55:00Z] STAGE START: ArtifactPublisher
[ArtifactPublisher] Pushed to main — commit: abc123def456
[2026-03-21T01:55:01Z] STAGE END:   ArtifactPublisher — OK: tfvars pushed to main (abc123def456)

[2026-03-21T01:55:01Z] Pipeline completed successfully.
```

### Stopping the pipeline

Press `Ctrl+C` at any time. The pipeline catches `KeyboardInterrupt`, logs the interruption,
and exits with code 1. Any infrastructure already applied will remain — Terraform does not
auto-rollback.

---

## PipelineContext — The Shared Data Object

`PipelineContext` is a Python `dataclass` defined in `stages/base.py`. It is the single
object that flows through every stage. Stages read from it to get their inputs and write
to it to pass outputs to downstream stages.

You create one instance at the bottom of `pipeline.py` and pass it to `run_pipeline()`.
The pipeline runner passes the same instance to every stage's `run()` method.

### Fields

#### Input fields (you set these before the pipeline runs)

| Field | Type | Required | Description |
|---|---|---|---|
| `cloud_provider` | `str` | Always | `"azure"` or `"aws"` (case-insensitive) |
| `variables` | `dict` | Always | Terraform variable key/value pairs |
| `github_repo` | `str` | Always | GitHub repo in `"owner/repo"` format |
| `github_branch` | `str` | Always | Branch to push the tfvars file to |
| `subscription_id` | `str` | Azure only | Azure subscription ID |
| `storage_account_name` | `str` | Azure only | Name of the Terraform state storage account |
| `resource_group_name` | `str` | Azure only | Resource group that owns the storage account |
| `s3_bucket_name` | `str` | AWS only | S3 bucket name for Terraform state |
| `aws_region` | `str` | AWS only | AWS region (e.g. `"us-east-1"`) |

#### Output fields (stages write these; you do not set them)

| Field | Type | Written By | Read By | Description |
|---|---|---|---|---|
| `tfvars_path` | `str` | TfvarsGenerator | TerraformDeployer, ArtifactPublisher | Absolute path to the generated `.tfvars.json` file |
| `backend_config` | `BackendConfig` | BackendProvisioner | TerraformDeployer | All backend connection details |
| `container_id` | `str` | DockerBuilder | SecurityScanner | Full Docker container ID |
| `scan_results` | `list[ScanResult]` | SecurityScanner | (logged only) | One `ScanResult` per tool |
| `plan_file` | `str` | TerraformDeployer | TerraformDeployer | Name of the saved plan file (`tfplan`) |
| `apply_success` | `bool` | TerraformDeployer | ArtifactPublisher | `True` only after a successful apply |
| `commit_sha` | `str` | ArtifactPublisher | (logged only) | SHA of the GitHub commit |

### Example — reading context state after a run

```python
import sys
sys.path.insert(0, 'Python')
from stages.base import PipelineContext
from pipeline import run_pipeline

ctx = PipelineContext(
    cloud_provider="azure",
    variables={...},
    github_repo="owner/repo",
    github_branch="main",
    subscription_id="...",
    storage_account_name="...",
    resource_group_name="...",
)

exit_code = run_pipeline(ctx)

# After the run you can inspect what each stage produced:
print(ctx.tfvars_path)       # /abs/path/to/my-project-dev.tfvars.json
print(ctx.backend_config)    # BackendConfig(provider='azure', storage_account='...', ...)
print(ctx.container_id)      # full 64-char container ID
print(ctx.scan_results)      # [ScanResult(tool='tflint', passed=True, ...), ...]
print(ctx.apply_success)     # True
print(ctx.commit_sha)        # abc123...
```

---

## Data Flow Diagram

```
pipeline.py
  |
  |-- creates PipelineContext (ctx) with all input fields
  |
  v
TfvarsGenerator.run(ctx)
  reads:   ctx.variables
  writes:  ctx.tfvars_path  ──────────────────────────────────────────┐
  |                                                                    |
  v                                                                    |
AzureBackendProvisioner.run(ctx)                                       |
  reads:   ctx.subscription_id                                        |
           ctx.storage_account_name                                   |
           ctx.resource_group_name                                    |
  writes:  ctx.backend_config  ──────────────────────────────────┐   |
  |                                                               |   |
  v                                                               |   |
DockerBuilder.run(ctx)                                            |   |
  reads:   (nothing from ctx — uses constants)                   |   |
  writes:  ctx.container_id  ──────────────────────────────┐    |   |
  |                                                         |    |   |
  v                                                         |    |   |
SecurityScanner.run(ctx)                                    |    |   |
  reads:   ctx.container_id  <────────────────────────────-┘    |   |
  writes:  ctx.scan_results                                      |   |
  |                                                              |   |
  v                                                              |   |
TerraformDeployer.run(ctx)                                       |   |
  reads:   ctx.backend_config  <─────────────────────────────────┘   |
           ctx.tfvars_path  <───────────────────────────────────────-┘
  writes:  ctx.plan_file
           ctx.apply_success
  |
  v
ArtifactPublisher.run(ctx)
  reads:   ctx.tfvars_path
           ctx.github_repo
           ctx.github_branch
           os.environ["GITHUB_TOKEN"]
  writes:  ctx.commit_sha
```

---

## Stage Reference

---

### Stage 1: TfvarsGenerator

**File:** `stages/tfvars_generator.py`
**Runs:** First, always
**Purpose:** Validate the Terraform variables and write them to a `.tfvars.json` file on disk.

#### What it does

1. Iterates over `REQUIRED_KEYS` and checks each one exists in `ctx.variables`. If any key
   is missing it immediately returns a failure `StageResult` naming the missing key. The
   pipeline halts — no file is written.
2. Constructs the output filename as `<project_name>-<environment>.tfvars.json` using the
   values from `ctx.variables`.
3. Serialises `ctx.variables` to JSON with 4-space indentation and writes the file to the
   current working directory (wherever you ran `python3 pipeline.py` from).
4. Sets `ctx.tfvars_path` to the absolute path of the written file.

#### Required keys

```python
REQUIRED_KEYS = [
    "project_name",       # string  — used in resource names
    "environment",        # string  — dev | test | prod
    "location",           # string  — Azure region, e.g. "eastus"
    "subnet_address",     # list    — e.g. ["10.0.1.0/24"]
    "aks_subnet_address", # list    — e.g. ["10.0.2.0/24"]
    "vnet_address",       # list    — e.g. ["10.0.0.0/16"]
    "should_delegate",    # boolean — subnet delegation flag
    "enable_nat_gateway", # boolean — NAT gateway flag
    "node_count",         # integer — AKS node count
]
```

#### Output file example

For `project_name="my-platform"` and `environment="dev"`, the file written is:

`my-platform-dev.tfvars.json`

```json
{
    "project_name": "my-platform",
    "environment": "dev",
    "location": "eastus",
    "subnet_address": ["10.0.1.0/24"],
    "aks_subnet_address": ["10.0.2.0/24"],
    "vnet_address": ["10.0.0.0/16"],
    "should_delegate": false,
    "enable_nat_gateway": false,
    "node_count": 2
}
```

#### Context reads / writes

| Direction | Field | Notes |
|---|---|---|
| Reads | `ctx.variables` | The dict you provided in `pipeline.py` |
| Writes | `ctx.tfvars_path` | Absolute path — used by TerraformDeployer and ArtifactPublisher |

#### Failure modes

| Condition | Message |
|---|---|
| Key missing from `ctx.variables` | `"Missing required variable: <key>"` |
| File write permission error | `"Failed to write tfvars file: <OS error>"` |

---

### Stage 2: AzureBackendProvisioner

**File:** `stages/azure_backend_provisioner.py`
**Runs:** Second, when `cloud_provider="azure"`
**Purpose:** Ensure the Azure Storage Account that holds Terraform state exists, then
populate `ctx.backend_config` with the connection details.

#### What it does

1. Validates that `ctx.subscription_id`, `ctx.storage_account_name`, and
   `ctx.resource_group_name` are all set. Halts with a descriptive error if any are missing.
2. Creates a `DefaultAzureCredential` — this automatically tries Azure CLI login, environment
   variables, managed identity, and workload identity in that order.
3. Creates a `StorageManagementClient` scoped to your subscription.
4. Lists all storage accounts in `ctx.resource_group_name` and checks whether
   `ctx.storage_account_name` is already present.
5. If the account does not exist: creates it (`Standard_LRS`, `StorageV2`, region from the
   `LOCATION` constant at the top of the file), then creates a blob container named `tfstate`.
6. If the account already exists: skips creation entirely (idempotent).
7. Populates `ctx.backend_config` with a `BackendConfig` instance containing all the values
   `TerraformDeployer` needs to build the `azurerm` backend flags.

#### Key constants (edit these to change defaults)

```python
CONTAINER_NAME = "tfstate"          # blob container name
BLOB_KEY       = "terraform.tfstate" # state file path inside the container
LOCATION       = "eastus"           # region used when creating the storage account
```

#### Context reads / writes

| Direction | Field | Notes |
|---|---|---|
| Reads | `ctx.subscription_id` | Azure subscription GUID |
| Reads | `ctx.storage_account_name` | Must be 3-24 chars, lowercase, globally unique |
| Reads | `ctx.resource_group_name` | Must already exist in Azure |
| Writes | `ctx.backend_config` | `BackendConfig(provider="azure", ...)` |

#### Failure modes

| Condition | Message |
|---|---|
| `subscription_id` not set | `"subscription_id is required for Azure backend provisioning"` |
| `storage_account_name` not set | `"storage_account_name is required..."` |
| `resource_group_name` not set | `"resource_group_name is required..."` |
| Azure SDK not installed | `"Missing Azure SDK dependency: <import error>"` |
| Any Azure API error | `"Azure backend provisioning failed: <exception>"` |

---

### Stage 2 (alt): AwsBackendProvisioner

**File:** `stages/aws_backend_provisioner.py`
**Runs:** Second, when `cloud_provider="aws"`
**Purpose:** Ensure the S3 bucket that holds Terraform state exists with native locking
enabled, then populate `ctx.backend_config`.

#### What it does

1. Validates `ctx.s3_bucket_name` and `ctx.aws_region` are set.
2. Creates a `boto3` S3 client in the specified region.
3. Calls `head_bucket` to check if the bucket exists. A `404` or `NoSuchBucket` error means
   it doesn't exist. Any other error is a real failure and halts the pipeline.
4. If the bucket does not exist: creates it with `ObjectLockEnabledForBucket=True` (this
   enables Terraform's native S3 state locking — no DynamoDB table needed). Also enables
   versioning, which is required by AWS for object lock to work.
5. Special case: `us-east-1` does not accept a `LocationConstraint` in the create call —
   the code handles this automatically.
6. If the bucket already exists: skips creation (idempotent).
7. Populates `ctx.backend_config`.

#### Key constant

```python
STATE_KEY = "terraform.tfstate"   # path of the state file inside the bucket
```

#### Context reads / writes

| Direction | Field | Notes |
|---|---|---|
| Reads | `ctx.s3_bucket_name` | S3 bucket name (globally unique) |
| Reads | `ctx.aws_region` | e.g. `"us-east-1"`, `"eu-west-1"` |
| Writes | `ctx.backend_config` | `BackendConfig(provider="aws", ...)` |

---

### Stage 3: DockerBuilder

**File:** `stages/docker_builder.py`
**Runs:** Third, always
**Purpose:** Clone the repository that contains the Dockerfile, build the `security-scanner`
Docker image, and start a container that stays alive for the next stage.

#### What it does

1. Determines `clone_path` as `<cwd>/workspace_build`.
2. If `workspace_build/` already exists, deletes it with `shutil.rmtree` to guarantee a
   clean clone every time.
3. Clones `REPO_URL` on `BRANCH` into `workspace_build/` using `git.Repo.clone_from`.
4. Builds the Docker image from the Dockerfile at
   `workspace_build/Docker-Images/security-scanner/Dockerfile`, tagging it `security-scanner`.
   Build log lines are streamed to stdout as they arrive.
5. Starts the container in detached mode (`detach=True`) with the current working directory
   mounted read-only at `/terraform` inside the container. The Dockerfile's
   `CMD ["tail", "-f", "/dev/null"]` keeps the container alive indefinitely.
6. Sets `ctx.container_id` to the full 64-character container ID.

#### Key constants (edit these to change the source)

```python
REPO_URL   = "https://github.com/thogue12/cloud-platform-pipelines.git"
BRANCH     = "main"
IMAGE_NAME = "security-scanner"
```

#### Volume mount

The current working directory (where you run `python3 pipeline.py` from) is mounted
read-only at `/terraform` inside the container. This is the path the security scanners
target. Your Terraform `.tf` files must be in or under that directory.

```
Host:      /path/to/Cloud-Platform/  (read-only)
Container: /terraform/
```

#### Context reads / writes

| Direction | Field | Notes |
|---|---|---|
| Reads | nothing from ctx | Uses constants only |
| Writes | `ctx.container_id` | Full 64-char Docker container ID |

#### Failure modes

| Condition | Message |
|---|---|
| `docker` or `gitpython` not installed | `"Missing dependency: <import error>"` |
| Permission error deleting `workspace_build/` | `"Permission denied removing clone dir: ..."` |
| Git clone fails | `"Git clone failed: <GitCommandError>"` |
| Docker build fails | `"Docker build failed: <error lines from build log>"` |
| Docker API error | `"Docker API error: <APIError>"` |
| Container start fails | `"Failed to start container: <exception>"` |

---

### Stage 4: SecurityScanner

**File:** `stages/security_scanner.py`
**Runs:** Fourth, always
**Purpose:** Run three security scanning tools against the Terraform code inside the
container. This is the security gate — if any tool fails, Terraform never runs.

#### What it does

1. Checks that `ctx.container_id` is set. If not, returns a failure immediately.
2. Iterates over `SCAN_TOOLS = ["tflint", "checkov", "trivy"]` in order.
3. For each tool, calls `_run_scan()` which builds a `docker exec` command and runs it via
   `subprocess.run` with `capture_output=True`.
4. Checks the exit code. Exit code 0 = passed. Any non-zero = failed.
5. Appends a `ScanResult` to `ctx.scan_results` for each tool.
6. Prints `[SecurityScanner] <tool>: PASS` or `FAIL` for each tool.
7. If any tool failed, prints all finding lines and returns a failure `StageResult` listing
   the failing tools.

#### The three scan tools

**tflint** — Terraform linter. Checks for deprecated syntax, invalid resource arguments,
and provider-specific rule violations.

```bash
# Command run inside the container:
tflint --chdir=/terraform
```

**checkov** — Bridgecrew's IaC security scanner. Checks for misconfigurations against
hundreds of built-in policies (CIS benchmarks, NIST, etc.).

```bash
# Command run inside the container:
checkov -d /terraform --quiet
```

**trivy** — Aqua Security's vulnerability and misconfiguration scanner. Scans Terraform
for misconfigurations. `--exit-code 1` makes trivy return non-zero if any issues are found.

```bash
# Command run inside the container:
trivy config /terraform --exit-code 1
```

#### `_parse_findings(output)` function

A module-level helper that takes the combined stdout+stderr string from a tool and returns
a list of non-empty, non-whitespace-only lines. Used to extract the human-readable finding
lines from tool output when a scan fails.

```python
def _parse_findings(output: str) -> list:
    return [line for line in output.splitlines() if line.strip()]
```

#### `_run_scan(tool, container_id)` method

Private method on `SecurityScanner`. Builds the `docker exec` command for the given tool,
runs it, and returns a `ScanResult`. Any exception (e.g. Docker not running) is caught and
returned as a failed `ScanResult` with the exception message as the finding.

#### Context reads / writes

| Direction | Field | Notes |
|---|---|---|
| Reads | `ctx.container_id` | Must be set by DockerBuilder |
| Writes | `ctx.scan_results` | Appends one `ScanResult` per tool |

#### Failure modes

| Condition | Message |
|---|---|
| `ctx.container_id` is None | `"No container ID in context — DockerBuilder must run first"` |
| Any tool exits non-zero | `"Security gate failed. Failing tools: tflint, checkov"` (lists failing tools) |
| `docker exec` itself fails | Tool's `ScanResult.findings` contains the exception message |

---

### Stage 5: TerraformDeployer

**File:** `stages/terraform_deployer.py`
**Runs:** Fifth, always (only reached if SecurityScanner passed)
**Purpose:** Run `terraform init`, `terraform plan`, and `terraform apply` in sequence,
streaming all output to your terminal in real time.

#### What it does

1. Validates `ctx.backend_config` and `ctx.tfvars_path` are set.
2. Calls `_build_backend_config_flags()` to translate `ctx.backend_config` into
   `-backend-config=` CLI flags appropriate for the provider.
3. Runs `terraform init` with those flags via `_stream_command()`.
4. Runs `terraform plan -var-file=<ctx.tfvars_path> -out=tfplan` via `_stream_command()`.
   Sets `ctx.plan_file = "tfplan"` on success.
5. Runs `terraform apply tfplan` via `_stream_command()`. Sets `ctx.apply_success = True`
   on success.
6. Any non-zero exit code from any command halts the pipeline immediately.

#### `_stream_command(args)` function

Module-level helper that runs a subprocess and streams its stdout line-by-line to your
terminal as the process runs (not after it finishes). stderr is collected separately and
returned for error messages.

```python
def _stream_command(args: list) -> tuple[int, str]:
    process = subprocess.Popen(args, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
    for line in process.stdout:
        print(line, end="", flush=True)   # real-time streaming
    stderr_output = process.stderr.read()
    process.wait()
    return process.returncode, stderr_output
```

This is why you see Terraform output appear line-by-line rather than all at once at the end.

#### `_build_backend_config_flags(backend_config)` function

Translates a `BackendConfig` object into a list of `-backend-config=` strings for
`terraform init`. The flags differ by provider:

**Azure:**
```
-backend-config=resource_group_name=<rg>
-backend-config=storage_account_name=<account>
-backend-config=container_name=tfstate
-backend-config=key=terraform.tfstate
```

**AWS:**
```
-backend-config=bucket=<bucket>
-backend-config=key=terraform.tfstate
-backend-config=region=<region>
-backend-config=use_lockfile=true
```

`use_lockfile=true` is the Terraform >= 1.6 native S3 locking flag. No DynamoDB table
is needed.

#### Key constant

```python
PLAN_FILE = "tfplan"   # name of the saved plan file written to disk
```

#### Context reads / writes

| Direction | Field | Notes |
|---|---|---|
| Reads | `ctx.backend_config` | Provides backend connection details |
| Reads | `ctx.tfvars_path` | Path to the `.tfvars.json` file |
| Writes | `ctx.plan_file` | Set to `"tfplan"` after successful plan |
| Writes | `ctx.apply_success` | Set to `True` after successful apply |

#### Failure modes

| Condition | Message |
|---|---|
| `ctx.backend_config` is None | `"No backend_config in context"` |
| `ctx.tfvars_path` is None | `"No tfvars_path in context"` |
| `terraform init` exits non-zero | `"terraform init failed (exit <N>): <stderr>"` |
| `terraform plan` exits non-zero | `"terraform plan failed (exit <N>): <stderr>"` |
| `terraform apply` exits non-zero | `"terraform apply failed (exit <N>): <stderr>"` |

---

### Stage 6: ArtifactPublisher

**File:** `stages/artifact_publisher.py`
**Runs:** Sixth (last), always (only reached after a successful apply)
**Purpose:** Push the generated `.tfvars.json` file to GitHub as a deployment artifact.

#### What it does

1. Reads `GITHUB_TOKEN` from the environment. Returns a failure immediately if absent —
   no GitHub API call is made.
2. Validates `ctx.tfvars_path` is set.
3. Reads the tfvars file as bytes.
4. Creates a `Github` client using the token.
5. Gets the target repository via `gh.get_repo(ctx.github_repo)`.
6. Determines the remote path as just the filename (e.g. `my-platform-dev.tfvars.json`).
7. Tries to get the existing file at that path on the target branch:
   - If it exists: calls `repo.update_file()` with the existing file's SHA.
   - If it returns 404: calls `repo.create_file()`.
8. Logs the resulting commit SHA and sets `ctx.commit_sha`.

#### Context reads / writes

| Direction | Field | Notes |
|---|---|---|
| Reads | `ctx.tfvars_path` | Local file to push |
| Reads | `ctx.github_repo` | `"owner/repo"` format |
| Reads | `ctx.github_branch` | Branch to commit to |
| Reads | `os.environ["GITHUB_TOKEN"]` | Personal access token with `repo` scope |
| Writes | `ctx.commit_sha` | SHA of the resulting GitHub commit |

#### Failure modes

| Condition | Message |
|---|---|
| `GITHUB_TOKEN` not set | `"GITHUB_TOKEN environment variable is not set"` |
| `ctx.tfvars_path` is None | `"No tfvars_path in context"` |
| `PyGithub` not installed | `"Missing PyGithub dependency: ..."` |
| File read error | `"Failed to read tfvars file: <OS error>"` |
| GitHub API error (non-404) | `"GitHub push failed: <GithubException>"` |

---

## Base Classes and Data Models

All shared types live in `stages/base.py`. Every stage imports from here.

---

### `Stage` (Abstract Base Class)

```python
class Stage(ABC):
    name: str = "base"

    @abstractmethod
    def run(self, ctx: PipelineContext) -> StageResult:
        ...
```

Every stage class inherits from `Stage` and must:
- Set the class attribute `name` to a unique string (used in log output)
- Implement `run(ctx)` which takes a `PipelineContext` and returns a `StageResult`

The `run()` method must never raise an unhandled exception — all errors must be caught
and returned as `StageResult(success=False, message="...")`.

---

### `StageResult`

```python
@dataclass
class StageResult:
    success: bool    # True = stage passed, False = pipeline should halt
    message: str     # Human-readable description of what happened
```

The pipeline runner checks `result.success` after every stage. If `False`, it logs
`result.message` and returns exit code 1.

---

### `BackendConfig`

```python
@dataclass
class BackendConfig:
    provider: Literal["azure", "aws"]
    # Azure fields
    storage_account: Optional[str] = None
    container_name:  Optional[str] = None
    blob_key:        Optional[str] = None
    resource_group:  Optional[str] = None
    # AWS fields
    bucket: Optional[str] = None
    key:    Optional[str] = None
    region: Optional[str] = None
```

Written by the BackendProvisioner stage. Read by TerraformDeployer to build
`-backend-config=` flags. Only the fields relevant to the selected provider are populated.

---

### `ScanResult`

```python
@dataclass
class ScanResult:
    tool:     str   # "tflint" | "checkov" | "trivy"
    passed:   bool  # True if exit code was 0
    findings: list  # non-empty lines from tool output (only populated on failure)
```

One `ScanResult` is created per scan tool and appended to `ctx.scan_results`.

---

### `PipelineContext`

See the full field reference in the [PipelineContext section](#pipelinecontext) above.

---

## Error Handling Reference

The pipeline uses a consistent pattern across all stages:

1. Guard clauses at the top of `run()` check for missing required context fields and return
   `StageResult(success=False, ...)` immediately.
2. SDK/subprocess calls are wrapped in `try/except`. The raw exception is included in the
   `StageResult.message` so you always know exactly what went wrong.
3. The pipeline runner in `pipeline.py` checks `result.success` after every stage. On
   failure it logs the stage name and message, then returns exit code 1.
4. `KeyboardInterrupt` is caught at the pipeline loop level — pressing Ctrl+C logs the
   interruption and exits cleanly with code 1.

| Stage | What can go wrong | How it surfaces |
|---|---|---|
| TfvarsGenerator | Missing variable key | `"Missing required variable: <key>"` |
| TfvarsGenerator | Disk write failure | `"Failed to write tfvars file: ..."` |
| AzureBackendProvisioner | Missing context field | `"<field> is required for Azure backend provisioning"` |
| AzureBackendProvisioner | Azure API error | `"Azure backend provisioning failed: <AzureError>"` |
| AwsBackendProvisioner | Missing context field | `"<field> is required for AWS backend provisioning"` |
| AwsBackendProvisioner | AWS API error | `"AWS backend provisioning failed: <ClientError>"` |
| DockerBuilder | Docker not running | `"Docker API error: ..."` |
| DockerBuilder | Git clone fails | `"Git clone failed: <GitCommandError>"` |
| DockerBuilder | Build fails | `"Docker build failed: <error lines>"` |
| SecurityScanner | No container ID | `"No container ID in context — DockerBuilder must run first"` |
| SecurityScanner | Scan tool fails | `"Security gate failed. Failing tools: <list>"` |
| TerraformDeployer | terraform not on PATH | `"terraform init failed (exit 127): ..."` |
| TerraformDeployer | Backend config wrong | `"terraform init failed (exit 1): <stderr>"` |
| TerraformDeployer | Plan/apply fails | `"terraform plan/apply failed (exit <N>): <stderr>"` |
| ArtifactPublisher | No GITHUB_TOKEN | `"GITHUB_TOKEN environment variable is not set"` |
| ArtifactPublisher | GitHub API error | `"GitHub push failed: <GithubException>"` |

---

## Python Terraform Library Reference

The pipeline does not use the `python-terraform` wrapper library. It calls the `terraform`
CLI directly via `subprocess.Popen`. This section explains why and documents the exact
commands used.

### Why subprocess instead of python-terraform

`python-terraform` is a thin wrapper that buffers all output and returns it as a string
after the command finishes. For long-running `terraform apply` operations this means you
see nothing for several minutes, then a wall of text. The pipeline uses `subprocess.Popen`
with line-by-line stdout streaming so you see output in real time.

### Terraform commands executed

#### `terraform init`

```bash
terraform init \
  -backend-config=resource_group_name=<rg> \
  -backend-config=storage_account_name=<account> \
  -backend-config=container_name=tfstate \
  -backend-config=key=terraform.tfstate
```

Initialises the working directory, downloads providers, and configures the remote backend.
The `-backend-config` flags are passed on the command line rather than hardcoded in a
`backend.tf` file, which keeps the Terraform code cloud-agnostic.

#### `terraform plan`

```bash
terraform plan \
  -var-file=/abs/path/to/my-project-dev.tfvars.json \
  -out=tfplan
```

Creates an execution plan and saves it to `tfplan`. The `-var-file` flag points to the
file written by TfvarsGenerator. The saved plan is used by `apply` to ensure exactly what
was reviewed gets applied.

#### `terraform apply`

```bash
terraform apply tfplan
```

Applies the saved plan. Because a plan file is passed, Terraform does not prompt for
confirmation — it applies immediately. This is intentional for pipeline automation.

### Terraform backend configuration

The backend is configured entirely via `-backend-config` flags on `terraform init`. Your
Terraform root module must have a backend block with no hardcoded values:

**For Azure (`azurerm` backend):**

```hcl
# In your root main.tf or backend.tf
terraform {
  backend "azurerm" {}
}
```

**For AWS (`s3` backend):**

```hcl
terraform {
  backend "s3" {}
}
```

The empty block is intentional. All values are supplied at runtime by the pipeline.

### Terraform version requirement

Terraform 1.6 or later is required. The AWS backend uses `use_lockfile=true` which is
a native S3 locking feature introduced in Terraform 1.6. Earlier versions require a
DynamoDB table for locking — this pipeline does not support that approach.

Check your version:

```bash
terraform version
```

### Working directory

`terraform init`, `plan`, and `apply` all run in the current working directory — wherever
you executed `python3 pipeline.py` from. Your `.tf` files must be in that directory or
Terraform will find nothing to deploy.

If you run the pipeline from `Python/`, Terraform will look for `.tf` files in `Python/`.
If your Terraform code is in the repo root, run the pipeline from there:

```bash
# From the repo root (where main.tf lives):
python3 Python/pipeline.py
```

---

## Extending the Pipeline

### Adding a new Terraform variable

1. Add the key and value to the `variables` dict in `pipeline.py`.
2. Add the key name to `REQUIRED_KEYS` in `stages/tfvars_generator.py`.
3. Add the corresponding `variable` block to your Terraform root module.

### Adding a new scan tool

1. Install the tool in the Dockerfile (in `Docker-Images/security-scanner/Dockerfile`).
2. Add the tool name to `SCAN_TOOLS` in `stages/security_scanner.py`.
3. Add an `elif` branch in `SecurityScanner._run_scan()`:

```python
elif tool == "my-tool":
    cmd = ["docker", "exec", container_id, "my-tool", "--flag", "/terraform"]
```

### Adding a new stage

1. Create `Python/stages/my_stage.py`:

```python
from .base import Stage, StageResult, PipelineContext

class MyStage(Stage):
    name = "MyStage"

    def run(self, ctx: PipelineContext) -> StageResult:
        try:
            # your logic here
            # read from ctx, write to ctx
            return StageResult(success=True, message="MyStage completed")
        except Exception as e:
            return StageResult(success=False, message=f"MyStage failed: {e}")
```

2. Import it in `pipeline.py` and insert it into the `stages` list at the position you want:

```python
from stages.my_stage import MyStage

stages = [
    TfvarsGenerator(),
    backend_provisioner,
    DockerBuilder(),
    SecurityScanner(),
    MyStage(),           # <-- inserted before TerraformDeployer
    TerraformDeployer(),
    ArtifactPublisher(),
]
```

### Adding a new cloud provider

1. Create `Python/stages/<provider>_backend_provisioner.py` following the same pattern as
   `azure_backend_provisioner.py` or `aws_backend_provisioner.py`.
2. Add the provider name to `SUPPORTED_PROVIDERS` in `pipeline.py`.
3. Add an `elif` branch in `run_pipeline()` to select your new provisioner.
4. Add an `elif` branch in `_build_backend_config_flags()` in `terraform_deployer.py` to
   generate the correct `-backend-config=` flags for your provider.
5. Add any new provider-specific fields to `PipelineContext` and `BackendConfig` in
   `stages/base.py`.

---

## Troubleshooting

### "Missing required variable: <key>"

You forgot to include one of the 9 required keys in the `variables` dict in `pipeline.py`.
Add the missing key.

### "subscription_id is required for Azure backend provisioning"

You set `cloud_provider="azure"` but left `subscription_id` as the placeholder
`"<your-subscription-id>"`. Replace it with your actual Azure subscription GUID.

Find your subscription ID:
```bash
az account show --query id -o tsv
```

### "Azure backend provisioning failed: DefaultAzureCredential failed..."

You are not authenticated to Azure. Run:
```bash
az login
```

### "Git clone failed"

Either the repo URL is wrong, you don't have network access, or the branch doesn't exist.
Check `REPO_URL` and `BRANCH` in `stages/docker_builder.py`.

### "Docker API error" or "Failed to start container"

Docker Desktop is not running. Start it and try again.

### "terraform init failed (exit 1)"

The most common causes:
- The backend storage account or S3 bucket doesn't exist yet (run the pipeline again —
  AzureBackendProvisioner will create it).
- Your Terraform root module doesn't have a `backend` block. Add an empty one (see the
  backend configuration section above).
- The `-backend-config` values are wrong. Check the values in `pipeline.py`.

### "terraform plan failed" — provider not registered

```
Error: The subscription is not registered to use namespace 'Microsoft.ContainerService'
```

Register the provider:
```bash
az provider register --namespace Microsoft.ContainerService
az provider register --namespace Microsoft.Network
az provider register --namespace Microsoft.Storage
```

### "Security gate failed. Failing tools: checkov"

Your Terraform code has security misconfigurations that checkov caught. The findings are
printed above the failure line. Fix the issues in your `.tf` files and re-run.

To see the full checkov output without running the whole pipeline:
```bash
checkov -d . --quiet
```

### "GITHUB_TOKEN environment variable is not set"

Export your token before running:
```bash
export GITHUB_TOKEN="ghp_your_token_here"
```

### Pipeline exits with code 1 but no clear error

Check the log line immediately before `Pipeline halted at stage:`. The `STAGE END` line
for the failing stage contains the full error message.

### Running from the wrong directory

Terraform looks for `.tf` files in the current working directory. If you run from `Python/`
but your Terraform code is in the repo root, init will succeed but plan will find nothing.

Always run from the directory that contains your `main.tf`:

```bash
# Correct — run from repo root where main.tf lives
python3 Python/pipeline.py

# Wrong — Terraform won't find any .tf files
cd Python && python3 pipeline.py
```
