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
    files.sort()
    return files

def get_services():
    services = {}
    for file in get_service_files():
        with open(file) as dataFile:
            data = json.load(dataFile)
        services[data["proxy_port"]] = data
    return services

def get_cfnt_url(port, path=""):
    try:
        process = subprocess.run(['cfnt-url.sh', '-p', port, '-l', path], 
                             stdout=subprocess.PIPE, 
                             universal_newlines=True)
        output = process.stdout.strip()
        scheme = urlparse(output).scheme
        if scheme:
            return output
        return False
    except:
        return False

def get_cfqt_url(port, path=""):
    try:
        process = subprocess.run(['cfqt-url.sh', '-p', port, '-l', path], 
                             stdout=subprocess.PIPE, 
                             universal_newlines=True)
        output = process.stdout.strip()
        scheme = urlparse(output).scheme
        if scheme:
            return output
        return False
    except:
        return False

def get_direct_url(port, path=""):
    try:
        process = subprocess.run(['direct-url.sh', '-p', port, '-l', path], 
                             stdout=subprocess.PIPE, 
                             universal_newlines=True)
        output = process.stdout.strip()
        scheme = urlparse(output).scheme
        if scheme:
            return output
        return False
    except:
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