# EX01 Report: [Cloud Infrastructure]

**Student Name:** [leave this exactly like this]  
**Student ID:** `leave this exactly like this`  

---

## Task 1 - [Virtual Machines and Baseline Execution]

### Provision an EC2 Instance with Terraform

| Parameter | Value | Description |
| :--- | :--- | :--- |
| `terraform` | `required_version`, `required_providers` | specifies minimum required version of terraform and external provider plugins |
| `provider` | "aws"; "us-east-1" | set region to `us-east-1` |
| `data` | most_recent: true and filter al2023-ami-*-x86_64 | search in amazon linux ami's for x86_64 2023 |
| `resource.aws_security_group.ssh_sg` | `ingress` | allowing ssh access through port 22 with the tcp protocol |
| `resource.aws_security_group.port_forward` | `ingress` | allow application ports to be passed through; 80 for http, 8000 for the backend application |
| `aws_instance.my_vm` | instance_type: "t2.micro"; key_name: "vockey"; user_data: ... | build t2.micro instance with preexistent ssh key vockey, attach the security groups and install the needed packages (docker, python3) to deploy the application |
| `output` | aws_instance.baseline_vm.public_ip | outputs public ipv4 of the ec2 instance |

After creating our main.tf we copy the aws credentials into `~/.aws/credentials`

We then run `terraform init`, `terraform plan` and `terraform apply`

Running terraform apply yields:
```
Apply complete! Resources: 3 added, 0 changed, 0 destroyed.

Outputs:

instance_public_ip = "<public_ip>"
```

### Setup & Execution

Using the public ip we can now connect to the ec2 instance via ssh and transfer our application via scp.

For this we also need to download the labuser.pem ssh key and store it somehwere logical.

ssh-connection:
`ssh -i ~/.ssh/labsuser.pem ec2-user@<public-ip>`

copying application:
`scp -i ~/.ssh/labsuser.pem tic-tac-toe/tic-tac-toe.zip ec2-user@<public-ip>:~/`

To run our application we can cd into the backend and create a venv:
`cd tic-tac-toe/backend`
`python3 -m venv venv`
Activate and install requirements:
`source venv/bin/activate`
`pip install -r requirements.txt`
Host the app on port 8000:
`uvicorn main:app --host 0.0.0.0 --port 8000`

```
LAMBDA_URL=None
INFO:     Started server process [2603]
INFO:     Waiting for application startup.
INFO:     Application startup complete.
INFO:     Uvicorn running on http://0.0.0.0:8000 (Press CTRL+C to quit)
```

### Measure Performance

We can run a bash script measuring performance of our api endpoint:

```
#!/bin/bash

URL="http://localhost:8000/api/render-bitmap"
PAYLOAD='{"board":["X","O"," ","X","O"," ","X"," "," "],"winner":"X"}'

# Workload levels (number of total requests)
WORKLOADS=(10 50 100 200)

echo "=== Benchmarking Endpoint Throughput ==="
echo "Workload (N Requests) | Execution Time"

for COUNT in "${WORKLOADS[@]}"; do
  echo -n "N = $COUNT requests: "

  # Time the total duration of sending N requests sequentially
  /usr/bin/time -f "Real: %Es | CPU User: %Us | System: %Ss" \
    bash -c "for ((i=1; i<=$COUNT; i++)); do
      curl -s -X POST '$URL' \
        -H 'Content-Type: application/json' \
        -d '$PAYLOAD' \
        -o /dev/null
    done"
done
```

`./benchmark.sh` yields:
```
=== Benchmarking Endpoint Throughput ===
Workload (N Requests) | Execution Time
N = 10 requests: Real: 0:00.11s | CPU User: 0.01s | System: 0.03s
N = 50 requests: Real: 0:00.48s | CPU User: 0.17s | System: 0.06s
N = 100 requests: Real: 0:00.92s | CPU User: 0.34s | System: 0.10s
N = 200 requests: Real: 0:01.84s | CPU User: 0.69s | System: 0.20s
```

---

## Task 2 - [Containerization with Docker]

Our Dockerfile looks like this:
```
FROM python:3.11-slim

WORKDIR /app

COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

COPY main.py .

CMD ["uvicorn", "main:app", "--host", "0.0.0.0", "--port", "8000"]
```

All the needed dependencies are installed via a bash script defined in our main.tf:
```
user_data = <<-EOF
              #!/bin/bash
              dnf update -y
              dnf install -y docker python3 python3-pip time unzip
              systemctl enable --now docker
              usermod -aG docker ec2-user

              # Automatically download and install Compose & Buildx plugins
              mkdir -p /usr/libexec/docker/cli-plugins
              curl -SL https://github.com/docker/compose/releases/download/v2.29.2/docker-compose-linux-x86_64 -o /usr/libexec/docker/cli-plugins/docker-compose
              curl -SL https://github.com/docker/buildx/releases/download/v0.17.0/buildx-v0.17.0.linux-amd64 -o /usr/libexec/docker/cli-plugins/docker-buildx
              chmod +x /usr/libexec/docker/cli-plugins/docker-compose
              chmod +x /usr/libexec/docker/cli-plugins/docker-buildx
              EOF
```

Since we already transferred the application including the Dockerfile we can simply run docker compose up, starting a single docker container:
```
[+] Running 3/2
 ✔ Network tic-tac-toe_default       Created                                                                                         0.1s 
 ✔ Container tic-tac-toe-backend-1   Created                                                                                         0.0s 
 ✔ Container tic-tac-toe-frontend-1  Created                                                                                         0.0s 
Attaching to backend-1, frontend-1
frontend-1  | /docker-entrypoint.sh: /docker-entrypoint.d/ is not empty, will attempt to perform configuration
frontend-1  | /docker-entrypoint.sh: Looking for shell scripts in /docker-entrypoint.d/
frontend-1  | /docker-entrypoint.sh: Launching /docker-entrypoint.d/10-listen-on-ipv6-by-default.sh
frontend-1  | 10-listen-on-ipv6-by-default.sh: info: Getting the checksum of /etc/nginx/conf.d/default.conf
frontend-1  | 10-listen-on-ipv6-by-default.sh: info: Enabled listen on IPv6 in /etc/nginx/conf.d/default.conf
frontend-1  | /docker-entrypoint.sh: Sourcing /docker-entrypoint.d/15-local-resolvers.envsh
frontend-1  | /docker-entrypoint.sh: Launching /docker-entrypoint.d/20-envsubst-on-templates.sh
frontend-1  | /docker-entrypoint.sh: Launching /docker-entrypoint.d/30-tune-worker-processes.sh
frontend-1  | /docker-entrypoint.sh: Configuration complete; ready for start up
frontend-1  | 2026/10/19 12:53:33 [notice] 1#1: using the "epoll" event method
frontend-1  | 2026/10/19 12:53:33 [notice] 1#1: nginx/1.31.7
frontend-1  | 2026/10/19 12:53:33 [notice] 1#1: built by gcc 15.2.0 (Alpine 15.2.0) 
frontend-1  | 2026/10/19 12:53:33 [notice] 1#1: OS: Linux 6.12.111-136.204.amzn2023.x86_64
frontend-1  | 2026/10/19 12:53:33 [notice] 1#1: getrlimit(RLIMIT_NOFILE): 32768:65536
frontend-1  | 2026/10/19 12:53:33 [notice] 1#1: start worker processes
frontend-1  | 2026/10/19 12:53:33 [notice] 1#1: start worker process 30
backend-1   | LAMBDA_URL=None
backend-1   | INFO:     Started server process [1]
backend-1   | INFO:     Waiting for application startup.
backend-1   | INFO:     Application startup complete.
backend-1   | INFO:     Uvicorn running on http://0.0.0.0:8000 (Press CTRL+C to quit)
```

Checking the running container with `sudo docker ps` prints the following on stout:
```
CONTAINER ID   IMAGE                 COMMAND                  CREATED         STATUS         PORTS                                       NAMES
ecc6525f4a49   nginx:alpine          "/docker-entrypoint.…"   3 minutes ago   Up 3 minutes   0.0.0.0:80->80/tcp, :::80->80/tcp           tic-tac-toe-frontend-1
ff024ab03be6   tic-tac-toe-backend   "uvicorn main:app --…"   3 minutes ago   Up 3 minutes   0.0.0.0:8000->8000/tcp, :::8000->8000/tcp   tic-tac-toe-backend-1
```
Here we can see two containers, one for the frontend and one for the backend.

We now stop the running docker container and start up two instances using `docker compose up --scale backend=2 -d`

`sudo docker ps`:

```
CONTAINER ID   IMAGE                 COMMAND                  CREATED          STATUS          PORTS                                       NAMES
92aa3bc595be   nginx:alpine          "/docker-entrypoint.…"   22 seconds ago   Up 21 seconds   0.0.0.0:80->80/tcp, :::80->80/tcp           tic-tac-toe-frontend-1
edc128360037   tic-tac-toe-backend   "uvicorn main:app --…"   23 seconds ago   Up 22 seconds   0.0.0.0:8001->8000/tcp, :::8001->8000/tcp   tic-tac-toe-backend-1
c74a72907dfe   tic-tac-toe-backend   "uvicorn main:app --…"   23 seconds ago   Up 21 seconds   0.0.0.0:8002->8000/tcp, :::8002->8000/tcp   tic-tac-toe-backend-2
```
Now we see three containers, one frontend and two backends. Both backends are being started on port 8000, but docker automatically maps the two containers to distinct ports (8001 and 8002) to avoid conflicts.

We can now test the independent API endpoints:
```
PAYLOAD='{"board":["X","O"," ","X","O"," ","X"," "," "],"winner":"X"}'

# Test instance 1
curl -s -o /dev/null -w "Backend-1 HTTP Status: %{http_code}\n" -X POST http://localhost:8001/api/render-bitmap -H "Content-Type: application/json" -d "$PAYLOAD"

# Test instance 2
curl -s -o /dev/null -w "Backend-2 HTTP Status: %{http_code}\n" -X POST http://localhost:8002/api/render-bitmap -H "Content-Type: application/json" -d "$PAYLOAD"
```
and they will both return the correct http status code:
```
Backend-1 HTTP Status: 200
Backend-2 HTTP Status: 200
```

We can view the container process list:
```
docker top tic-tac-toe-backend-1
docker top tic-tac-toe-backend-2
```

and we will see two distinct processes:
```
UID                 PID                 PPID                C                   STIME               TTY                 TIME                CMD
root                15602               15573               0                   12:59               ?                   00:00:01            /usr/local/bin/python3.11 /usr/local/bin/uvicorn main:app --host 0.0.0.0 --port 8000
UID                 PID                 PPID                C                   STIME               TTY                 TIME                CMD
root                15810               15783               0                   12:59               ?                   00:00:01            /usr/local/bin/python3.11 /usr/local/bin/uvicorn main:app --host 0.0.0.0 --port 8000
```

We can list all uvicorn processes running on the EC2 instance via `ps aux | grep uvicorn` and we will see two of those:
```
root       15602  0.2  5.4 144860 53220 ?        Ssl  12:59   0:01 /usr/local/bin/python3.11 /usr/local/bin/uvicorn main:app --host 0.0.0.0 --port 8000
root       15810  0.2  5.4 144860 53068 ?        Ssl  12:59   0:01 /usr/local/bin/python3.11 /usr/local/bin/uvicorn main:app --host 0.0.0.0 --port 8000
ec2-user   16418  0.0  0.2 222312  2168 pts/1    S+   13:10   0:00 grep --color=auto uvicorn
```
The third one seen here is just the grep command itself.

We can create a file in one container and look for it in both containers:
```
docker exec tic-tac-toe-backend-1 touch /app/container_1_only.txt
docker exec tic-tac-toe-backend-1 ls /app/container_1_only.txt
docker exec tic-tac-toe-backend-2 ls /app/container_1_only.txt
```
We will only find it inside one of the containers:
```
/app/container_1_only.txt
ls: cannot access '/app/container_1_only.txt': No such file or directory
```

## Task 3 - [Serverless Offloading with AWS Lambda]

### Offloading a function
We change our python function render_bitmap to use our lambda function in case a LAMBDA_URL environment variable is set:
```
@app.post("/api/render-bitmap")
def render_bitmap(result: GameResult, size: int = 300):
    if LAMBDA_URL:
        # --- TASK 3 OFFLOAD: Switch to this to invoke Lambda ---
        payload = json.dumps({**result.model_dump(), "size": size}).encode("utf-8")
        req = Request(
            LAMBDA_URL,
            data=payload,
            headers={"Content-Type": "application/json"},
        )
        res = urlopen(req)
        data = json.loads(res.read().decode("utf-8"))
        bmp_bytes = base64.b64decode(data["bmp_base64"])
        return Response(content=bmp_bytes, media_type="image/png")
    else:
        # --- TASK 1 & 2 BASELINE: Render on the EC2 machine ---
        bmp_bytes = render_board_bitmap(result.board, result.winner, size)
        return Response(content=bmp_bytes, media_type="image/png")
```

The code for our lambda function looks like this, the fucntion render_board_bitmap is the same as in main.py:

```
import base64
import io
import json

from PIL import Image, ImageDraw


def render_board_bitmap(board: list[str], _winner: str, size: int = 300) -> bytes:
    img = Image.new("RGB", (size, size), color=(255, 255, 255))
    draw = ImageDraw.Draw(img)

    cell = size / 3
    grid_w = max(1, size // 75)
    mark_w = max(1, size // 50)
    r = cell * 0.3

    # Grid lines
    draw.line([(cell, 0), (cell, size)], fill=(0, 0, 0), width=grid_w)
    draw.line([(2 * cell, 0), (2 * cell, size)], fill=(0, 0, 0), width=grid_w)
    draw.line([(0, cell), (size, cell)], fill=(0, 0, 0), width=grid_w)
    draw.line([(0, 2 * cell), (size, 2 * cell)], fill=(0, 0, 0), width=grid_w)

    # Draw X and O marks
    for idx, c in enumerate(board):
        col = idx % 3
        row = idx // 3
        cx = col * cell + cell / 2
        cy = row * cell + cell / 2

        if c == "X":
            draw.line(
                [(cx - r, cy - r), (cx + r, cy + r)], fill=(200, 0, 0), width=mark_w
            )
            draw.line(
                [(cx + r, cy - r), (cx - r, cy + r)], fill=(200, 0, 0), width=mark_w
            )
        elif c == "O":
            draw.ellipse(
                [(cx - r, cy - r), (cx + r, cy + r)], outline=(0, 0, 200), width=mark_w
            )

    buf = io.BytesIO()
    # Save as standard BMP format
    img.save(buf, format="PNG")
    return buf.getvalue()


def handler(event, _context):
    body = json.loads(event["body"]) if "body" in event else event
    bmp = render_board_bitmap(body["board"], body["winner"], body.get("size", 300))
    return {
        "statusCode": 200,
        "headers": {"Content-Type": "application/json"},
        "body": json.dumps({"bmp_base64": base64.b64encode(bmp).decode()}),
    }
```

In order to create a lambda function in aws we use a terraform file:

```
# 1. Reference AWS Learner Lab's pre-created IAM Role
data "aws_iam_role" "lab_role" {
  name = "LabRole"
}

# 2. Automatically install Linux-compatible Pillow (PIL) into a build folder
resource "null_resource" "install_dependencies" {
  triggers = {
    code_hash = filemd5("${path.module}/lambda/lambda_function.py")
  }

  provisioner "local-exec" {
    command = <<EOT
      rm -rf ${path.module}/lambda_build
      mkdir -p ${path.module}/lambda_build
      cp ${path.module}/lambda/lambda_function.py ${path.module}/lambda_build/
      pip install --platform manylinux2014_x86_64 --target ${path.module}/lambda_build --implementation cp --python-version 3.11 --only-binary=:all: --upgrade pillow
    EOT
  }
}

# 3. Zip the handler code + installed dependencies
data "archive_file" "lambda_zip" {
  type        = "zip"
  source_dir  = "${path.module}/lambda_build"
  output_path = "${path.module}/lambda_package.zip"

  depends_on = [null_resource.install_dependencies]
}

# 4. Deploy the AWS Lambda Function
resource "aws_lambda_function" "render_lambda" {
  filename         = data.archive_file.lambda_zip.output_path
  function_name    = "tic-tac-toe-render-lambda"
  role             = data.aws_iam_role.lab_role.arn
  handler          = "lambda_function.handler"
  runtime          = "python3.11"
  timeout          = 10
  memory_size      = 512
  source_code_hash = data.archive_file.lambda_zip.output_base64sha256

  depends_on = [data.archive_file.lambda_zip]
}

# 5. Create a public Function URL for HTTP invocations
resource "aws_lambda_function_url" "lambda_url" {
  function_name      = aws_lambda_function.render_lambda.function_name
  authorization_type = "NONE"
}

# 6. Grant unauthenticated public access to the Function URL
resource "aws_lambda_permission" "allow_public_url" {
  statement_id           = "AllowFunctionURLPublicAccess"
  action                 = "lambda:InvokeFunctionUrl"
  function_name          = aws_lambda_function.render_lambda.function_name
  principal              = "*"
  function_url_auth_type = "NONE"
}

# 7. Output the generated Function URL
output "lambda_function_url" {
  description = "Public Function URL for the Lambda function"
  value       = aws_lambda_function_url.lambda_url.function_url
}
```
| Parameter | Value | Description |
| :--- | :--- | :--- |
| `data` | `aws_iam_role` | sets role to the predefined LabRole |
| `resource` | `null_resource` | this is used later in the block, if the file of the defined path file changes, this gets triggered |
| `provisioner` | `local-exec` | when the null_resource gets triggered, this does setup and installs dependencies |
| `data` | `archive_file` | this zips the lambda build after the null resource "install dependencies" was run |
| `resource` | `aws_lambda_function` | sets filepath, function name, lab_role, runtime, memory_size and depends on the block that comes before |
| `resource` | `aws_lambda_permission` | sets permissions for the lambda function, allows unauthenticated public http requests in this case |
| `output` | `lambda_function_url` | outputs the url of our created lambda function, we will need this later |

Using the output of this .tf file, we can set the environment variable LAMBDA_URL that is used in our main.py via `sudo LAMBDA_URL="<LAMBDA_URL>" docker compose up`

### Benchmark

We use the same benchmark.sh as before and get following result:

### Benchmarking Endpoint Throughput

| Workload | Real Time | Real Factor | CPU User Time | CPU User Factor | System Time | System Factor |
| --- | --- | --- | --- | --- | --- | --- |
| 10 requests | 0:00.04s | 2.75x | 0.03s | 3.00x | 0.00s | - |
| 50 requests | 0:00.20s | 2.40x | 0.15s | 1.13x | 0.04s | 1.50x |
| 100 requests | 0:00.39s | 2.36x | 0.32s | 1.06x | 0.06s | 1.66x |
| 200 requests | 0:00.79s | 2.33x | 0.63s | 1.10x | 0.14s | 1.43x |

## Discussion Questions

>Question 1: What are the primary benefits of containerizing your application with Docker compared to deploying directly
onto a raw EC2 virtual machine?

The Dockerfile defines the whole environment (Python version and dependencies), so the app runs the same on every host and does not depend on the state of the VM. There is no manual venv setup or second ssh session: docker compose up builds and starts everything, and docker compose down cleans it up. Containers also add isolation, central logs and automatic restarts, with almost no runtime overhead because they share the host kernel.

>Question 2: Why is running multiple containers in parallel on a single VM more efficient or manageable than running
multiple raw Python processes manually?

`docker compose up --scale backend=2` starts both replicas from the same image with one command. Each replica listens on port 8000 inside its own network namespace, and Docker maps them to free host ports, so there are no port conflicts. Each replica has its own PID, hostname, IP and filesystem, so one cannot affect the other, and all of them are started, stopped and monitored together. Raw processes would need separate sessions, manual ports and manual restarts. Since containers share the kernel and image layers, an extra replica costs about as much as an extra process, and far less than an extra VM.

>Question 3: What are the operational trade-offs between managing code execution on an EC2 VM versus offloading
it to a serverless function like AWS Lambda? What did you observe regarding startup times or execution
overhead?

On EC2 I manage the OS, packages, ports and scaling myself, and pay while the VM runs, but the process is always warm and has a full CPU. Lambda needs no server management, scales automatically and is billed per request. In return it has cold starts, network overhead per call, limits (runtime, payload, CPU tied to memory) and extra packaging work (bundling Pillow, JSON/base64 payloads).

I observed a cold start of 0.9 s on the first request, compared to 0.1 s for the next (larger) one. Warm requests were still about 6x slower than local rendering, because of the HTTPS round trip, base64 encoding and the smaller CPU share at 512 MB. For this lightweight task, offloading does not pay off.

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
