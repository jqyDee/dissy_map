import redis 
import sys
import time

host = sys.argv[1]
n = int(sys.argv[2])

r = redis.Redis(host=host, port=6379)
r.ping()


start = time.perf_counter() # to start measuring time of the loop only and not of establishing connection and pings 
for i in range(n):
    value = int(r.get("counter"))
    value = value + 1
    r.set("counter", value)
end = time.perf_counter()

total = end - start
per_inc = total/n

print(int(r.get("counter")))
print(f"total time: {total * 1000:.3f} ms")
print(f"per_increment: {per_inc * 1000:.3f} ms")
