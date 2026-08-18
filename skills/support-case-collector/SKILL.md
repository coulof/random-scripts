---
name: support-case-collector
description: Collect, inspect, auto-probe, and format comprehensive support cases and tickets for SUSE Rancher, Longhorn, RKE/RKE2/K3s, and Kubernetes clusters. Use when the user wants to create a support case, collect cluster details for troubleshooting, structure a ticket description, draft an incident/issue report, or run collect-case-info.
---

# Support Case Collector

Collects environment details (via `kubectl` auto-probing, Lima VMs, or interactive queries) and structured ticket descriptions to produce ready-to-submit support cases for **SUSE Rancher**, **Longhorn**, and **Kubernetes** downstream clusters.

---

## Required Support Case Schema

Every support case follows this standardized template:

```text
Rancher Cluster:
Rancher version: <version>
Number of nodes: <number>
Node OS version: <os version>

Downstream Cluster:
Number of Downstream clusters: <number>
Node OS: <os version>
RKE/RKE2/K3S version: <version>
Kubernetes version: <version>
CNI: <cni>

Longhorn:
Longhorn version: <version>
CPU per node: <cpu>
Memory per node: <memory>
Disk type: HDD/SSD/NVMe
Network bandwidth between the nodes: <bandwidth>

Other:
Underlying Infrastructure: AWS/GCE, EKS/GKE, VMWare/KVM, Baremetal
Any 3rd party software installed on the nodes: <software or None>
Customer’s main time zone: <timezone, e.g. CEST (UTC+02:00)>


The ticket Description is : 
Issue description:
<text>

Business impact:
<text>

Troubleshooting steps:
<text>

Repro steps:

step 1
step 2

Workaround:
Is a workaround available and implemented? yes/no
What is the workaround:
<text>

Actual behavior:
<text>

Expected behavior:
<text>

Files, logs, traces:
<text>

Additional notes:
<text>
```

---

## Workflow: Assisting the User with Case Creation

When a user wants to create a case, follow this interactive flow:

### 1. Auto-Probe Cluster Environment (if available)
Check if `kubectl` or a Lima VM is available:
* If a custom kubeconfig exists, pass `-k <path/to/kubeconfig.yaml>`.
* If connecting through a Lima VM (e.g., VPN VM like `vpn-vm`), pass `--lima vpn-vm`.
* Run `./collect-case-info -a -k <kubeconfig> [--lima <vm>] -q --json`
* Extracted data:
  - **Node count & OS**: `status.nodeInfo.osImage` + `status.nodeInfo.kernelVersion`
  - **K8s & Distro version**: RKE2 / K3s / RKE / kubelet version
  - **CNI**: Look for Calico, Cilium, Canal, Flannel, AWS VPC CNI, Kube-OVN daemonsets
  - **Longhorn version**: Image tag from `longhorn-system` namespace
  - **Rancher version**: Image tag from `cattle-system` namespace or cluster agent
  - **Node CPU & Memory**: Average capacity from node specs
  - **Underlying Infrastructure**: Harvester HCI, AWS, GCE, Azure, VMWare, Cloud, Baremetal
  - **3rd-Party Agents**: CrowdStrike Falcon, Datadog, Prisma, Dynatrace, Wiz, NeuVector, etc.

### 2. Interview & Extract Ticket Information
If the user provides an unstructured issue description, log output, or error snippet:
* Extract what you can (error messages, affected workloads, versions, timestamps).
* Prompt the user for missing details:
  - **Business impact**: Severity, production vs staging, workload downtime, blocked operations.
  - **Repro steps**: Step-by-step instructions to reproduce.
  - **Workaround**: Is a workaround available/implemented? What is it?
  - **Actual vs. Expected behavior**: What is currently happening vs what should happen.
  - **Underlying hardware/network**: Disk type (HDD/SSD/NVMe), network bandwidth (10G/1G), cloud/baremetal infra.

### 3. Generate and Deliver Case
* Output the complete formatted text in the standard template format.
* Optionally save to a file (e.g. `support-case-<timestamp>.md`) or copy to clipboard (`-c`).
* Optionally compile to a branded PDF using `md2pdf <file>.md --theme suse`.

---

## CLI Helper Tool: `collect-case-info`

The repository includes a dedicated CLI helper `collect-case-info`:

```bash
# Generate empty template to stdout
./collect-case-info -t -q

# Auto-probe using specific kubeconfig
./collect-case-info -a -k /path/to/cluster-kubeconfig.yaml -q

# Auto-probe via a Lima VM (e.g. vpn-vm)
./collect-case-info -a --lima vpn-vm -k /path/to/rke2-kubeconfig.yaml -q

# Run interactive wizard in terminal with clipboard copy
./collect-case-info -i -c

# Auto-probe and compile directly to a SUSE-themed PDF
./collect-case-info -a --lima vpn-vm -k cluster.yaml --pdf -o case.md
```

### Options Reference
* `-a`, `--auto`: Auto-probe active `kubectl` context for environment details.
* `-k`, `--kubeconfig <path>`: Path to kubeconfig file (also respects `$KUBECONFIG`).
* `--lima <vm>`: Execute `kubectl` queries inside the specified Lima VM instance (e.g. `vpn-vm`).
* `--context <name>`: Specific context name inside the kubeconfig.
* `--insecure`: Skip TLS certificate verification (`--insecure-skip-tls-verify`).
* `-i`, `--interactive`: Run step-by-step interactive CLI wizard.
* `-t`, `--template`: Generate an empty template skeleton.
* `-c`, `--clipboard`: Copy generated case markdown to system clipboard (`pbcopy`/`xclip`/`wl-copy`).
* `-e`, `--editor`: Open `$EDITOR` for multi-line text input fields.
* `-o`, `--output <file>`: Write case markdown to file.
* `-q`, `--quiet`: Suppress headers and banners (clean machine-readable output).
* `--json`: Export case structure as JSON.
* `--pdf`: Compile to PDF using `md2pdf` (defaults to `--theme suse`).
