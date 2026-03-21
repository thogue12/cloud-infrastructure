import os
import shutil
from .base import Stage, StageResult, PipelineContext

REPO_URL = "https://github.com/thogue12/cloud-platform-pipelines.git"
BRANCH = "main"
IMAGE_NAME = "security-scanner"


class DockerBuilder(Stage):
    name = "DockerBuilder"

    def run(self, ctx: PipelineContext) -> StageResult:
        try:
            import docker
            from docker.errors import BuildError, APIError
            from git import Repo
            from git.exc import GitCommandError
        except ImportError as e:
            return StageResult(success=False, message=f"Missing dependency: {e}")

        local_path = os.getcwd()
        clone_path = os.path.join(local_path, "workspace_build")
        dockerfile_path = os.path.join(clone_path, "Docker-Images", "security-scanner", "Dockerfile")

        # Remove existing clone directory
        if os.path.exists(clone_path):
            try:
                print(f"[DockerBuilder] Removing existing directory: {clone_path}")
                shutil.rmtree(clone_path)
            except PermissionError as e:
                return StageResult(success=False, message=f"Permission denied removing clone dir: {e}")

        # Clone the repository
        try:
            print(f"[DockerBuilder] Cloning {REPO_URL} on branch {BRANCH}...")
            Repo.clone_from(REPO_URL, clone_path, branch=BRANCH)
            print("[DockerBuilder] Repository cloned successfully.")
        except GitCommandError as e:
            return StageResult(success=False, message=f"Git clone failed: {e}")

        # Build the Docker image
        try:
            print(f"[DockerBuilder] Building image '{IMAGE_NAME}'...")
            client = docker.from_env()

            # Stop and remove any containers using the image
            existing_containers = client.containers.list(all=True, filters={"ancestor": IMAGE_NAME})
            for c in existing_containers:
                print(f"[DockerBuilder] Stopping and removing container: {c.id[:12]}")
                c.stop(timeout=5)
                c.remove(force=True)

            # Remove the stale image so we always build fresh
            try:
                client.images.remove(IMAGE_NAME, force=True)
                print(f"[DockerBuilder] Removed existing image '{IMAGE_NAME}'.")
            except docker.errors.ImageNotFound:
                pass  # nothing to remove

            image, build_logs = client.images.build(
                path=clone_path,
                dockerfile=dockerfile_path,
                tag=IMAGE_NAME,
            )
            for chunk in build_logs:
                if "stream" in chunk:
                    print(chunk["stream"].strip())
            print(f"[DockerBuilder] Image '{IMAGE_NAME}' built successfully.")
        except BuildError as e:
            error_lines = [l["error"] for l in e.build_log if "error" in l]
            return StageResult(success=False, message=f"Docker build failed: {'; '.join(error_lines)}")
        except APIError as e:
            return StageResult(success=False, message=f"Docker API error: {e}")

        # Start the container in detached mode
        # CMD ["tail", "-f", "/dev/null"] in the Dockerfile keeps it alive
        try:
            import time
            terraform_path = os.path.abspath(os.getcwd())
            container = client.containers.run(
                image=IMAGE_NAME,
                detach=True,
                volumes={terraform_path: {"bind": "/terraform", "mode": "ro"}},
            )
            ctx.container_id = container.id
            print(f"[DockerBuilder] Container started: {ctx.container_id[:12]}")

            # Wait up to 10 seconds for the container to reach running state
            for _ in range(10):
                container.reload()
                if container.status == "running":
                    break
                time.sleep(1)
            else:
                logs = container.logs().decode("utf-8", errors="replace")
                return StageResult(
                    success=False,
                    message=f"Container exited before becoming ready. Logs:\n{logs}",
                )

            print(f"[DockerBuilder] Container is running: {ctx.container_id[:12]}")
        except Exception as e:
            return StageResult(success=False, message=f"Failed to start container: {e}")

        return StageResult(success=True, message=f"Docker image built and container started: {ctx.container_id[:12]}")
