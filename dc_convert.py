#!/usr/bin/env python3

import os
import yaml
import argparse

parser = argparse.ArgumentParser()
parser.add_argument("file_to_convert", help="Input file")
parser.add_argument("output_file", help="Output file")
parser.add_argument("old_registry_url", help="URL of the old registry")
parser.add_argument("new_registry_url", help="URL of the new registry")


args = parser.parse_args()

#output_file=os.path.dirname(args.file_to_convert)+"/new_"+os.path.basename(args.file_to_convert)


with open(args.file_to_convert) as f:
    documents = yaml.full_load(f)

for doc in documents["items"]: #iterating over deploymant configs

    del(doc["metadata"]["creationTimestamp"])
    del(doc["metadata"]["resourceVersion"])
    del(doc["metadata"]["selfLink"])
    del(doc["metadata"]["uid"])
    del(doc["metadata"]["generation"])
    del(doc["status"])    
    try:
        doc["spec"]["triggers"][1]["imageChangeParams"]["lastTriggeredImage"]=doc["spec"]["triggers"][1]["imageChangeParams"]["lastTriggeredImage"].replace(args.old_registry_url, args.new_registry_url)  
    except KeyError:
        pass

    for container in doc["spec"]["template"]["spec"]["containers"]: #iterating over containers within dc
      container["image"]=container["image"].replace(args.old_registry_url, args.new_registry_url)

with open(args.output_file, 'w') as file:
    documents = yaml.dump(documents, file)


