# import libraries
import os
import subprocess
import json
from urllib.parse import urlparse
from pathlib import Path
from fastapi import FastAPI, Request, Response
from fastapi.staticfiles import StaticFiles
from fastapi.responses import RedirectResponse
from fastapi.templating import Jinja2Templates
import uvicorn
import argparse
 
parser = argparse.ArgumentParser(description="Require port and service name",
                                 formatter_class=argparse.ArgumentDefaultsHelpFormatter)
parser.add_argument("-p", "--port", action="store", help="listen port", required="True", type=int)
args = parser.parse_args()

base_dir = "/opt/ai-dock/fastapi/redirector/"

app = FastAPI()

# set template and static file directories for Jinja
templates = Jinja2Templates(directory=str(Path(base_dir, "templates")))
app.mount("/static", StaticFiles(directory=str(Path(base_dir, "static"))), name="static")

@app.get("/")
async def get(request: Request):
    return load_index(request)

@app.get("/cloudflare/{port}")
async def get(request: Request, port: str):
    try:
        if not is_valid_port(int(port)):
            return load_index(request, "Port not valid", 400)
        url = get_cf_url(port)
        if url:
            return RedirectResponse(url)
    except:
        return load_index(request, "Port not valid", 400)
    
    return load_index(request, "Unable to load Cloudflare tunnel for port " + port, 404)
    
@app.get("/direct/{port}")
async def get(request: Request, port: str):
    try:
        if not is_valid_port(int(port)):
            return load_index(request, "Port not valid", 400)
        host_ip = request.headers['host'].split(':')[0]
        url = get_direct_url(host_ip, port)
        if url:
            return RedirectResponse(url)
    except:
        return load_index(request, "Port not valid", 400)
        
    return load_index(request, "Unable to complete redirect for port " + port, 400)

@app.get("/{catch_all:path}")
async def get(request: Request):
    return RedirectResponse("/")
    
def load_index(request: Request, message: str = "", status_code: int = 200):
    services = get_services()
    context = {
                "message": message,
                "services": services,
                "urlslug": os.environ.get('IMAGE_SLUG'),
                "cloud": os.environ.get('CLOUD_PROVIDER'),
                'tunnels': os.environ.get('CF_QUICK_TUNNELS')
            }
    return templates.TemplateResponse("index.html", {
        "request": request, 
        "context": context,
        "status": status_code
        })

def get_cf_url(port):
    process = subprocess.run(['cfqt-url.sh', '-p', port], 
                         stdout=subprocess.PIPE, 
                         universal_newlines=True)
    output = process.stdout.strip()
    scheme = urlparse(output).scheme
    if scheme:
        return output
    return False

def get_direct_url(host_ip, port):
    cloud = os.environ.get('CLOUD_PROVIDER')
    if not cloud:
        return "http://" + host_ip + ":" + port

    elif cloud == 'vast.ai':
        return get_vast_url(host_ip, port)
    elif cloud == 'runpod.io':
        return get_runpod_url(host_ip, port)
    else:
        return False

def get_vast_url(host_ip, port):
    ext_port = os.environ.get("VAST_TCP_PORT_"+port)
    if ext_port and os.environ.get("PUBLIC_IPADDR"):
        return "http://" + os.environ.get("PUBLIC_IPADDR") + ":" + ext_port
    else:
         return False

def get_runpod_url(host_ip, port):
    ext_port = os.environ.get("RUNPOD_TCP_PORT_"+port)
    if ext_port and os.environ.get("RUNPOD_PUBLIC_IP"):
        return "http://" + os.environ.get("RUNPOD_PUBLIC_IP") + ":" + ext_port
    elif os.environ.get("RUNPOD_POD_ID"):
        return "https://" + os.environ.get("RUNPOD_POD_ID") + "-" + port + ".proxy.runpod.net"
    else:
        return False

def is_valid_port(port: int):
    if not port in range(1,65535):
        return False
    return True

def get_service_files():
    dir = "/run/http_ports/"
    files = []
    for filename in os.listdir(dir):
        file = os.path.join(dir, filename)
        if os.path.isfile(file):
            files.append(file)
    return files

def get_services():
    services = {}
    for file in get_service_files():
        with open(file) as dataFile:
            data = json.load(dataFile)
        services[data["proxy_port"]] = data
    return services
        
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
