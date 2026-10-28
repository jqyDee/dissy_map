import redis 
import sys

#usage: python3 reset.py <redis_host> -> sets the shared counter to 0
r = redis.Redis(host=sys.argv[1], port=6379)
r.set("counter", 0)
print("counter reset to 0")