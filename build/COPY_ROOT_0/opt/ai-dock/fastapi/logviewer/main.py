"""
Evolved from https://github.com/h3xagn/streaming-log-viewer-websocket
"""

# import libraries
import os
import hashlib
from pathlib import Path
from fastapi import FastAPI, WebSocket, Request
from fastapi.staticfiles import StaticFiles

from fastapi.templating import Jinja2Templates
import uvicorn
import asyncio
import argparse
 
parser = argparse.ArgumentParser(description="Require port and service name",
                                 formatter_class=argparse.ArgumentDefaultsHelpFormatter)
parser.add_argument("-f", "--file", action="store", help="file to read", type=str, default="/var/log/logtail.log")
parser.add_argument("-n", "--numlines", action="store", help="number of lines to stream", type=int, default=250)
parser.add_argument("-p", "--port", action="store", help="listen port", required="True", type=int)
parser.add_argument("-r", "--refresh", action="store", help="time to wait in seconds before refreshing", type=int, default=0)
parser.add_argument("-s", "--service", action="store", help="service name", type=str, default="service")
parser.add_argument("-t", "--title", action="store", help="page title", type=str, default="Preparing your container...")
parser.add_argument("-u", "--urlslug", action="store", help="image slug", type=str, default=os.environ.get('IMAGE_SLUG'))
args = parser.parse_args()

# set path and log file name
base_dir = "/opt/ai-dock/fastapi/logviewer/"

# create fastapi instance
app = FastAPI()

# set template and static file directories for Jinja
templates = Jinja2Templates(directory=str(Path(base_dir, "templates")))
app.mount("/static", StaticFiles(directory=str(Path(base_dir, "static"))), name="static")

async def log_reader(n=args.numlines) -> list:
    log_lines = []
    with open(f"{args.file}", "r") as file:
        for line in file.readlines()[-n:]:
            if line.isspace(): continue
            line = line.replace("  ", "&nbsp;&nbsp;", 22)
            if line.__contains__("==>") and line.__contains__("<=="):
                log_lines.append(f'<span class="tail-header">{line}</span><br/>')
            elif line.__contains__("ERR"):
                log_lines.append(f'<span class="error">{line}</span><br/>')
            elif line.__contains__("WARN"):
                log_lines.append(f'<span class="warning">{line}</span><br/>')
            elif line.__contains__("INFO"):
                log_lines.append(f'<span class="info">{line}</span><br/>')
            else:
                log_lines.append(f"{line}<br/>")
        return log_lines

@app.websocket("/ai-dock/logtail.sh")
async def websocket_endpoint_log(websocket: WebSocket) -> None:
    last_logs = []
    await websocket.accept()
    try:
        while True:
            await asyncio.sleep(1)
            logs = await log_reader(args.numlines)
            if not logs == last_logs:
                await websocket.send_text(logs)
                last_logs = logs
            else:
                await websocket.send_text("")
    except Exception as e:
        print(e)
    finally:
        await websocket.close()
        
@app.api_route("/{path_name:path}", methods=["GET"])
async def get(request: Request):
    context = {
        "title": args.title,
        "urlslug": args.urlslug,
        "service": args.service,
        "refresh": args.refresh,
        "log_file": args.file,
        "cloud": os.environ.get('CLOUD_PROVIDER')
    }
    return templates.TemplateResponse("index.html", {
        "request": request, 
        "context": context
        }
    )

# set parameters to run uvicorn
if __name__ == "__main__":
    uvicorn.run(
        "main:app",
        host="127.0.0.1",
        port=args.port,
        log_level="info",
        reload=False,
        workers=1,
    )
