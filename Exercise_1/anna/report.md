# EX01 Report: Cloud Infrastructure

**Student Name:** [leave this exactly like this]  
**Student ID:** `leave this exactly like this`  

---

## Task 1 - Virtual Machines and Baseline Execution

### 1.1 Provisioning the EC2 instance with Terraform

Terraform is used to describe infrastructure as code. Instead of clicking through the AWS console, we describe the end state we want in `main.tf`, and Terraform works out the steps to get there.

Commands: 

- `terraform init` - prepares the folder: downloads the AWS provider plugin into `.terraform/` and pins its version in `.terraform.lock.hcl` (doesn't touch AWS yet) 
- `terraform fmt` / `terraform validate` - fixes indentation and spacing / checks the syntax and that references point to things that exist
- `terraform plan` - compares our file with what already exists in AWS and shows the difference, without changing anything
- `terraform apply` - makes the changes
- `terraform destroy` - deletes everything Terraform created

Terraform remembers what it created in `terraform.tfstate`. That is how `plan` knows what already exists, and it's also why the state file is gitignored and not part of the submission.

**Provider.** First we specify which cloud we'll be talking to. This tells Terraform to download the AWS provider plugin from `hashicorp/aws`. `~> 6.0` means any 6.x version, but never 7.0, so a future major version can't break the config. Every resource we define later gets created in `us-east-1` (US East).

```hcl
terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
  }
}

provider "aws" {
  region = "us-east-1"
}
```

**AMI.** An AMI (Amazon Machine Image) is the disk image a VM boots from (OS + preinstalled software). We need Amazon Linux 2023. AMI IDs differ per region and change with every update, so instead of hardcoding an ID that would go stale, we use a `data` block. A `data` block looks something up without creating anything, while a `resource` creates something. `owners = ["amazon"]` only considers AMIs published by Amazon, and `most_recent` picks the newest match. The filter picks the standard image (not "minimal"), any version, and `x86_64`, because t2.micro is an Intel instance and an arm64 image wouldn't boot. During `plan` it resolved to `ami-0567589d25e06853e`.

```hcl
data "aws_ami" "al2023" {
  most_recent = true
  owners      = ["amazon"]
  filter {
    name   = "name"
    values = ["al2023-ami-2023.*-x86_64"]
  }
}
```

**Security group.** The security group is the VM's firewall: it blocks all incoming traffic unless a rule allows it. Before writing it, we had to check what the VM actually needs:

1. SSH uses TCP on port 22, so we need that to log in.
2. The tic-tac-toe backend runs on the VM and we send requests to it from our laptops. It listens on port 8000 (according to the Dockerfile).
3. The VM needs to download Python packages and Docker images from the internet. Security groups are stateful, so if someone connects in on port 22, the replies are allowed back out automatically and need no rule. But when the VM starts a connection itself (pip reaching PyPI, Docker pulling an image), that's new outgoing traffic, and it needs an egress rule. A security group created in the AWS console allows all outbound traffic by default, but Terraform removes that default. Without an explicit egress rule, the VM couldn't download anything.

`ingress` is an inbound rule (traffic coming into the VM) and `egress` an outbound rule (traffic going out of it). `from_port`/`to_port` is a range of ports, and the same number twice means exactly one port. `cidr_blocks` says who may connect: `0.0.0.0/0` means any IP address. `protocol = "-1"` with ports 0/0 means all protocols and all ports.

```hcl
resource "aws_security_group" "app" {
  name = "ex1-tictactoe"

  ingress { # SSH
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress { # tic-tac-toe backend
    from_port   = 8000
    to_port     = 8000
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress { # everything out, so the VM can download packages
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}
```

We allowed SSH from anywhere because the laptop's IP changes (home vs. university). In production you would restrict it to your own address, e.g. `"<your-ip>/32"`.

**The VM.** `ami` references the AMI found by the data block. `instance_type` is the VM's size: t2.micro has 1 vCPU and about 1 GiB of RAM (confirmed on the VM with `nproc` → 1 and `free -h` → 957 MiB). `vpc_security_group_ids` attaches the security group to the VM; without it, the firewall would exist but protect nothing. `key_name = "vockey"` is the name of a key pair that already exists in the AWS Academy account: AWS puts its public key onto the VM, and we hold the matching private key (`labsuser.pem`).

```hcl
resource "aws_instance" "vm" {
  ami                    = data.aws_ami.al2023.id
  instance_type          = "t2.micro"
  vpc_security_group_ids = [aws_security_group.app.id]
  key_name               = "vockey"
}

output "public_ip" {
  value = aws_instance.vm.public_ip
}
```

These references also define the order: because the VM uses `data.aws_ami.al2023.id` and `aws_security_group.app.id`, Terraform builds a dependency graph and does the AMI lookup and creates the security group before the VM, even though the security group is written below it in the file.

The `output` block prints the VM's public IP at the end of `apply` (and anytime with `terraform output public_ip`). It follows the same reference pattern: resource type, our name for it, attribute. `terraform plan` showed `Plan: 2 to add, 0 to change, 0 to destroy` (the security group and the VM), and `apply` gave us:

```
public_ip = "54.145.234.105"
```

This IP isn't permanent. AWS gives the VM a random public IP from its pool, so after a `destroy` and a new `apply` (or a stop/start), the VM gets a different one. A fixed IP would need an extra resource (an Elastic IP).

### 1.2 Setup and execution

There are two different credentials involved:

- **Terraform → AWS:** the AWS Academy credentials in `~/.aws/credentials`. They're temporary (they include a session token), so they have to be pasted again every lab session.
- **Us → VM:** the SSH private key `labsuser.pem`, kept in `~/.ssh/` with `chmod 400` (SSH refuses keys that other users can read) and never in the public repository.

```bash
ssh -i ~/.ssh/labsuser.pem ec2-user@54.145.234.105
```

On the first connection SSH asks whether to trust the server's host key. This is the server proving its identity to us (protection against man-in-the-middle attacks), and after confirming, the key is saved in `~/.ssh/known_hosts`.

We copied only the app to the VM:

```bash
scp -i ~/.ssh/labsuser.pem -r app ec2-user@54.145.234.105:~
```

Amazon Linux comes with Python but without pip, so the dependencies had to be installed by hand before starting the backend:

```bash
sudo dnf install -y python3-pip
pip3 install -r app/backend/requirements.txt
cd app/backend
python3 -m uvicorn main:app --host 0.0.0.0 --port 8000
```

`--host 0.0.0.0` makes uvicorn accept connections from outside the VM; without it, the app would only be reachable from the VM itself, even with port 8000 open in the security group. We then tested it from the laptop by sending a request to `http://54.145.234.105:8000/api/render-bitmap` and opening the returned board image.

### 1.3 Measuring performance

The workload parameter is `size`, the side length of the rendered board image in pixels (300×300 = 90,000 pixels, 3000×3000 = 9 million). `bench.sh` sends 5 requests per size and times each one with `time`. The host is passed as an argument, so the same script runs on the VM (`localhost`) and on the laptop (the public IP):

```bash
#!/usr/bin/env bash
HOST=${1:-localhost}

for SIZE in 300 1000 2000 3000; do
  for RUN in 1 2 3 4 5; do
    echo "size=$SIZE run=$RUN"
    time curl -s -o /dev/null -X POST "http://$HOST:8000/api/render-bitmap?size=$SIZE" \
      -H "Content-Type: application/json" \
      -d '{"board":["X","O","X","O","X","O","O","X","X"],"winner":"X"}'
  done
done
```

Running it on the VM against `localhost` measures (almost) pure compute. Running it from the laptop in Innsbruck adds the network trip to us-east-1 and back. The difference between the two is the network.

**Raw results (`real` time in seconds):**

| size | where | run 1 | run 2 | run 3 | run 4 | run 5 | average |
| :--- | :--- | ---: | ---: | ---: | ---: | ---: | ---: |
| 300 | VM | 0.011 | 0.009 | 0.009 | 0.009 | 0.009 | **0.009** |
| 300 | laptop | 0.355 | 0.405 | 0.453 | 0.343 | 0.335 | **0.378** |
| 1000 | VM | 0.037 | 0.035 | 0.036 | 0.034 | 0.035 | **0.035** |
| 1000 | laptop | 0.517 | 0.516 | 0.529 | 0.516 | 0.531 | **0.522** |
| 2000 | VM | 0.122 | 0.116 | 0.115 | 0.114 | 0.115 | **0.116** |
| 2000 | laptop | 0.915 | 0.966 | 0.749 | 0.808 | 0.764 | **0.840** |
| 3000 | VM | 0.262 | 0.270 | 0.269 | 0.268 | 0.270 | **0.268** |
| 3000 | laptop | 0.969 | 0.953 | 0.980 | 0.904 | 1.051 | **0.971** |

**Compute vs. network (averages):**

| size | VM (compute) | laptop (total) | network = total − compute | network share |
| :--- | ---: | ---: | ---: | ---: |
| 300 | 0.009 s | 0.378 s | 0.369 s | 97% |
| 1000 | 0.035 s | 0.522 s | 0.487 s | 93% |
| 2000 | 0.116 s | 0.840 s | 0.724 s | 86% |
| 3000 | 0.268 s | 0.971 s | 0.703 s | 72% |

**Observations:**

1. **The network dominates.** For small images, 97% of the time we waited was the trip to Virginia, not the computation. Even at the largest size it's still about 70%. Innsbruck to us-east-1 is roughly 7,000 km, and every request needs several round trips (opening the TCP connection, then request and response), which is a fixed cost no matter how small the image is. A faster VM would barely help for small requests.
2. **The network part also grows with the size** (0.37 s → about 0.7 s), because transfer time ≈ latency + size / bandwidth: the latency stays the same, but a bigger image is a bigger response to send back.
3. **Jitter comes from the network, not the VM.** On the VM, the 5 runs are almost identical (e.g. 0.114–0.122 s at 2000 px). From the laptop, the same request varied by up to 0.2 s (e.g. 0.749–0.966 s at 2000 px). That's why we repeated each measurement and use the average.
4. **Compute scales with the number of pixels once the work is big enough.** From 2000 to 3000 px, the pixels grow 2.25× and the time 2.3×. At small sizes, the fixed per-request overhead (handling the HTTP request, parsing the JSON) hides this: from 300 to 1000 px the pixels grow 11×, but the time only about 4×.


After finishing, the infrastructure is removed with `terraform destroy`.

---

## Task 2 - Containerization with Docker

To run the app on the VM in Task 1, we had to install the requirements by hand. A container, however, packages the app together with everything it needs, and it runs the same everywhere Docker is installed.

### 2.1 The Dockerfile

We used the Dockerfile that comes with our team's tic-tac-toe app:

```dockerfile
FROM python:3.11-slim                                # start from an image that already has Python 3.11
WORKDIR /app                                         # create the folder /app inside the image and work from there
COPY requirements.txt .                              # copy the dependency list in
RUN pip install --no-cache-dir -r requirements.txt   # install the dependencies at build time
COPY main.py .                                       # copy the code
CMD ["uvicorn", "main:app", "--host", "0.0.0.0", "--port", "8000"]   # what runs when a container starts
```

`docker build` follows the recipe and produces an **image** (a snapshot of the app plus its environment). Each line of the Dockerfile becomes a layer, and unchanged layers are cached. That's why `requirements.txt` is copied before `main.py`: if you only change the code, the slow `pip install` layer gets reused. `RUN` happens at build time, `CMD` at run time.

`docker run` starts a **container** from the image. One image can run as many containers at once, like one class and many objects.

**VM vs. container:** a VM virtualises the hardware and runs its own full OS with its own kernel, which is heavy and takes some time to start. A container shares the host's kernel and is just an isolated process, which is light and starts in a second. Containers are isolated by two Linux features:

- **namespaces**: each container gets its own view of processes, network and filesystem, so it can't see the others
- **cgroups**: limits on how much CPU and memory each one may use

### 2.2 Build and run on EC2

**Security group.** Because the task asks for two containers in parallel, we need one port per container on the VM, so we widened the backend rule in `main.tf` and ran `terraform plan` and `terraform apply` (an in-place update of the security group; the VM itself is untouched):

```hcl
ingress {
  from_port   = 8000
  to_port     = 8001
  protocol    = "tcp"
  cidr_blocks = ["0.0.0.0/0"]
}
```

(Our `docker-compose.yml` maps `"8000-8002:8000"`, so it could use up to three ports, but for two containers 8000–8001 is enough.)

**Docker on the VM.** We installed Docker, started the Docker service (the daemon that actually builds images and runs containers) and added `ec2-user` to the `docker` group, so there's no need for `sudo` before every docker command:

```bash
sudo dnf install -y docker
sudo systemctl start docker
sudo usermod -aG docker ec2-user   # takes effect after logging out and in again
```

**Build.** `-t` gives our image a tag, so it is easy to refer to it by name; the dot at the end is the build context (the folder Docker copies files from).

```bash
docker build -t ticktactoe-backend .
```

```
$ docker images
REPOSITORY           TAG       IMAGE ID       CREATED          SIZE
ticktactoe-backend   latest    66074178fe7f   33 seconds ago   174MB
```

Running the same build a second time finished almost instantly, because every step was `CACHED`.

**Run the first container:**

```bash
docker run -d -p 8000:8000 --name ttt1 ticktactoe-backend
```

- `-d`: detached, so the terminal doesn't stay busy
- `-p <VM port>:<container port>`: maps a port on the VM to a port inside the container
- `--name`: gives it a readable name
- `ticktactoe-backend`: which image to start from

**Verify with the logs.** Right after starting, `docker logs ttt1` shows uvicorn starting up. After sending a request from my laptop with curl, the request appears in the log:

```
$ docker logs ttt1
LAMBDA_URL=None
INFO:     Started server process [1]
INFO:     Waiting for application startup.
INFO:     Application startup complete.
INFO:     Uvicorn running on http://0.0.0.0:8000 (Press CTRL+C to quit)
INFO:     <my-ip>:35388 - "POST /api/render-bitmap HTTP/1.1" 200 OK
```

### 2.3 Two containers in parallel

```bash
docker run -d -p 8001:8000 --name ttt2 ticktactoe-backend
```

Only the VM-side port changes. Inside, both containers listen on 8000 without any conflict, because each has its own network namespace. 

**Both are running:**

```
$ docker ps
CONTAINER ID   IMAGE                COMMAND                  STATUS          PORTS                    NAMES
93cf5a33a148   ticktactoe-backend   "uvicorn main:app --…"   Up 18 seconds   0.0.0.0:8001->8000/tcp   ttt2
ed65bd436a8a   ticktactoe-backend   "uvicorn main:app --…"   Up 8 minutes    0.0.0.0:8000->8000/tcp   ttt1
```

**Both serve requests.** Sending a request from my laptop to each port returned `200` for both:

```bash
curl -s -o /dev/null -w "%{http_code}\n" -X POST "http://54.145.234.105:8000/api/render-bitmap" \
  -H "Content-Type: application/json" -d '{"board":["X","O","X","O","X","O","O","X","X"],"winner":"X"}'
curl -s -o /dev/null -w "%{http_code}\n" -X POST "http://54.145.234.105:8001/api/render-bitmap" \
  -H "Content-Type: application/json" -d '{"board":["X","O","X","O","X","O","O","X","X"],"winner":"X"}'
```

and the request shows up in ttt2's log as well:

```
$ docker logs ttt2
...
INFO:     Uvicorn running on http://0.0.0.0:8000 (Press CTRL+C to quit)
INFO:     <my-ip>:35318 - "POST /api/render-bitmap HTTP/1.1" 200 OK
```

### 2.4 Isolation and process management

**Hostnames.** Each container has its own hostname (its container ID), so they're isolated from each other:

```
$ docker exec ttt1 hostname
ed65bd436a8a
$ docker exec ttt2 hostname
93cf5a33a148
```

**Processes from the VM's view.** From the VM, both uvicorns are just ordinary processes running on the VM's kernel, right next to everything else:

```
$ ps aux | grep uvicorn
root   35107  0.2  5.5 144868 54152 ?  Ssl  13:08  0:01 /usr/local/bin/python3.11 /usr/local/bin/uvicorn main:app --host 0.0.0.0 --port 8000
root   35967  0.5  5.2  67460 51692 ?  Ss   13:17  0:00 /usr/local/bin/python3.11 /usr/local/bin/uvicorn main:app --host 0.0.0.0 --port 8000
```

`docker top ttt1` shows the same process (PID 35107) from the VM's perspective.

**Processes from inside the containers.** Inside each container, uvicorn is PID 1 (the arguments in `/proc/1/cmdline` are separated by invisible null characters, which is why they look glued together):

```
$ docker exec ttt1 cat /proc/1/cmdline; echo
/usr/local/bin/python3.11/usr/local/bin/uvicornmain:app--host0.0.0.0--port8000
$ docker exec ttt2 cat /proc/1/cmdline; echo
/usr/local/bin/python3.11/usr/local/bin/uvicornmain:app--host0.0.0.0--port8000
```

The logs say the same: `Started server process [1]`.

| | PID on the VM | PID inside the container |
| :--- | ---: | ---: |
| ttt1's uvicorn | 35107 | 1 |
| ttt2's uvicorn | 35967 | 1 |

So the same process has two different PIDs, depending on who's looking. From the VM's point of view, there are two uvicorn processes; inside each container, uvicorn is the only process it knows about. That's the PID namespace.

**CPU and memory per container.** Before the requests, ttt2 hadn't sent anything yet (`796B / 0B`); after them, both show traffic:

```
# before the curl requests
NAME   CPU %   MEM USAGE / LIMIT     MEM %   NET I/O          PIDS
ttt2   0.13%   34.53MiB / 957.6MiB   3.61%   796B / 0B        1
ttt1   0.14%   38.59MiB / 957.6MiB   4.03%   2.2kB / 4.74kB   2

# after the curl requests
NAME   CPU %   MEM USAGE / LIMIT     MEM %   NET I/O           PIDS
ttt2   0.13%   36.91MiB / 957.6MiB   3.85%   1.78kB / 4.59kB   2
ttt1   0.13%   38.71MiB / 957.6MiB   4.04%   3.04kB / 9.33kB   2
```

Each container uses only about 35–39 MiB, so two containers together take roughly 75 MiB of the VM's 957 MiB. The LIMIT column shows the whole VM's memory because we didn't set a limit; with `docker run --memory 200m`, cgroups would cap each container.

After finishing, both containers are removed with `docker rm -f ttt1 ttt2`.

---

## Task 3 - Serverless Offloading with AWS Lambda

TODO

---

## Discussion Questions

> Question 1: What are the primary benefits of containerizing your application with Docker compared to deploying directly onto a raw EC2 virtual machine?

TODO

> Question 2: Why is running multiple containers in parallel on a single VM more efficient or manageable than running multiple raw Python processes manually?

TODO

> Question 3: What are the operational trade-offs between managing code execution on an EC2 VM versus offloading it to a serverless function like AWS Lambda? What did you observe regarding startup times or execution overhead?

TODO

<!--
Delete this guide section before submitting — it must not appear in the report PDF.

How to generate the PDF (this repo):
- This is the template. Copy it to your folder as the report source:
    cp report.template.md Exercise_<N>/<you>/report.md
  then fill in the sections above.
- Build it with the Makefile (renders report.md -> dist/exc0N_report_<STUDENT_ID>.pdf):
    make submit EX=<N>
  (set your UIBK username once in .env; see the repo README "Setup"). Uses `npx md-to-pdf`.

Alternatives if you prefer:
- VS Code: install the "Markdown PDF" extension, right-click -> Markdown PDF: Export (pdf).
- Browser: open the Markdown preview, Cmd/Ctrl+P -> Save as PDF.
-->
