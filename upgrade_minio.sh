#!/bin/bash

set -e # Exit immediately if a command exits with a non-zero status
NETWORK_NAME="docker_default"

echo "-*-* Create docker compose yml file *-*-"
cat >docker-compose.yml <<EOL
services:
  minio:
    image: minio/minio:latest
    container_name: minio_docker_container
    command: server /data --console-address ":9001"
    environment:
      MINIO_ROOT_USER: "minio_user"
      MINIO_ROOT_PASSWORD: "test_password_123"
    restart: always
    ports:
      - "9000:9000"   # API S3
      - "9001:9001"   # Dashboard Web MinIO
    networks:
      - docker_default
    volumes:
      - minio_data:/data
    
  createbuckets:
    image: minio/mc:latest
    depends_on:
      - minio
    networks:
      - docker_default
    entrypoint: >
      /bin/sh -c "
      until /usr/bin/mc alias set myminio http://minio:9000 minio_user test_password_123; do
        echo 'Waiting for MinIO...'
        sleep 2
      done;
      /usr/bin/mc mb myminio/pictures --ignore-existing;
      /usr/bin/mc anonymous set download myminio/pictures;
      echo 'Policy applied with success!';
      "

volumes:
  minio_data:

networks:
  docker_default:
    external: true
    name: docker_default
EOL

if docker network inspect "$NETWORK_NAME" >/dev/null 2>&1; then
  echo "Network '$NETWORK_NAME' already exists. Skipping creation."
else
  echo "Creating network '$NETWORK_NAME'..."
  docker network create "$NETWORK_NAME"
fi

echo "Creating new docker container"

docker compose -f docker-compose.yml up -d --force-recreate

echo "Delete docker compose file"
rm docker-compose.yml