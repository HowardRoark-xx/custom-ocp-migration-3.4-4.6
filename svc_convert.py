#!/usr/bin/env python3

import os
import yaml
import argparse

parser = argparse.ArgumentParser()
parser.add_argument("file_to_convert", help="Input file")
parser.add_argument("output_file", help="Output file")

args = parser.parse_args()


with open(args.file_to_convert) as f:
    documents = yaml.full_load(f)

for doc in documents["items"]:

    del(doc["metadata"]["creationTimestamp"])
    del(doc["metadata"]["resourceVersion"])
    del(doc["metadata"]["selfLink"])
    del(doc["metadata"]["uid"])
    del(doc["spec"]["clusterIP"])
    del(doc["status"])    

with open(args.output_file, 'w') as file:
    documents = yaml.dump(documents, file)


