# Requirements Document

## Introduction

This feature defines a Python-based Terraform pipeline that orchestrates infrastructure deployment through six sequential stages: variable collection and tfvars generation, cloud-agnostic backend provisioning, Docker image build for security tooling, security scanning (tfsec, checkov, trivy), Terraform deployment, and post-deploy artifact push to GitHub. The pipeline integrates and extends the existing `Python/main.py`, `Python/build-docker-image.py`, and `Python/buikd-az-storage.py` scripts into a single cohesive, gate-controlled execution flow.

The pipeline supports both Azure and AWS as target cloud providers. The operator specifies a `cloud_provider` input (`"azure"` or `"aws"`), and the pipeline selects the appropriate backend provisioner at runtime: `AzureBackendProvisioner` for Azure (Storage Account + container + blob key) or `AwsBackendProvisioner` for AWS (S3 bucket + DynamoDB table for state locking). The generated Terraform backend block matches the selected provider.

## Glossary

- **Pipeline**: The top-level Python orchestrator that executes all stages in sequence.
- **Stage**: A discrete, ordered unit of work within the Pipeline.
- **TfvarsGenerator**: The component responsible for collecting variable values and writing the `.tfvars.json` file.
- **BackendProvisioner**: The abstract component responsible for creating or verifying the cloud storage backend used for Terraform remote state. Implemented by `AzureBackendProvisioner` and `AwsBackendProvisioner`.
- **AzureBackendProvisioner**: The provider-specific BackendProvisioner implementation that creates or verifies an Azure Storage Account, blob container, and blob key.
- **AwsBackendProvisioner**: The provider-specific BackendProvisioner implementation that creates or verifies an S3 bucket and a DynamoDB table (with `LockID` as the partition key) for Terraform state locking.
- **CloudProvider**: The operator-supplied input value (`"azure"` or `"aws"`, case-insensitive) that determines which BackendProvisioner implementation is selected at runtime.
- **DockerBuilder**: The component responsible for cloning the security scanner repository, building the Docker image, and running the container.
- **SecurityScanner**: The component responsible for executing tfsec, checkov, and trivy scans inside the Docker container and parsing their results.
- **TerraformDeployer**: The component responsible for running `terraform init`, `terraform plan`, and `terraform apply`.
- **ArtifactPublisher**: The component responsible for pushing the generated `.tfvars.json` file to GitHub after a successful deployment.
- **ScanResult**: A structured object containing the tool name, pass/fail status, and any findings from a single security scan.
- **tfvars file**: A JSON-formatted file (`.tfvars.json`) containing Terraform input variable values.
- **Backend block**: The Terraform `backend` configuration block that references the remote state storage. For Azure this is an `azurerm` backend; for AWS this is an `s3` backend.
- **Security gate**: A pipeline control point that halts execution if any security scan fails.

---

## Requirements

### Requirement 1: Variable Collection and tfvars Generation

**User Story:** As a platform engineer, I want the pipeline to collect Terraform variable values and generate a `.tfvars.json` file, so that Terraform commands receive consistent, reproducible input.

#### Acceptance Criteria

1. THE TfvarsGenerator SHALL accept the following variables as input: `project_name`, `environment`, `location`, `subnet_address`, `aks_subnet_address`, `vnet_address`, `should_delegate`, `enable_nat_gateway`, and `node_count`.
2. THE TfvarsGenerator SHALL write all collected variable values to a `.tfvars.json` file before any Terraform command is executed.
3. WHEN a required variable is not provided, THE TfvarsGenerator SHALL raise a descriptive error identifying the missing variable and halt the Pipeline.
4. WHEN the `.tfvars.json` file is written, THE TfvarsGenerator SHALL confirm the file path and name to the operator via standard output.

---

### Requirement 2: Dynamic Azure Backend Provisioning

**User Story:** As a platform engineer, I want the pipeline to create the Azure storage backend if it does not already exist, so that Terraform remote state is always available before `terraform init` runs.

#### Acceptance Criteria

1. THE BackendProvisioner SHALL accept a subscription ID and storage account name as input parameters.
2. WHEN the specified storage account does not exist in the given subscription, THE BackendProvisioner SHALL create the storage account, a blob container, and a state blob key in that order.
3. WHEN the specified storage account already exists, THE BackendProvisioner SHALL skip creation and proceed without error.
4. WHEN backend provisioning fails for any reason, THE BackendProvisioner SHALL log the error with the Azure API response and halt the Pipeline.
5. THE BackendProvisioner SHALL output the storage account name, container name, and blob key to the Pipeline so the Terraform backend block can be dynamically configured.

---

### Requirement 3: Docker Image Build for Security Tooling

**User Story:** As a platform engineer, I want the pipeline to clone the security scanner repository and build a Docker image containing tfsec, checkov, and trivy, so that scans always run in a controlled, versioned environment.

#### Acceptance Criteria

1. THE DockerBuilder SHALL clone the repository at `https://github.com/thogue12/cloud-platform-pipelines.git` on the `main` branch before building the image.
2. WHEN the clone destination directory already exists, THE DockerBuilder SHALL remove it before cloning.
3. THE DockerBuilder SHALL build a Docker image tagged `security-scanner` using the Dockerfile located at `Docker-Images/security-scanner/Dockerfile` within the cloned repository.
4. WHEN the Docker image build fails, THE DockerBuilder SHALL log the build error output and halt the Pipeline.
5. WHEN the Docker image is built successfully, THE DockerBuilder SHALL start the container before the SecurityScanner stage begins.

---

### Requirement 4: Security Scanning

**User Story:** As a platform engineer, I want the pipeline to run tfsec, checkov, and trivy against the Terraform code inside the Docker container, so that security issues are caught before any infrastructure is deployed.

#### Acceptance Criteria

1. THE SecurityScanner SHALL execute tfsec, checkov, and trivy scans sequentially inside the running Docker container.
2. THE SecurityScanner SHALL parse the output of each scan tool and produce a ScanResult for each tool.
3. WHEN all three ScanResults indicate a passing status, THE SecurityScanner SHALL signal the Pipeline to proceed to the Deploy Stage.
4. WHEN any ScanResult indicates a failing status, THE SecurityScanner SHALL log the findings for the failing tool(s) and halt the Pipeline without proceeding to deployment.
5. THE SecurityScanner SHALL report the pass/fail status of each individual scan tool to standard output before the security gate decision is made.

---

### Requirement 5: Terraform Deployment

**User Story:** As a platform engineer, I want the pipeline to run `terraform init`, `terraform plan`, and `terraform apply` only after all security scans pass, so that infrastructure is never deployed from code with known security issues.

#### Acceptance Criteria

1. WHEN all security scans pass, THE TerraformDeployer SHALL run `terraform init` using the backend configuration produced by the BackendProvisioner.
2. WHEN `terraform init` succeeds, THE TerraformDeployer SHALL run `terraform plan` with the generated tfvars file and save the plan output to a plan file.
3. WHEN `terraform plan` succeeds, THE TerraformDeployer SHALL run `terraform apply` using the saved plan file.
4. WHEN any Terraform command returns a non-zero exit code, THE TerraformDeployer SHALL log the command, exit code, and stderr output, then halt the Pipeline.
5. WHILE the Deploy Stage is running, THE TerraformDeployer SHALL stream command output to standard output in real time.

---

### Requirement 6: Post-Deploy Artifact Publishing

**User Story:** As a platform engineer, I want the pipeline to push the generated `.tfvars.json` file to GitHub after a successful deployment, so that the exact variable values used for each deployment are version-controlled and auditable.

#### Acceptance Criteria

1. WHEN `terraform apply` completes successfully, THE ArtifactPublisher SHALL push the generated `.tfvars.json` file to the configured GitHub repository and branch.
2. THE ArtifactPublisher SHALL require a GitHub personal access token provided via the `GITHUB_TOKEN` environment variable.
3. WHEN the `GITHUB_TOKEN` environment variable is not set, THE ArtifactPublisher SHALL raise a descriptive error and halt the Pipeline before attempting any GitHub operation.
4. WHEN the push to GitHub fails, THE ArtifactPublisher SHALL log the GitHub API error response and report the failure without rolling back the deployment.
5. WHEN the push to GitHub succeeds, THE ArtifactPublisher SHALL log the commit SHA and target branch to standard output.

---

### Requirement 7: Pipeline Orchestration and Stage Gating

**User Story:** As a platform engineer, I want the pipeline to enforce strict stage ordering and halt on any failure, so that partial or unsafe deployments never occur.

#### Acceptance Criteria

1. THE Pipeline SHALL execute stages in the following fixed order: TfvarsGenerator → BackendProvisioner → DockerBuilder → SecurityScanner → TerraformDeployer → ArtifactPublisher.
2. WHEN any stage fails, THE Pipeline SHALL halt immediately and report which stage failed along with the reason.
3. THE Pipeline SHALL return a non-zero exit code when any stage fails and a zero exit code when all stages complete successfully.
4. THE Pipeline SHALL log the start and completion of each stage with a timestamp to standard output.
5. IF the Pipeline is interrupted by a keyboard interrupt or system signal, THEN THE Pipeline SHALL log the interruption and exit with a non-zero exit code.

---

### Requirement 8: Cloud-Agnostic Backend Selection

**User Story:** As a platform engineer, I want to specify which cloud provider I am targeting (Azure or AWS), so that the pipeline automatically provisions the correct remote backend without requiring manual configuration changes.

#### Acceptance Criteria

1. THE Pipeline SHALL accept a `cloud_provider` input that accepts the values `"azure"` or `"aws"` in a case-insensitive manner.
2. WHEN `cloud_provider` resolves to `"azure"`, THE Pipeline SHALL select the `AzureBackendProvisioner` to create or verify the Azure Storage Account, blob container, and blob key (as defined in Requirement 2).
3. WHEN `cloud_provider` resolves to `"aws"`, THE Pipeline SHALL select the `AwsBackendProvisioner` to create or verify the S3 bucket and DynamoDB table for Terraform state locking.
4. WHEN `cloud_provider` resolves to `"aws"`, THE AwsBackendProvisioner SHALL accept an S3 bucket name as an input parameter.
5. WHEN the specified S3 bucket does not exist, THE AwsBackendProvisioner SHALL create it with native state locking enabled before proceeding.
6. WHEN the specified S3 bucket already exists, THE AwsBackendProvisioner SHALL skip creation and proceed without error.
7. THE AwsBackendProvisioner SHALL NOT create or require a DynamoDB table; state locking SHALL be enabled directly on the S3 bucket using the native locking feature.
8. WHEN `cloud_provider` resolves to `"azure"`, THE TerraformDeployer SHALL generate an `azurerm` backend block using the values from `BackendConfig`.
9. WHEN `cloud_provider` resolves to `"aws"`, THE TerraformDeployer SHALL generate an `s3` backend block using the values from `BackendConfig`.
10. WHEN an unsupported `cloud_provider` value is specified, THE Pipeline SHALL halt with a descriptive error identifying the unsupported value before any stage executes.
11. THE BackendConfig data model SHALL accommodate both Azure-specific fields (`storage_account`, `container_name`, `blob_key`, `resource_group`) and AWS-specific fields (`bucket`, `key`, `region`), with only the fields relevant to the selected provider populated.
