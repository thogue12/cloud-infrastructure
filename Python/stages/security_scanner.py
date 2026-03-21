import subprocess
from .base import Stage, StageResult, PipelineContext, ScanResult

SCAN_TOOLS = ["tflint", "checkov", "trivy"]


def _parse_findings(output: str) -> list:
    """Extract non-empty lines from tool output as findings."""
    return [line for line in output.splitlines() if line.strip()]


class SecurityScanner(Stage):
    name = "SecurityScanner"

    def _run_scan(self, tool: str, container_id: str) -> ScanResult:
        """Execute a single scan tool via docker exec and return a ScanResult."""
        if tool == "tflint":
            cmd = ["docker", "exec", container_id, "tflint", "--chdir=/terraform"]
        elif tool == "checkov":
            cmd = ["docker", "exec", container_id, "checkov", "-d", "/terraform", "--quiet"]
        elif tool == "trivy":
            cmd = ["docker", "exec", container_id, "trivy", "config", "/terraform", "--exit-code", "1"]
        else:
            cmd = ["docker", "exec", container_id, tool]

        try:
            result = subprocess.run(cmd, capture_output=True, text=True)
            passed = result.returncode == 0
            output = result.stdout + result.stderr
            findings = _parse_findings(output) if not passed else []
            return ScanResult(tool=tool, passed=passed, findings=findings)
        except Exception as e:
            return ScanResult(tool=tool, passed=False, findings=[str(e)])

    def run(self, ctx: PipelineContext) -> StageResult:
        if not ctx.container_id:
            return StageResult(success=False, message="No container ID in context — DockerBuilder must run first")

        all_passed = True
        for tool in SCAN_TOOLS:
            scan_result = self._run_scan(tool, ctx.container_id)
            ctx.scan_results.append(scan_result)
            status = "PASS" if scan_result.passed else "FAIL"
            print(f"[SecurityScanner] {tool}: {status}")
            if not scan_result.passed:
                all_passed = False
                for finding in scan_result.findings:
                    print(f"  {finding}")

        if not all_passed:
            failed_tools = [r.tool for r in ctx.scan_results if not r.passed]
            return StageResult(
                success=False,
                message=f"Security gate failed. Failing tools: {', '.join(failed_tools)}",
            )

        return StageResult(success=True, message="All security scans passed")
