import base64
import io
import json
import os
from urllib.request import Request, urlopen

from fastapi import FastAPI, Response
from fastapi.middleware.cors import CORSMiddleware
from PIL import Image, ImageDraw
from pydantic import BaseModel

LAMBDA_URL = os.environ.get("LAMBDA_URL")
print(f"LAMBDA_URL={LAMBDA_URL}", flush=True)

app = FastAPI()

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)


class GameResult(BaseModel):
    board: list[str]  # 9 items: ["X", "O", " ", ...]
    winner: str  # "X", "O", or "Draw"


def render_board_bitmap(board: list[str], winner: str, size: int = 300) -> bytes:
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