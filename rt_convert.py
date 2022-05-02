#!/usr/bin/env python3

import os
import yaml
import argparse

parser = argparse.ArgumentParser()
parser.add_argument("file_to_convert", help="Input file")
parser.add_argument("output_file", help="Output file")
parser.add_argument("old_route_basename", help="Old route basename")
parser.add_argument("new_route_basename", help="New route basename")

args = parser.parse_args()


with open(args.file_to_convert) as f:
    documents = yaml.full_load(f)

for doc in documents["items"]:
    #print(doc["spec"]["host"])
    doc["spec"]["host"]=doc["spec"]["host"].replace(args.old_route_basename, args.new_route_basename)
    try:
        del(doc["spec"]["tls"]["caCertificate"])
    except KeyError:
        pass
    try:
        del(doc["spec"]["tls"]["certificate"])
    except KeyError:
        pass
    try:
        del(doc["spec"]["tls"]["key"])
    except KeyError:
        pass
    del(doc["metadata"]["creationTimestamp"])
    del(doc["metadata"]["resourceVersion"])
    del(doc["metadata"]["selfLink"])
    del(doc["metadata"]["uid"])
    del(doc["status"])    
    try:
        del(doc["metadata"]["annotations"])
    except KeyError:
        pass


with open(args.output_file, 'w') as file:
    documents = yaml.safe_dump(documents, file)


