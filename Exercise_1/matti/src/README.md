# Exercise 1 — Cloud Infrastructure (source)

Terraform-provisioned AWS baseline VM running a containerized Tic-Tac-Toe app.

## Contents

| Path | What it is |
|------|------------|
| `main.tf` | Terraform: provider, AMI lookup, security group, EC2 instance |
| `tic-tac-toe/` | The app deployed on the VM |
| `tic-tac-toe/backend/` | FastAPI backend (`main.py`, `Dockerfile`, `requirements.txt`) |
| `tic-tac-toe/frontend/` | Static frontend (`index.html`) |
| `tic-tac-toe/docker-compose.yml` | Brings up backend + frontend |
| `Makefile` | Helper to zip the app bundle |

## Run

```bash
terraform init      # run from this src/ directory
terraform apply
```

Security group opens ports 22 (SSH), 80 (frontend), 8000 (backend).

> Note: Terraform state (`*.tfstate`, `.terraform/`) lives here but is gitignored
> and excluded from the submission zip.
