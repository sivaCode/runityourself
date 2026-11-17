# The commands, in order

Replace Evernote for scanned paperwork with Paperless-ngx on your Mac: every command the video runs, by chapter. `install.sh` does the same with checks; `uninstall.sh` undoes it.

### Colima is running

```sh
colima list
```

### The compose file

```sh
cat compose.yaml
```

### Install and start

```sh
./install.sh
netstat -an -p tcp | grep LISTEN | grep 8000
```

### The test scans

```sh
./pdf-check.sh demo/scans/*.pdf
```

### The consume folder

```sh
cp demo/scans/*.pdf consume/ && ls consume
./paper.sh wait 4
./paper.sh list
```

### Find a receipt

```sh
./paper.sh find dehumidifier
./paper.sh find renewal premium
```

### Filing rules

```sh
./paper.sh rule tag Invoices any invoice
./paper.sh rule correspondent "Maple Lane Design Studio" exact "Maple Lane"
cp demo/new/maple-lane-invoice-118.pdf consume/ && ./paper.sh wait 5
./paper.sh list
```

### Memory

```sh
docker stats --no-stream --format "table {{.Name}}\t{{.MemUsage}}"
```

### Back up

```sh
docker-compose exec -T webserver document_exporter ../export --no-progress-bar && ls export
du -sh export
```

### Wipe and restore

```sh
docker-compose down -v
docker-compose up -d
./paper.sh up
docker-compose exec -T webserver document_importer ../export --no-progress-bar
./paper.sh find dehumidifier
./paper.sh list
```

### Updating

```sh
docker-compose pull && docker-compose up -d
```

### Verify

```sh
./verify.sh
```
