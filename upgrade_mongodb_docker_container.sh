#!/bin/bash

set -e # Exit immediately if a command exits with a non-zero status
SERVICE_NAME="mongodb"
CONTAINER_NAME="mongodb_docker_container"
TEMPORARY_BACKUP_DIRECTORY_NAME="temp_mongodb_backup"
NETWORK_NAME="docker_default"

mkdir -p $TEMPORARY_BACKUP_DIRECTORY_NAME # Temporary directory to store backup and docker yml file

echo "-*-* Create docker compose yml file *-*-"
cat >$TEMPORARY_BACKUP_DIRECTORY_NAME/docker-compose.yml <<EOL
services:
  mongodb:
    image: mongodb/mongodb-atlas-local:latest
    container_name: mongodb_docker_container
    hostname: mongodb
    restart: always
    ports:
      - "27017:27017"
    networks:
      - docker_default
    volumes:
      - atlas_data:/data/db
      - atlas_config:/data/configdb
      - atlas_search_data:/data/mongot

volumes:
  atlas_data:
  atlas_config:
  atlas_search_data:

networks:
  docker_default:
    external: true
    name: docker_default
EOL

read -p "Create a new container (y) or upgrade and backup the existing one (N)? (y/N): " confirm
if [[ "$confirm" =~ ^[Yy]$ ]]; then
    echo "Creating new docker container"
else
    echo "-*-* Starting mongodb docker container upgrade *-*-"
    echo "Create backup inside docker container"
    docker exec $CONTAINER_NAME mongodump --uri="mongodb://localhost:27017/?directConnection=true" --out=/tmp/backup

    echo "Create a local copy of database from docker container"
    docker cp $CONTAINER_NAME:/tmp/backup $TEMPORARY_BACKUP_DIRECTORY_NAME/

    read -p "Check local folder now, and make sure the local copy of the backup is present! Starting to upgrade (and delete docker container)? (y/N): " confirm
    if [[ "$confirm" =~ ^[Yy]$ ]]; then
        echo "Stop docker container"
    else
        echo "User stopped database backup. EXIT!!"
        exit 0
    fi

    docker stop "$CONTAINER_NAME"

    echo "Remove old container"
    docker compose -f "$TEMPORARY_BACKUP_DIRECTORY_NAME/docker-compose.yml" down -v --rmi all

    echo "Recreate docker container with upgraded version"
fi

if docker network inspect "$NETWORK_NAME" >/dev/null 2>&1; then
  echo "Network '$NETWORK_NAME' already exists. Skipping creation."
else
  echo "Creating network '$NETWORK_NAME'..."
  docker network create "$NETWORK_NAME"
fi

docker compose -f $TEMPORARY_BACKUP_DIRECTORY_NAME/docker-compose.yml up -d --force-recreate

echo "Waiting for MongoDB to become PRIMARY and ready for writes..."
until docker exec mongodb_docker_container mongosh --quiet --eval "db.hello().isWritablePrimary" 2>/dev/null | grep -q "true"; do
    echo "MongoDB is still initializing, waiting..."
    sleep 2
done

echo "Copy local backup directory inside new created docker container"
docker cp $TEMPORARY_BACKUP_DIRECTORY_NAME/backup $CONTAINER_NAME:/tmp/backup

echo "Restore the backup"
docker exec $CONTAINER_NAME mongorestore --drop --uri="mongodb://localhost:27017/?directConnection=true" /tmp/backup

echo "Backup restored"
read -p "Check your database now. Delete backup files? (y/N): " confirm
if [[ "$confirm" =~ ^[Yy]$ ]]; then
    echo "Deleting local and container backup files"
    
    echo "Delete backup inside the container"
    docker exec mongodb_docker_container rm -rf /tmp/backup
    
    echo "Delete local backup folder"
    rm -rf $TEMPORARY_BACKUP_DIRECTORY_NAME
    
    echo "Cleanup complete!"
else
    echo "Cleanup skipped. Backup files retained."
    exit 0
fi

echo "Finished!"