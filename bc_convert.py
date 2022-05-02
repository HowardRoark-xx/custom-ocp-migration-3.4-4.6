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


with open(args.file_to_convert) as f:
    documents = yaml.full_load(f)

for doc in documents["items"]:
    try:
        del(doc["metadata"]["annotations"])
    except KeyError:
        pass
    del(doc["metadata"]["creationTimestamp"])
    del(doc["metadata"]["resourceVersion"])
    del(doc["metadata"]["selfLink"])
    del(doc["metadata"]["uid"])
    for trigger in doc["spec"]["triggers"]:
        ind=doc["spec"]["triggers"].index(trigger)
        try:
            doc["spec"]["triggers"][ind]["imageChange"]["lastTriggeredImageID"]=doc["spec"]["triggers"][ind]["imageChange"]["lastTriggeredImageID"].replace(args.old_registry_url, args.new_registry_url)
        except KeyError:
            pass


with open(args.output_file, 'w') as file:
    documents = yaml.dump(documents, file)


