#!/usr/bin/python3

import argparse
import bcrypt
 
parser = argparse.ArgumentParser(description="Create a bcrypt hash from a string",
                                 formatter_class=argparse.ArgumentDefaultsHelpFormatter)
parser.add_argument("-p", "--password", action="store", help="password to hash", required="True", type=str)
parser.add_argument("-r", "--rounds", action="store", help="salt rounds", type=int, default=12)
args = parser.parse_args()

password = str.encode(args.password)

print (bcrypt.hashpw(password, bcrypt.gensalt(rounds=args.rounds)).decode())

