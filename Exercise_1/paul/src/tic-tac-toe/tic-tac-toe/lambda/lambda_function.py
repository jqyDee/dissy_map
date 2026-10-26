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