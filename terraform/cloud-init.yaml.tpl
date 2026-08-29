#cloud-config
# Applied on first boot when VM is created via Terraform custom_data.
# Re-run ansible/bootstrap.yml on existing VMs instead of replacing the VM.

package_update: true
packages:
  - docker.io
  - docker-compose-plugin
  - git
  - nginx
  - libxml2-utils

groups:
  - docker

users:
  - default
  - name: ${admin_username}
    groups: docker
    sudo: ALL=(ALL) NOPASSWD:ALL

runcmd:
  - systemctl enable docker
  - systemctl start docker
  - systemctl enable nginx
