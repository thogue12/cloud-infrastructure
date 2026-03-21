from .base import Stage, StageResult, PipelineContext, BackendConfig

STATE_KEY = "terraform.tfstate"


class AwsBackendProvisioner(Stage):
    name = "AwsBackendProvisioner"

    def run(self, ctx: PipelineContext) -> StageResult:
        try:
            import boto3
            from botocore.exceptions import ClientError
        except ImportError as e:
            return StageResult(success=False, message=f"Missing AWS SDK dependency: {e}")

        if not ctx.s3_bucket_name:
            return StageResult(success=False, message="s3_bucket_name is required for AWS backend provisioning")
        if not ctx.aws_region:
            return StageResult(success=False, message="aws_region is required for AWS backend provisioning")

        try:
            s3 = boto3.client("s3", region_name=ctx.aws_region)

            # Check if bucket already exists
            bucket_exists = False
            try:
                s3.head_bucket(Bucket=ctx.s3_bucket_name)
                bucket_exists = True
            except ClientError as e:
                error_code = e.response["Error"]["Code"]
                if error_code not in ("404", "NoSuchBucket"):
                    return StageResult(success=False, message=f"AWS error checking bucket: {e}")

            if not bucket_exists:
                print(f"[AwsBackendProvisioner] Creating S3 bucket: {ctx.s3_bucket_name}")
                create_kwargs = {
                    "Bucket": ctx.s3_bucket_name,
                    "ObjectLockEnabledForBucket": True,
                }
                # us-east-1 does not accept a LocationConstraint
                if ctx.aws_region != "us-east-1":
                    create_kwargs["CreateBucketConfiguration"] = {
                        "LocationConstraint": ctx.aws_region
                    }
                s3.create_bucket(**create_kwargs)

                # Enable versioning (required for object lock)
                s3.put_bucket_versioning(
                    Bucket=ctx.s3_bucket_name,
                    VersioningConfiguration={"Status": "Enabled"},
                )
                print(f"[AwsBackendProvisioner] Bucket created with native state locking enabled.")
            else:
                print(f"[AwsBackendProvisioner] S3 bucket already exists, skipping creation.")

            ctx.backend_config = BackendConfig(
                provider="aws",
                bucket=ctx.s3_bucket_name,
                key=STATE_KEY,
                region=ctx.aws_region,
            )
            return StageResult(success=True, message="AWS backend provisioned successfully")

        except Exception as e:
            return StageResult(success=False, message=f"AWS backend provisioning failed: {e}")
