import psutil
disk = psutil.disk_usage('/')
disk_usage=disk.percent
print(disk_usage)