# The commands, in order

Replace Acrobat for OCR and redaction with Stirling-PDF on your Mac: every command the video runs, by chapter. `install.sh` does the same with checks; `uninstall.sh` undoes it.

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
docker-compose up -d
until curl -fs http://127.0.0.1:8080/api/v1/info/status; do sleep 2; done; echo
netstat -an -p tcp | grep LISTEN | grep 8080
```

### The test files

```sh
./pdf-check.sh demo/in/*.pdf
```

### Shrink a scan

```sh
curl -fsS -OJ --clobber --output-dir demo/out -F fileInput=@demo/in/scanned-report.pdf -F optimizeLevel=5 http://127.0.0.1:8080/api/v1/misc/compress-pdf && ls demo/out
./pdf-check.sh demo/in/scanned-report.pdf demo/out/scanned-report_Optimized.pdf
```

### Merge two PDFs

```sh
curl -fsS -OJ --clobber --output-dir demo/out -F fileInput=@demo/in/invoice.pdf -F fileInput=@demo/in/contract.pdf -F sortType=orderProvided http://127.0.0.1:8080/api/v1/general/merge-pdfs && ls demo/out
./pdf-check.sh demo/out/invoice_merged_unsigned.pdf
```

### OCR a scan

```sh
curl -fsS -OJ --clobber --output-dir demo/out -F fileInput=@demo/in/scanned-letter.pdf -F languages=eng http://127.0.0.1:8080/api/v1/misc/ocr-pdf && ls demo/out
./pdf-check.sh --find "proofs are ready" demo/in/scanned-letter.pdf demo/out/scanned-letter_OCR.pdf
```

### Redact a number

```sh
curl -fsS -OJ --clobber --output-dir demo/out -F fileInput=@demo/in/invoice.pdf -F listOfText=0042-7781-3390 http://127.0.0.1:8080/api/v1/security/auto-redact && ls demo/out
./pdf-check.sh --find "0042-7781-3390" demo/in/invoice.pdf demo/out/invoice_redacted.pdf
```

### Memory

```sh
docker stats --no-stream
```

### Restart and back up

```sh
docker-compose down
docker-compose up -d
until curl -fs http://127.0.0.1:8080/api/v1/info/status; do sleep 2; done; echo
ls stirling-data/configs
tar -czf configs-backup.tgz stirling-data/configs && du -h configs-backup.tgz
```

### Updating

```sh
docker-compose pull && docker-compose up -d
```

### Verify

```sh
./verify.sh
```
