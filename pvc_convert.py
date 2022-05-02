#!/usr/bin/env python3

import yaml
import argparse

parser = argparse.ArgumentParser()
parser.add_argument("file_to_convert", help="This scripts converts PVC metadata")
parser.add_argument("output_file", help="Output file")
args = parser.parse_args()
#print(args.file_to_convert)
#print(args.output_file)

with open(args.file_to_convert) as f:
    documents = yaml.full_load(f)
 
#    for item, doc in documents.items():
#        print(item, ":", doc)


#print("===========================================================")

for i in documents["items"]:
    del(i["metadata"]["creationTimestamp"])
    try:
        del(i["metadata"]["annotations"])
    except KeyError:
        pass

    del(i["status"])
#print("===========================================================")

#for item, doc in documents.items():
#        print(item, ":", doc)


with open(args.output_file, 'w') as file:
    documents = yaml.dump(documents, file)



