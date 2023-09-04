"""
Evolved from https://github.com/h3xagn/streaming-log-viewer-websocket
"""

# import libraries
from pathlib import Path
from fastapi import FastAPI, WebSocket, Request
from fastapi.staticfiles import StaticFiles

from fastapi.templating import Jinja2Templates
import uvicorn
import asyncio
import argparse
 
parser = argparse.ArgumentParser(description="Require port and service name",
                                 formatter_class=argparse.ArgumentDefaultsHelpFormatter)
parser.add_argument("-p", "--port", action="store", help="listen port", required="True", type=int)
parser.add_argument("-s", "--service", action="store", help="service name", type=str, default="service")
parser.add_argument("-t", "--title", action="store", help="page title", type=str, default="Preparing your container...")
parser.add_argument("-u", "--urlslug", action="store", help="page title", type=str, default="base-image")
args = parser.parse_args()

# set path and log file name
base_dir = "/opt/ai-dock/fastapi/"
log_file = "/var/log/logtail.log"

# create fastapi instance
app = FastAPI()

# set template and static file directories for Jinja
templates = Jinja2Templates(directory=str(Path(base_dir, "templates")))
app.mount("/static", StaticFiles(directory=str(Path(base_dir, "static"))), name="static")

async def log_reader(n=50) -> list:
    log_lines = []
    with open(f"{log_file}", "r") as file:
        for line in file.readlines()[-n:]:
            if line.__contains__(">") and line.__contains__(".log"):
                log_lines.append(f'<span class="tail-header">{line}</span><br/>')
            elif line.__contains__("ERR"):
                log_lines.append(f'<span class="error">{line}</span><br/>')
            elif line.__contains__("WARN"):
                log_lines.append(f'<span class="warning">{line}</span><br/>')
            else:
                log_lines.append(f"{line}<br/>")
        return log_lines


@app.get("/")
async def get(request: Request):
    context = {
        "title": args.title,
        "urlslug": args.urlslug,
        "service": args.service,
        "log_file": log_file
    }
    return templates.TemplateResponse("index.html", {
        "request": request, 
        "context": context
        }
    )


@app.websocket("/ai-dock/logtail.sh")
async def websocket_endpoint_log(websocket: WebSocket) -> None:
    await websocket.accept()
    try:
        while True:
            await asyncio.sleep(1)
            logs = await log_reader(50)
            await websocket.send_text(logs)
    except Exception as e:
        print(e)
    finally:
        await websocket.close()

# set parameters to run uvicorn
if __name__ == "__main__":
    
    uvicorn.run(
        "main:app",
        host="0.0.0.0",
        port=args.port,
        log_level="info",
        reload=False,
        workers=1,
    )
