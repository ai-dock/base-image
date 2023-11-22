import os
import subprocess
import json
from urllib.parse import urlparse
from xmlrpc.client import ServerProxy

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

def get_cfnt_url(port):
    try:
        process = subprocess.run(['cfnt-url.sh', '-p', port], 
                             stdout=subprocess.PIPE, 
                             universal_newlines=True)
        output = process.stdout.strip()
        scheme = urlparse(output).scheme
        if scheme:
            return output
        return False
    except:
        return False

def get_cfqt_url(port):
    try:
        process = subprocess.run(['cfqt-url.sh', '-p', port], 
                             stdout=subprocess.PIPE, 
                             universal_newlines=True)
        output = process.stdout.strip()
        scheme = urlparse(output).scheme
        if scheme:
            return output
        return False
    except:
        return False

def get_direct_url(port):
    port = os.environ.get("MAPPED_TCP_PORT_" + port, port)
    direct_address = os.environ.get('DIRECT_ADDRESS')
    if direct_address == 'auto#vast-ai':
        return get_vast_url(port)
    elif direct_address == 'auto#runpod-io':
        return get_runpod_url(port)
    elif direct_address:
        return "http://" + direct_address + ":" + port
    else:
        return False

def get_vast_url(port):
    ext_port = os.environ.get("VAST_TCP_PORT_"+port)
    if ext_port and os.environ.get("PUBLIC_IPADDR"):
        return "http://" + os.environ.get("PUBLIC_IPADDR") + ":" + ext_port
    else:
         return False

def get_runpod_url(port):
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

async def log_reader(n=250) -> list:
    log_lines = []
    with open("/var/log/logtail.log", "r") as file:
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
        
def get_all_processes():
    with ServerProxy('http://localhost:9001/RPC2') as server:
        return server.supervisor.getAllProcessInfo()
    
def get_single_process(name):
    with ServerProxy('http://localhost:9001/RPC2') as server:
        return server.supervisor.getProcessInfo(name)
    
def stop_process(name):
    with ServerProxy('http://localhost:9001/RPC2') as server:
        return server.supervisor.stopProcess(name)
    
def start_process(name):
    with ServerProxy('http://localhost:9001/RPC2') as server:
        return server.supervisor.startProcess(name)
    
def restart_process(name):
    stop_process(name)
    return start_process(name)