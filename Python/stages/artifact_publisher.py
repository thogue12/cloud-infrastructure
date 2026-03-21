import os
from .base import Stage, StageResult, PipelineContext


class ArtifactPublisher(Stage):
    name = "ArtifactPublisher"

    def run(self, ctx: PipelineContext) -> StageResult:
        token = os.getenv("GITHUB_TOKEN")
        if not token:
            return StageResult(
                success=False,
                message="GITHUB_TOKEN environment variable is not set",
            )

        if not ctx.tfvars_path:
            return StageResult(success=False, message="No tfvars_path in context")

        try:
            from github import Github, GithubException
        except ImportError as e:
            return StageResult(success=False, message=f"Missing PyGithub dependency: {e}")

        try:
            with open(ctx.tfvars_path, "rb") as f:
                content = f.read()
        except OSError as e:
            return StageResult(success=False, message=f"Failed to read tfvars file: {e}")

        try:
            gh = Github(token)
            repo = gh.get_repo(ctx.github_repo)
            remote_path = os.path.basename(ctx.tfvars_path)
            commit_message = f"chore: update tfvars for deployment"

            try:
                existing = repo.get_contents(remote_path, ref=ctx.github_branch)
                result = repo.update_file(
                    path=remote_path,
                    message=commit_message,
                    content=content,
                    sha=existing.sha,
                    branch=ctx.github_branch,
                )
            except GithubException as e:
                if e.status == 404:
                    result = repo.create_file(
                        path=remote_path,
                        message=commit_message,
                        content=content,
                        branch=ctx.github_branch,
                    )
                else:
                    raise

            commit_sha = result["commit"].sha
            ctx.commit_sha = commit_sha
            print(f"[ArtifactPublisher] Pushed to {ctx.github_branch} — commit: {commit_sha}")
            return StageResult(success=True, message=f"tfvars pushed to {ctx.github_branch} ({commit_sha})")

        except Exception as e:
            return StageResult(success=False, message=f"GitHub push failed: {e}")
