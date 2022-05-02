#!/usr/bin/env python3

import yaml
import argparse

parser = argparse.ArgumentParser()
parser.add_argument("file_to_convert", help="Input file")
parser.add_argument("output_file", help="Output file")
parser.add_argument("old_nfs_server", help="Old NFS server")
parser.add_argument("old_nfs_path", help="Old NFS path")
parser.add_argument("new_nfs_server", help="New NFS server")
parser.add_argument("new_nfs_path", help="New NFS path")

args = parser.parse_args()
#print(args.file_to_convert)
#print(args.output_file)

with open(args.file_to_convert) as f:
    documents = yaml.full_load(f)


try:
    del(documents["metadata"]["annotations"])
except KeyError:
    pass

del(documents["spec"]["claimRef"]["resourceVersion"])
del(documents["spec"]["claimRef"]["uid"])
documents["spec"]["nfs"]["server"]=args.new_nfs_server
documents["spec"]["nfs"]["path"]=documents["spec"]["nfs"]["path"].replace(args.old_nfs_path, args.new_nfs_path)

with open(args.output_file, 'w') as file:
    documents = yaml.dump(documents, file)


