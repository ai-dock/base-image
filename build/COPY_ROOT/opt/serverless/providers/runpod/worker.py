import runpod
import os
from importlib.machinery import SourceFileLoader

def get_handler(payload):
    try:
        name = payload["handler"]
        handler = SourceFileLoader(name,f"/opt/serverless/handlers/{name}.py").load_module()
    except:
        raise IndexError("Handler not found")
    
    return handler
  
'''
Handler to be specified in input.handler
'''
def worker(event):
    payload = event["input"]
    handler = get_handler(payload)
    
    # Defer all processing to the named handler
    result = handler.run(payload)
    
    # Future updates will parse the result before return
    # We will want to handle object uploads here (probably)
    return result

runpod.serverless.start({
    "handler": worker
})