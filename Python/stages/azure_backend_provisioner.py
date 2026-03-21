from .base import Stage, StageResult, PipelineContext, BackendConfig

CONTAINER_NAME = "tfstate"
BLOB_KEY = "terraform.tfstate"
LOCATION = "eastus"


class AzureBackendProvisioner(Stage):
    name = "AzureBackendProvisioner"

    def run(self, ctx: PipelineContext) -> StageResult:
        try:
            from azure.identity import DefaultAzureCredential
            from azure.mgmt.storage import StorageManagementClient
            from azure.mgmt.storage.models import StorageAccountCreateParameters, Sku, Kind
            from azure.core.exceptions import AzureError
        except ImportError as e:
            return StageResult(success=False, message=f"Missing Azure SDK dependency: {e}")

        if not ctx.subscription_id:
            return StageResult(success=False, message="subscription_id is required for Azure backend provisioning")
        if not ctx.storage_account_name:
            return StageResult(success=False, message="storage_account_name is required for Azure backend provisioning")
        if not ctx.resource_group_name:
            return StageResult(success=False, message="resource_group_name is required for Azure backend provisioning")

        try:
            credential = DefaultAzureCredential()
            client = StorageManagementClient(credential, ctx.subscription_id)

            # Check if storage account already exists
            existing = list(client.storage_accounts.list_by_resource_group(ctx.resource_group_name))
            account_names = [a.name for a in existing]

            if ctx.storage_account_name not in account_names:
                print(f"[AzureBackendProvisioner] Creating storage account: {ctx.storage_account_name}")
                poller = client.storage_accounts.begin_create(
                    ctx.resource_group_name,
                    ctx.storage_account_name,
                    StorageAccountCreateParameters(
                        sku=Sku(name="Standard_LRS"),
                        kind=Kind.STORAGE_V2,
                        location=LOCATION,
                    ),
                )
                poller.result()

                # Create blob container
                client.blob_containers.create(
                    ctx.resource_group_name,
                    ctx.storage_account_name,
                    CONTAINER_NAME,
                    {},
                )
                print(f"[AzureBackendProvisioner] Created container: {CONTAINER_NAME}")
            else:
                print(f"[AzureBackendProvisioner] Storage account already exists, skipping creation.")

            ctx.backend_config = BackendConfig(
                provider="azure",
                storage_account=ctx.storage_account_name,
                container_name=CONTAINER_NAME,
                blob_key=BLOB_KEY,
                resource_group=ctx.resource_group_name,
            )
            return StageResult(success=True, message="Azure backend provisioned successfully")

        except Exception as e:
            return StageResult(success=False, message=f"Azure backend provisioning failed: {e}")
