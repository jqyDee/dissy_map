# Tic-Tac-Toe (example app)

Small two-container app used as the workload for the Cloud Infrastructure exercise.
A static frontend plays the game in the browser; a FastAPI backend renders the final
board to a bitmap image.

## Structure

```
tic-tac-toe/
├── docker-compose.yml       # brings up backend + frontend
├── backend/                 # FastAPI service (renders the board to a BMP)
│   ├── main.py              #   POST /api/render-bitmap  -> image/bmp
│   ├── Dockerfile           #   python:3.11-slim + uvicorn
│   └── requirements.txt     #   fastapi, uvicorn, pillow, pydantic
└── frontend/
    └── index.html           # static UI, served by nginx:alpine
```

## Run

```bash
cd tic-tac-toe
docker compose up --build
```

| Service  | Port         | Notes                                              |
|----------|--------------|----------------------------------------------------|
| frontend | `80`         | open http://localhost — the game UI (nginx)        |
| backend  | `8000`       | FastAPI; container 8000 published on host 8000–8002 |

The frontend calls the backend at `http://<host>:8000/api/render-bitmap`, so the
backend must be reachable on port 8000 from the browser.

## API

`POST /api/render-bitmap` — body:

```json
{ "board": ["X","O"," ","X"," "," ","O"," ","X"], "winner": "X" }
```

Returns a 300×300 `image/bmp` of the drawn board (grid + X/O marks), rendered with
Pillow. CORS is open (`*`) for simplicity.

## Packaging

Zip the app via the Makefile one level up (`examples/Makefile`):

```bash
cd examples
make zip-tic-tac-toe     # -> tic-tac-toe.zip
```

## Exercise note

`backend/main.py` renders on the host by default (Task 1 & 2 baseline). A commented
block in `render_bitmap` shows the Task 3 variant that offloads rendering to an AWS
Lambda via its function URL — swap it in and set `<YOUR_LAMBDA_FUNCTION_URL>`.
