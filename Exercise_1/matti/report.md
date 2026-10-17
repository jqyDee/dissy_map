# EX01 Report: Cloud Infrastructure

**Student Name:** [Matti Sebastian Fischbach]
**Student ID:** `csbb8241`

---

## Task 1 - [Virtual Machines and Baseline Execution]

### Provision an EC2 Instance with Terraform

| Parameter | Value | Description |
| :--- | :--- | :--- |
| `provider` | "aws"; "us-east-1" | Download aws plugin and set deployment region to `us-east-1` |
| `data` | most_recent: true and filter al2023-ami-2023.*-x86_64 | search the amazon linux ami's for x86_64 2023 |
| `resource.aws_security_group.ssh_access` | `ingress` | allow ssh access through port 22 with protocol tcp |
| `resource.aws_security_group.port_forward` | `ingress` | allow application ports to be passed through; 80 for http, 8000 for the backend application |
| `aws_instance.baseline_vm` | instance_type: "t2.micro"; key_name: "vockey"; user_data: ... | build t2.micro instance with preexistent ssh key vockey, attach the security groups and install the needed packages (docker, python3) to deploy the application |
| `output` | aws_instance.baseline_vm.public_ip | Get the public IP of the provisioned EC2 instance |

After this is configured, start the learners-lab and put the aws credentials into `~/.aws/credentials`.

Then run `terraform init`, `terraform plan` and `terraform apply`. To update the
Terraform config, change `main.tf` and run `terraform apply`.

Using `terraform apply` with flag `-auto-approve` will instantly start the
instance without needing confirmation.

The EC2 instances public IP will be printed to stdout:
```
Apply complete! Resources: 3 added, 0 changed, 0 destroyed.

Outputs:

public_ip = "<public_ip>"
```

> If you lose this IP, run `terraform output public_ip` to print it again.

### Connect to the VM and transfer application

Download the learners-lab ssh key (Download PEM) and move it into a safe
location (e.g. `~/.ssh/labsuser.pem`) and change the ssh key to have ssh access
(`chmod 400 ~/.ssh/labsuser.pem`).

Use `ssh -i ~/.ssh/labsuser.pem ec2-user@<public-ip>` to connect to the VM.

> As we are using a small tic-tac-toe game with a fastapi backend and a
> JS/HTML frontend, use `make zip-tic-tac-toe` to create a zip archive
> of the game

With the `tic-tac-toe.zip` created, transfer it to your VM with `scp`:
```bash
scp -i ~/.ssh/labsuser.pem tic-tac-toe/tic-tac-toe.zip ec2-user@<public_ip>:~/
```

### Run the application

If still connected to the VM, just go on, otherwise connect to it now (again).
You will need two ssh connections to start frontend and backend in parallel.

- unzip the just transferred application (`unzip tic-tac-toe.zip`)
- start the backend (`cd tic-tac-toe/backend && python3 -m venv venv && source venv/bin/activate && pip install -r requirements.txt && uvicorn main:app --host 0.0.0.0 --port 8000`). When the application is running it should print:
  ```
  INFO:     Started server process [28953]
  INFO:     Waiting for application startup.
  INFO:     Application startup complete.
  INFO:     Uvicorn running on http://0.0.0.0:8000 (Press CTRL+C to quit)
  ```
  to stdout. You can also test the connection/port forwarding through a browser
  by going to `http://<public_ip>:8000/docs`. If the backend (and forwarding is
  working) the OpenAPI web interface should be visible
- start the frontend in a new ssh connection by `cd tic-tac-toe/frontend && sudo python3 -m http.server 80 --bind 0.0.0.0`. To test it running and port
  forwarding working open `http://<public_ip>` in your browser. A tic tac toe
  interface should show. 

### Measure Performance

Open a new `ssh` connection to measure the performance of the application on
the EC2 instance. The backend runs directly on the VM on port `8000`. The
workload parameter is the image `size` (edge length in pixels) of the rendered
board bitmap:
```bash
for s in 300 600 1200 2400 4800; do
  echo "size=$s"
  time curl -s -o /dev/null -X POST \
    "http://localhost:8000/api/render-bitmap?size=$s" \
    -H "Content-Type: application/json" \
    -d '{"board":["X","O","X","O","X","O","X"," "," "],"winner":"X"}'
done
```

**Result:**
```
size=300

real	0m0.009s
user	0m0.005s
sys	0m0.000s
size=600

real	0m0.008s
user	0m0.005s
sys	0m0.000s
size=1200

real	0m0.013s
user	0m0.006s
sys	0m0.001s
size=2400

real	0m0.034s
user	0m0.011s
sys	0m0.000s
size=4800

real	0m0.275s
user	0m0.011s
sys	0m0.011s
```

---

## Task 2 - Containerization with Docker

### Dockerfile

The backend is packaged into a custom image with the following `Dockerfile`
(`backend/Dockerfile`):
```dockerfile
FROM python:3.11-slim

WORKDIR /app

COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

COPY main.py .

CMD ["uvicorn", "main:app", "--host", "0.0.0.0", "--port", "8000"]
```

- `python:3.11-slim` keeps the image small but still has a full Python runtime.
- `requirements.txt` is copied and installed before `main.py`. This way the
  dependency layer is cached and only rebuilt when the dependencies change.
- `uvicorn` binds to `0.0.0.0` so the port can be published to the host.

The frontend needs no custom image. It is served by the stock `nginx:alpine`
image with the `frontend/` directory mounted read-only. `docker-compose.yml`
ties both services together.

### Single container application

With task 1 already done and everything running/transferred we can move straight
on to the containerization. Through the `user_data` entry in the terraform
config, `docker` is installed with further plugins `compose` and `buildx`. The
backend image is therefore built directly on the EC2 instance by
`docker compose` from the transferred sources.

To run the application use `cd ~/tic-tac-toe && docker compose up`. You should
see logs of the frontend and backend container, looking like this:
```
[+] Running 3/3
 ✔ Network tic-tac-toe_default       Created                                                                                          0.1s
 ✔ Container tic-tac-toe-backend-1   Created                                                                                          0.1s
 ✔ Container tic-tac-toe-frontend-1  Created                                                                                          0.0s
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
frontend-1  | 2026/10/17 11:57:51 [notice] 1#1: using the "epoll" event method
frontend-1  | 2026/10/17 11:57:51 [notice] 1#1: nginx/1.31.7
frontend-1  | 2026/10/17 11:57:51 [notice] 1#1: built by gcc 15.2.0 (Alpine 15.2.0)
frontend-1  | 2026/10/17 11:57:51 [notice] 1#1: OS: Linux 6.18.54-121.166.amzn2023.x86_64
frontend-1  | 2026/10/17 11:57:51 [notice] 1#1: getrlimit(RLIMIT_NOFILE): 32768:65536
frontend-1  | 2026/10/17 11:57:51 [notice] 1#1: start worker processes
frontend-1  | 2026/10/17 11:57:51 [notice] 1#1: start worker process 30
backend-1   | INFO:     Started server process [1]
backend-1   | INFO:     Waiting for application startup.
backend-1   | INFO:     Application startup complete.
backend-1   | INFO:     Uvicorn running on http://0.0.0.0:8000 (Press CTRL+C to quit)
```

To test this you can do the checks from the manual application setup from Task
1. Also the logs should look similar to the individual logs of manual deploy.
There might be some differences in the frontend serving logs, as this is now
using `nginx` rather than the python `http.server`.

### Scale the application to multiple containers

When the single container application is working correctly, we can scale our
application backend. First stop the docker compose run (either `ctrl + c` or
`docker compose down` in the `tic-tac-toe` directory.)

Use `docker compose up --scale backend=2 -d` to start 2 backend containers.
As two containers cannot both bind host port 8000, the compose file maps the
port range `8000-8002:8000` and Docker picks a free host port for each replica.
Check there are 2 backend containers running with `docker ps`. It should look similar to this:
```
CONTAINER ID   IMAGE                 COMMAND                  CREATED         STATUS         PORTS                                       NAMES
56f2bf86cd3c   tic-tac-toe-backend   "uvicorn main:app --…"   6 seconds ago   Up 5 seconds   0.0.0.0:8001->8000/tcp, :::8001->8000/tcp   tic-tac-toe-backend-2
112e7159de8f   nginx:alpine          "/docker-entrypoint.…"   8 minutes ago   Up 4 seconds   0.0.0.0:80->80/tcp, :::80->80/tcp           tic-tac-toe-frontend-1
7c754d879be7   tic-tac-toe-backend   "uvicorn main:app --…"   8 minutes ago   Up 4 seconds   0.0.0.0:8002->8000/tcp, :::8002->8000/tcp   tic-tac-toe-backend-1
```

> Note: the frontend always calls the backend on port `8000`, and the security
> group only opens port `8000`. In the run above, the replicas got host ports
> `8001` and `8002`, so neither one can be reached from outside the VM. Both can
> still be tested from inside the VM via `localhost:<port>`. A load balancer in
> front of the replicas would fix this.

- Check port mapping: read the PORTS column in the output of `docker ps`. Each
  replica listens on container port `8000` but is published on a different
  host port.
- Check process management and the PID namespace:
  ```
  docker top tic-tac-toe-backend-1
  docker top tic-tac-toe-backend-2
  ```
  TODO: paste output. Each container runs its own `uvicorn` process. On the
  host it has a distinct PID, but inside its own PID namespace it is PID 1.
- Check hostname (UTS namespace):
  ```
  docker exec tic-tac-toe-backend-1 hostname
  docker exec tic-tac-toe-backend-2 hostname
  ```
  TODO: paste output (two different container IDs).
- Check network namespace:
  ```
  docker inspect -f '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' tic-tac-toe-backend-1 tic-tac-toe-backend-2
  ```
  TODO: paste output (two different IPs in `tic-tac-toe_default`).
- Check resource usage per container with `docker stats --no-stream`.
  TODO: paste output.

When all this is done, stop the containers with `docker compose down`. Check
with `docker ps` that no containers are running anymore.

## Task 3 - Serverless Offloading with AWS Lambda

To offload the bitmap rendering to AWS Lambda, we use a `handler` function in
the `lambda/handler.py` python script. The handler function simply calls the
bitmap rendering function on its own, so the backend just passes the information
to this function and handles the return. The backend in itself will now never do
the rendering on its own.

Input and output both use JSON. The backend sends
`{"board": [...], "winner": "X", "size": 300}`, and the Lambda returns the PNG
base64-encoded inside a JSON object:
```python
def handler(event, _context):
    body = json.loads(event["body"]) if "body" in event else event
    bmp = render_board_bitmap(body["board"], body["winner"], body.get("size", 300))
    return {
        "statusCode": 200,
        "headers": {"Content-Type": "application/json"},
        "body": json.dumps({"bmp_base64": base64.b64encode(bmp).decode()}),
    }
```

The backend (`backend/main.py`) only offloads when the `LAMBDA_URL` environment
variable is set. Otherwise it renders locally as in Task 1 and 2:
```python
@app.post("/api/render-bitmap")
def render_bitmap(result: GameResult, size: int = 300):
    if LAMBDA_URL:
        payload = json.dumps({**result.model_dump(), "size": size}).encode("utf-8")
        req = Request(LAMBDA_URL, data=payload, headers={"Content-Type": "application/json"})
        data = json.loads(urlopen(req).read().decode("utf-8"))
        bmp_bytes = base64.b64decode(data["bmp_base64"])
        return Response(content=bmp_bytes, media_type="image/png")
    bmp_bytes = render_board_bitmap(result.board, result.winner, size)
    return Response(content=bmp_bytes, media_type="image/png")
```

Rendering uses the python package `Pillow`, so it has to be bundled into the
Lambda deployment package as well. To do this, run
`pip install --platform manylinux2014_x86_64 --implementation cp --python-version 3.12 --only-binary=:all: --target lambda/ pillow`
on your local machine. This downloads the Linux wheel matching the Lambda
runtime, even when running on macOS.

The Lambda is provisioned with Terraform in `lambda.tf`:

| Parameter | Value | Description |
| :--- | :--- | :--- |
| `variable.enable_lambda` | bool, default `false` | toggles all Task 3 resources via `count`, so Task 1/2 can be deployed without Lambda |
| `data.aws_iam_role.lab` | name: "LabRole" | the Learner Lab does not allow creating IAM roles, so the preexisting `LabRole` is reused |
| `data.archive_file.lambda_zip` | source_dir: `lambda/` | zips handler and bundled Pillow into `lambda.zip` |
| `aws_lambda_function.render` | runtime: "python3.12"; handler: "handler.handler"; memory_size: 512; timeout: 30 | the function itself; `source_code_hash` makes Terraform redeploy when the code changes |
| `aws_lambda_function_url.render` | authorization_type: "NONE" | public HTTPS endpoint, so the backend can call it with a plain POST (no AWS SDK/signing needed) |
| `output.lambda_url` | function URL | URL to pass to the backend as `LAMBDA_URL` |

With this done, deploy the Lambda with
`terraform init && terraform apply -var enable_lambda=true`. `terraform init` is
needed again because `archive_file` requires the `hashicorp/archive` provider.

> TODO: verify with `terraform plan -var enable_lambda=true`. If it only shows
> the Lambda resources being added, the EC2 instance is left untouched and the
> ssh session keeps working. Only if `main.tf` (e.g. `user_data`) changed will
> the instance be stopped/started and get a new `public_ip`.

In addition to the `public_ip`, the `lambda_url` will be printed to stdout
(again retrievable with `terraform output lambda_url`).

(Re-)connect to the EC2 instance, and run the `docker` containers again with the
environment `LAMBDA_URL="<lambda_url>"` set to the stdout url of the just
provisioned lambda function. 
```bash
LAMBDA_URL="<lambda_url>" docker compose up
```

The containers should run fine. Check like in Task 1 again.

### Measure performance

We now measure performance like in Task 1:

Opening a new `ssh` connection to now measure performance of the application on the EC2 instance. Make sure to check the containers port with `docker ps` and substitute the port for `<port>` in the following:
```bash
for s in 300 600 1200 2400 4800; do
  echo "size=$s"
  time curl -s -o /dev/null -X POST \
    "http://localhost:<port>/api/render-bitmap?size=$s" \
    -H "Content-Type: application/json" \
    -d '{"board":["X","O","X","O","X","O","X"," "," "],"winner":"X"}'
done
```

**Output:**
```
size=300

real	0m0.905s
user	0m0.005s
sys	0m0.000s
size=600

real	0m0.101s
user	0m0.005s
sys	0m0.000s
size=1200

real	0m0.322s
user	0m0.005s
sys	0m0.000s
size=2400

real	0m1.021s
user	0m0.005s
sys	0m0.000s
size=4800

real	0m3.990s
user	0m0.006s
sys	0m0.000s
```

### Performance comparison

`real` (wall clock) time per request. `user`/`sys` only measure the `curl`
client and are therefore nearly constant in both runs.

| size (px) | EC2 baseline (Task 1) | EC2 + Lambda (Task 3) | Lambda / EC2 |
| ---: | ---: | ---: | ---: |
| 300 | 0.009 s | 0.905 s (cold start) | ~100x |
| 600 | 0.008 s | 0.101 s | ~13x |
| 1200 | 0.013 s | 0.322 s | ~25x |
| 2400 | 0.034 s | 1.021 s | ~30x |
| 4800 | 0.275 s | 3.990 s | ~15x |

Observations:

- **Cold start:** the first request (size 300) took 0.9 s, although the
  following, larger request (600) only took 0.1 s. The first invocation has to
  start a new execution environment and load Python and Pillow. Later requests
  reuse the warm environment.
- **Fixed overhead:** even warm, every offloaded request pays an extra HTTPS
  round trip from the VM to the Lambda function URL. On top come JSON
  serialization and base64 encoding/decoding of the image (+33 % payload size).
  For small images this overhead is far larger than the actual rendering time.
- **Growing gap for large images:** with 512 MB of memory, Lambda only gets a
  fraction of a vCPU, so the rendering itself is slower than on the VM. In
  addition, the response payload grows with the image size and has to cross the
  network twice in encoded form.
- For this workload, offloading does not pay off. The task is short and
  CPU-light, so communication overhead dominates. Lambda would only be
  beneficial for heavy or bursty workloads that would overload the single
  `t2.micro`.
- Each size was measured once. For more robust numbers, each request should be
  repeated several times and cold and warm runs reported separately.

### Cleanup

After completing the tasks, destroy all infrastructure to avoid unexpected
charges:
```bash
terraform destroy -var enable_lambda=true
```

## Discussion Questions

>Question 1: What are the primary benefits of containerizing your application
 with Docker compared to deploying directly onto a raw EC2 virtual machine?

TODO: your answer.

>Question 2: Why is running multiple containers in parallel on a single VM more
 efficient or manageable than running multiple raw Python processes manually?

TODO: your answer.

>Question 3: What are the operational trade-offs between managing code execution
 on an EC2 VM versus offloading it to a serverless function like AWS Lambda?
 What did you observe regarding startup times or execution overhead?

TODO: your answer.