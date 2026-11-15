# The commands, in order

Replace Docker Desktop with Colima on your Mac: $0 vs $24/mo: every command the video runs, by chapter. `install.sh` does the same with checks; `uninstall.sh` undoes it.

### Install with Homebrew

```sh
HOMEBREW_NO_AUTO_UPDATE=1 HOMEBREW_NO_ASK=1 brew install colima docker docker-compose
colima version
docker --version
docker-compose version
```

### Start and size Colima

```sh
colima start --cpus 4 --memory 8 --disk 60
docker context show
colima list
```

### First container

```sh
docker run --rm hello-world
```

### Run a compose app

```sh
docker-compose up -d
docker-compose ps
docker-compose logs web
```

### Where the data is

```sh
docker-compose exec web sh -c "echo '<h1>Hello from Colima</h1>' > /usr/share/nginx/html/index.html"
docker volume ls
docker volume inspect colima-demo_html --format '{{ .Mountpoint }}'
docker system df
```

### Clean up and stop

```sh
docker-compose down
docker system prune --all --force
docker system df
colima stop
colima list
```

### Start it again

```sh
colima start
docker-compose up -d
```

### Verify

```sh
./verify.sh
```
