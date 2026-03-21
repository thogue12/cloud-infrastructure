# Implementation Plan: terraform-python-pipeline

## Overview

Incrementally build the pipeline from the base interfaces outward: shared types first, then each stage module, then the pipeline runner, then wire everything together. Existing scripts (`main.py`, `build-docker-image.py`, `buikd-az-storage.py`) are refactored into their respective stage classes rather than deleted.

## Tasks

- [x] 1. Set up project structure and base interfaces
  - Create `Python/stages/__init__.py` (empty)
  - Create `Python/tests/__init__.py` (empty)
  - Implement `Python/stages/base.py` with `BackendConfig`, `ScanResult`, `PipelineContext`, `StageResult`, and `Stage` ABC exactly as specified in the design
  - _Requirements: 7.1_

- [x] 2. Implement TfvarsGenerator
  - [x] 2.1 Implement `Python/stages/tfvars_generator.py`
    - Validate all 9 required keys; raise descriptive `StageResult` on missing key
    - Serialize `ctx.variables` to `<project_name>-<environment>.tfvars.json` and set `ctx.tfvars_path`
    - Print confirmed file path to stdout
    - _Requirements: 1.1, 1.2, 1.3, 1.4_

  - [ ]* 2.2 Write property test: TfvarsGenerator write round-trip (Property 1)
    - **Property 1: TfvarsGenerator write round-trip**
    - Use `hypothesis` `@given` with `st.fixed_dictionaries` covering all 9 required keys
    - Assert JSON read-back equals original dict
    - **Validates: Requirements 1.1, 1.2**

  - [ ]* 2.3 Write property test: missing variable raises descriptive error (Property 2)
    - **Property 2: Missing variable raises descriptive error**
    - Generate dicts missing at least one required key; assert `StageResult.success=False` and message names the missing key
    - **Validates: Requirements 1.3**

- [x] 3. Implement AzureBackendProvisioner
  - [x] 3.1 Implement `Python/stages/azure_backend_provisioner.py`
    - Accept `ctx.subscription_id` and `ctx.storage_account_name`
    - Use `azure-mgmt-storage` `StorageManagementClient` to check existence; create storage account, container, and blob key if absent
    - Populate `ctx.backend_config` with a `BackendConfig(provider="azure", ...)` instance
    - Log Azure API error and return failure `StageResult` on any exception
    - _Requirements: 2.1, 2.2, 2.3, 2.4, 2.5_

  - [ ]* 3.2 Write property test: AzureBackendProvisioner idempotence (Property 3)
    - **Property 3: BackendProvisioner idempotence**
    - Mock `StorageManagementClient`; for any pre-existing account name assert create API is never called and result is success
    - **Validates: Requirements 2.3**

  - [ ]* 3.3 Write property test: BackendConfig output matches provisioned values (Property 4)
    - **Property 4: BackendConfig output matches provisioned values**
    - Assert `ctx.backend_config` fields equal the values used during provisioning
    - **Validates: Requirements 2.2, 2.5**

  - [ ]* 3.4 Write property test: stage error propagation for Azure errors (Property 5)
    - **Property 5: Stage error propagation**
    - Inject `AzureError` via mock; assert `StageResult(success=False)` with non-empty message
    - **Validates: Requirements 2.4**

- [x] 4. Implement AwsBackendProvisioner
  - [x] 4.1 Implement `Python/stages/aws_backend_provisioner.py`
    - Accept `ctx.s3_bucket_name` and `ctx.aws_region`
    - Use `boto3` to check if the S3 bucket exists; create it with native state locking enabled (`ObjectLockEnabled=True`) if absent
    - Populate `ctx.backend_config` with a `BackendConfig(provider="aws", bucket=..., key=..., region=...)` instance
    - Log AWS API error (`botocore.exceptions.ClientError`) and return failure `StageResult` on any exception
    - _Requirements: 8.3, 8.4, 8.5, 8.6, 8.7_

  - [ ]* 4.2 Write property test: AwsBackendProvisioner idempotence (Property 14)
    - **Property 14: AwsBackendProvisioner idempotence**
    - Mock `boto3.client("s3")`; for any pre-existing bucket name assert create API is never called and result is success
    - **Validates: Requirements 8.7**

  - [ ]* 4.3 Write property test: stage error propagation for AWS errors (Property 5)
    - **Property 5: Stage error propagation (AwsBackendProvisioner)**
    - Inject `ClientError` via `botocore.stub.Stubber`; assert `StageResult(success=False)` with non-empty message
    - **Validates: Requirements 8.3**

- [x] 5. Implement DockerBuilder
  - [x] 5.1 Implement `Python/stages/docker_builder.py`
    - Refactor logic from `Python/build-docker-image.py` into the `Stage` interface
    - Remove `workspace_build/` with `shutil.rmtree` if it exists before cloning
    - Clone `https://github.com/thogue12/cloud-platform-pipelines.git` on `main` via `git.Repo.clone_from`
    - Build image tagged `security-scanner` via `docker.from_env().images.build`
    - Start container in detached mode; set `ctx.container_id`
    - Log build errors and return failure `StageResult` on `BuildError`
    - _Requirements: 3.1, 3.2, 3.3, 3.4, 3.5_

  - [ ]* 5.2 Write property test: pre-existing clone directory is removed (Property 6)
    - **Property 6: Pre-existing clone directory is removed before clone**
    - For any pre-existing directory at clone path, assert `shutil.rmtree` is called before `clone_from`
    - **Validates: Requirements 3.2**

  - [ ]* 5.3 Write unit tests for DockerBuilder
    - Assert image tag is `security-scanner`, clone URL and branch are correct
    - Assert `StageResult(success=False)` on `BuildError`
    - _Requirements: 3.3, 3.4_

- [x] 6. Implement SecurityScanner
  - [x] 6.1 Implement `Python/stages/security_scanner.py`
    - Execute `tfsec`, `checkov`, and `trivy` sequentially via `docker exec` against `ctx.container_id`
    - Parse exit code and stdout per tool into a `ScanResult`; append to `ctx.scan_results`
    - Print pass/fail status per tool to stdout
    - Return failure `StageResult` if any `ScanResult.passed=False`, logging all findings
    - _Requirements: 4.1, 4.2, 4.3, 4.4, 4.5_

  - [ ]* 6.2 Write property test: ScanResult parsing produces correct structure (Property 7)
    - **Property 7: ScanResult parsing produces correct structure**
    - For any tool name and output string, assert `tool` matches, `passed` reflects exit code 0, `findings` non-empty iff output contained finding lines
    - **Validates: Requirements 4.2**

  - [ ]* 6.3 Write property test: security gate decision matches scan results (Property 8)
    - **Property 8: Security gate decision matches scan results**
    - For any list of `ScanResult` objects, assert success iff all `passed=True`
    - **Validates: Requirements 4.3, 4.4**

- [ ] 7. Checkpoint — Ensure all tests pass
  - Ensure all tests pass, ask the user if questions arise.

- [x] 8. Implement TerraformDeployer
  - [x] 8.1 Implement `Python/stages/terraform_deployer.py`
    - Refactor logic from `Python/main.py` into the `Stage` interface
    - Run `terraform init` with provider-specific `-backend-config` flags derived from `ctx.backend_config.provider`:
      - Azure: `resource_group_name`, `storage_account_name`, `container_name`, `key`
      - AWS: `bucket`, `key`, `region`, `use_lockfile=true`
    - Run `terraform plan -var-file=<ctx.tfvars_path> -out=tfplan`; set `ctx.plan_file`
    - Run `terraform apply tfplan`; set `ctx.apply_success=True` on success
    - Use `subprocess.Popen` with line-by-line stdout streaming for all commands
    - Log command, exit code, and stderr on non-zero exit; return failure `StageResult`
    - _Requirements: 5.1, 5.2, 5.3, 5.4, 5.5, 8.8, 8.9_

  - [ ]* 8.2 Write property test: stage error propagation for subprocess errors (Property 5)
    - **Property 5: Stage error propagation (TerraformDeployer)**
    - Mock `subprocess.Popen` to return non-zero exit; assert `StageResult(success=False)` with error detail
    - **Validates: Requirements 5.4**

  - [ ]* 8.3 Write unit tests for TerraformDeployer
    - Assert subcommand order: `init` → `plan` → `apply`
    - Assert Azure backend flags when `provider="azure"`, AWS flags when `provider="aws"`
    - Assert `use_lockfile=true` is passed for AWS and no DynamoDB flag is present
    - Assert stdout is streamed line-by-line (not captured)
    - _Requirements: 5.1, 5.2, 5.3, 5.5, 8.8, 8.9_

- [x] 9. Implement ArtifactPublisher
  - [x] 9.1 Implement `Python/stages/artifact_publisher.py`
    - Read `GITHUB_TOKEN` from environment; return failure `StageResult` immediately if absent (no API call)
    - Use `PyGithub` to push `ctx.tfvars_path` file content to `ctx.github_repo` on `ctx.github_branch`
    - Log commit SHA and branch on success
    - Log GitHub API error and return failure `StageResult` on `GithubException` (no deployment rollback)
    - _Requirements: 6.1, 6.2, 6.3, 6.4, 6.5_

  - [ ]* 9.2 Write property test: missing GITHUB_TOKEN halts before any API call (Property 9)
    - **Property 9: Missing GITHUB_TOKEN halts before any API call**
    - For any context without `GITHUB_TOKEN` set, assert `StageResult(success=False)` and GitHub client is never instantiated
    - **Validates: Requirements 6.2, 6.3**

  - [ ]* 9.3 Write property test: artifact push content matches tfvars file (Property 10)
    - **Property 10: Artifact push content matches tfvars file**
    - For any `.tfvars.json` content, assert bytes pushed to GitHub API equal local file bytes
    - **Validates: Requirements 6.1**

- [x] 10. Implement Pipeline runner
  - [x] 10.1 Implement `Python/pipeline.py`
    - Instantiate `PipelineContext` from environment/config inputs including `cloud_provider`
    - Validate `cloud_provider` before any stage runs; halt with descriptive error if unsupported
    - Select `AzureBackendProvisioner` or `AwsBackendProvisioner` based on normalised `cloud_provider`
    - Define `STAGES` list in fixed order: `TfvarsGenerator → BackendProvisioner → DockerBuilder → SecurityScanner → TerraformDeployer → ArtifactPublisher`
    - Loop through stages: log ISO-timestamp start, call `stage.run(ctx)`, log ISO-timestamp completion, halt with `sys.exit(1)` on failure
    - Catch `KeyboardInterrupt`; log interruption and `sys.exit(1)`
    - Exit `0` on full success
    - _Requirements: 7.1, 7.2, 7.3, 7.4, 7.5, 8.1, 8.2, 8.3, 8.10_

  - [ ]* 10.2 Write property test: pipeline halts at first failing stage (Property 11)
    - **Property 11: Pipeline halts at first failing stage**
    - For any stage index `i` returning failure, assert no stage at index `> i` is called and exit code is non-zero
    - **Validates: Requirements 7.1, 7.2, 7.3**

  - [ ]* 10.3 Write property test: stage log entries contain timestamps (Property 12)
    - **Property 12: Stage log entries contain timestamps**
    - For any stage execution, assert captured log output contains ISO-format start and completion entries
    - **Validates: Requirements 7.4**

  - [ ]* 10.4 Write property test: cloud provider routes to correct provisioner (Property 13)
    - **Property 13: Cloud provider selection routes to correct provisioner**
    - For any case-insensitive `"azure"` input assert `AzureBackendProvisioner` is used; for `"aws"` assert `AwsBackendProvisioner`
    - **Validates: Requirements 8.1, 8.2, 8.3**

  - [ ]* 10.5 Write property test: unsupported cloud provider halts before any stage (Property 15)
    - **Property 15: Unsupported cloud provider halts pipeline before any stage**
    - For any value not in `{"azure", "aws"}`, assert pipeline halts with descriptive error and no stage executes
    - **Validates: Requirements 8.10**

  - [ ]* 10.6 Write unit tests for Pipeline runner
    - Assert fixed stage order
    - Assert exit code `0` on full success, `1` on any stage failure
    - Assert `KeyboardInterrupt` is caught and exits non-zero
    - _Requirements: 7.1, 7.3, 7.5_

- [ ] 11. Final checkpoint — Ensure all tests pass
  - Ensure all tests pass, ask the user if questions arise.

## Notes

- Tasks marked with `*` are optional and can be skipped for a faster MVP
- Each task references specific requirements for traceability
- Property tests use `hypothesis` with `@settings(max_examples=100)` and a comment referencing the property number
- All mocking uses `unittest.mock` (`MagicMock`, `patch`, `patch.dict`)
- Existing scripts (`main.py`, `build-docker-image.py`, `buikd-az-storage.py`) are refactored into stage classes; they are not deleted until the pipeline is verified working
