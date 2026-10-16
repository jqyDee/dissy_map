import io
import base64
from fastapi import FastAPI, Response
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel
from PIL import Image, ImageDraw

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


def render_board_bitmap(board: list[str], winner: str) -> bytes:
    # 300x300 image
    img = Image.new("RGB", (300, 300), color=(255, 255, 255))
    draw = ImageDraw.Draw(img)

    # Grid lines
    draw.line([(100, 0), (100, 300)], fill=(0, 0, 0), width=4)
    draw.line([(200, 0), (200, 300)], fill=(0, 0, 0), width=4)
    draw.line([(0, 100), (300, 100)], fill=(0, 0, 0), width=4)
    draw.line([(0, 200), (300, 200)], fill=(0, 0, 0), width=4)

    # Draw X and O marks
    for idx, cell in enumerate(board):
        col = idx % 3
        row = idx // 3
        cx = col * 100 + 50
        cy = row * 100 + 50

        if cell == "X":
            draw.line(
                [(cx - 30, cy - 30), (cx + 30, cy + 30)], fill=(200, 0, 0), width=6
            )
            draw.line(
                [(cx + 30, cy - 30), (cx - 30, cy + 30)], fill=(200, 0, 0), width=6
            )
        elif cell == "O":
            draw.ellipse(
                [(cx - 30, cy - 30), (cx + 30, cy + 30)], outline=(0, 0, 200), width=6
            )

    buf = io.BytesIO()
    # Save as standard BMP format
    img.save(buf, format="BMP")
    return buf.getvalue()


@app.post("/api/render-bitmap")
def render_bitmap(result: GameResult):
    # --- TASK 1 & 2 BASELINE: Render on the EC2 machine ---
    bmp_bytes = render_board_bitmap(result.board, result.winner)
    return Response(content=bmp_bytes, media_type="image/bmp")

    # --- TASK 3 OFFLOAD: Switch to this to invoke Lambda ---
    # payload = json.dumps(result.model_dump()).encode('utf-8')
    # req = urllib.request.Request("<YOUR_LAMBDA_FUNCTION_URL>", data=payload, headers={'Content-Type': 'application/json'})
    # res = urllib.request.urlopen(req)
    # data = json.loads(res.read().decode('utf-8'))
    # bmp_bytes = base64.b64decode(data['bmp_base64'])
    # return Response(content=bmp_bytes, media_type="image/bmp")
