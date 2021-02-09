# Challenge 48h - HelloAsso

---

## How to use this

**First start :**
```bash
./init-letsencrypt.sh
```

**Then :**
```bash
docker-compose up -d
```

## Maintenance mode

```bash
# Enable
docker exec -u www-data -it nextcloud_app_1 ./occ maintenance:mode --on

# Disable
docker exec -u www-data -it nextcloud_app_1 ./occ maintenance:mode --off
```

## Backup 

### Folders

Simply copy your config, data and theme folders (or even your whole Nextcloud install and data folder) to a place outside of your Nextcloud environment. You could use this command:
```
rsync -Aavx nextcloud/ nextcloud-dirbkp_`date +"%Y%m%d"`/
```

### Database  

**MySQL/MariaDB**
MySQL or MariaDB, which is a drop-in MySQL replacement, is the recommended database engine. To backup MySQL/MariaDB:
```
mysqldump --single-transaction -h [server] -u [username] -p[password] [db_name] > nextcloud-sqlbkp_`date +"%Y%m%d"`.bak
```

**SQLite**
```
sqlite3 data/owncloud.db .dump > nextcloud-sqlbkp_`date +"%Y%m%d"`.bak
```

**PostgreSQL**
```
PGPASSWORD="password" pg_dump [db_name] -h [server] -U [username] -f nextcloud-sqlbkp_`date +"%Y%m%d"`.bak
```
