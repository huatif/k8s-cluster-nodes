# CKS Kubernetes Lab Setup

This repository contains the Terraform and bootstrap scripts for a two-node Ubuntu Kubernetes lab on AWS.

## Repository structure

- `cks-lab/ec2-k8s-lab/` - Terraform to create the control-plane and worker EC2 instances in AWS
- `cks-lab/0.control-plane.sh` - control-plane bootstrap script for Ubuntu nodes
- `cks-lab/2.worker-node.sh` - worker bootstrap script for Ubuntu nodes
- `calico.yaml` - Calico manifest used to install the CNI plugin
- `notes.yaml` - SSH access and join command notes for the environment

## Prerequisites

- AWS account with permissions to create EC2, VPC, subnets, security groups
- SSH key pair available in AWS and locally (`cks-learning.pem`)
- Terraform installed locally
- Windows PowerShell or Linux/macOS shell for SSH/`scp`
- `kubectl` installed on the control plane and optionally locally

## Setup steps

### 1. Deploy the EC2 instances with Terraform

```powershell
cd c:\Users\amehan\Documents\CKS-LAB\cks-lab\ec2-k8s-lab
terraform init
terraform apply
```

After apply completes, note the public IPs for:
- control plane node
- worker node

### 2. Bootstrap the control plane

Copy the bootstrap script and run it on the control plane:

```powershell
scp -i "C:\key\cks-learning.pem" "C:\Users\amehan\Documents\CKS-LAB\cks-lab\0.control-plane.sh" ubuntu@<CONTROL_PLANE_PUBLIC_IP>:/home/ubuntu/
ssh -i "C:\key\cks-learning.pem" ubuntu@<CONTROL_PLANE_PUBLIC_IP> "chmod +x /home/ubuntu/0.control-plane.sh && sudo bash /home/ubuntu/0.control-plane.sh"
```

This script does the following:
- disables swap and updates `/etc/fstab`
- installs containerd, kubelet, kubeadm, kubectl
- configures `containerd` with `SystemdCgroup=true`
- enables required kernel modules and sysctl settings
- runs `kubeadm init --pod-network-cidr=192.168.0.0/16`
- installs Calico CNI
- generates `/join-command.sh` for the worker

> The control plane is deployed by running this script remotely over SSH from your local machine.

### 3. Bootstrap the worker node

Copy the worker bootstrap script and run it on the worker:

```powershell
scp -i "C:\key\cks-learning.pem" "C:\Users\amehan\Documents\CKS-LAB\cks-lab\2.worker-node.sh" ubuntu@<WORKER_PUBLIC_IP>:/home/ubuntu/
ssh -i "C:\key\cks-learning.pem" ubuntu@<WORKER_PUBLIC_IP> "chmod +x /home/ubuntu/2.worker-node.sh && sudo bash /home/ubuntu/2.worker-node.sh"
```

Or use the PowerShell pipeline remote deployment command that you used:

```powershell
Get-Content -Raw "C:\Users\amehan\Documents\CKS-LAB\cks-lab\2.worker-node.sh" |
ssh -i "C:\key\cks-learning.pem" ubuntu@<WORKER_PUBLIC_IP> 'cat > /home/ubuntu/2.worker-node.sh && chmod +x /home/ubuntu/2.worker-node.sh && sudo bash /home/ubuntu/2.worker-node.sh'
```

This script performs the same node preparation as the control plane, without running `kubeadm init`.

> The worker node is also deployed remotely using this SSH script execution method.

### 4. Join the worker to the cluster

On the control plane, get or regenerate the join command:

```bash
sudo kubeadm token create --print-join-command
```

Run the output command on the worker node as root:

```bash
sudo kubeadm join <CONTROL_PLANE_PRIVATE_IP>:6443 --token <TOKEN> --discovery-token-ca-cert-hash sha256:<HASH>
```

### 5. Verify the cluster

On the control plane:

```bash
sudo KUBECONFIG=/etc/kubernetes/admin.conf kubectl get nodes
sudo KUBECONFIG=/etc/kubernetes/admin.conf kubectl get pods -n kube-system -o wide
```

Check that both nodes are `Ready` and that Calico and kube-system pods are running.

## Kubernetes admin access from Windows

If you want to use `kubectl` from your Windows machine:

1. Copy the admin kubeconfig from the control plane to your local machine:

```powershell
scp -i "C:\key\cks-learning.pem" ubuntu@<CONTROL_PLANE_PUBLIC_IP>:~/admin.conf $env:USERPROFILE\.kube\config
```

2. Edit the local config file and update the `server:` entry to use the control plane public IP:

```yaml
server: https://<CONTROL_PLANE_PUBLIC_IP>:6443
```

3. Do not modify `certificate-authority-data`, `client-certificate-data`, or `client-key-data`.

4. Test local kubectl:

```powershell
kubectl config view
kubectl get nodes
```

## Important notes

### Hostname consistency

Kubernetes node names and Calico node names must match the underlying Linux hostname. If you changed hostnames during setup, restore them to the original AWS names and restart kubelet:

```bash
sudo hostnamectl set-hostname ip-172-31-14-177   # control plane
sudo hostnamectl set-hostname ip-172-31-8-82     # worker
sudo systemctl restart kubelet
sudo systemctl restart containerd
```

### Calico and BGP

The Calico manifest is configured for `k8s,bgp` with IP-in-IP enabled. If Calico `calico-node` remains `NotReady`, inspect:

```bash
sudo KUBECONFIG=/etc/kubernetes/admin.conf kubectl get pods -n kube-system
sudo KUBECONFIG=/etc/kubernetes/admin.conf kubectl describe pod -n kube-system calico-node-<pod-name>
sudo KUBECONFIG=/etc/kubernetes/admin.conf kubectl logs -n kube-system calico-node-<pod-name> -c calico-node
```

If you see a stale Calico node object from a previous hostname, delete it:

```bash
sudo KUBECONFIG=/etc/kubernetes/admin.conf kubectl get caliconodes
sudo KUBECONFIG=/etc/kubernetes/admin.conf kubectl delete caliconode <old-node-name>
```

Then restart Calico:

```bash
sudo KUBECONFIG=/etc/kubernetes/admin.conf kubectl rollout restart daemonset calico-node -n kube-system
```

### Common troubleshooting

- Use `admin.conf` on the control plane for full privileges.
- On a worker, `KUBECONFIG=/etc/kubernetes/kubelet.conf kubectl` is limited by node RBAC and may not read pod logs.
- If a node is `NotReady`, check both kubelet and Calico pod status.
- If you change the hostname, restart kubelet and containerd.

## Scripts and commands reference

- `cks-lab/0.control-plane.sh` — run on the control plane to install prerequisites, init cluster, install Calico, and print join command.
- `cks-lab/2.worker-node.sh` — run on the worker to install prerequisites and prepare the node for `kubeadm join`.
- `cks-lab/ec2-k8s-lab/main.tf` — Terraform EC2 provisioning script.
- `cks-lab/ec2-k8s-lab/variables.tf` — Terraform variable definitions.
- `cks-lab/ec2-k8s-lab/outputs.tf` — Terraform outputs for instance IDs and IPs.
- `calico.yaml` — Calico manifest used for manual or custom installation.

## Cleanup

When you are finished, destroy the AWS resources to avoid charges:

```powershell
cd c:\Users\amehan\Documents\CKS-LAB\cks-lab\ec2-k8s-lab
terraform destroy
```
