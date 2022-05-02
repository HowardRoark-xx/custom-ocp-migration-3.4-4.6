#!/usr/bin/env python3

import yaml
import argparse

parser = argparse.ArgumentParser()
parser.add_argument("file_to_convert", help="This scripts converts SCC metadata")
parser.add_argument("output_file", help="Output file")
args = parser.parse_args()
#print(args.file_to_convert)
#print(args.output_file)

with open(args.file_to_convert) as f:
    documents = yaml.full_load(f)



#print("===========================================================")

del(documents["metadata"]["creationTimestamp"])
try:
    del(documents["metadata"]["annotations"])
except KeyError:
    pass

del(documents["metadata"]["resourceVersion"])
del(documents["metadata"]["uid"])
del(documents["metadata"]["selfLink"])
#print("===========================================================")



with open(args.output_file, 'w') as file:
    documents = yaml.dump(documents, file)



