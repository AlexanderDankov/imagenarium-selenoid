#!/bin/bash

docker buildx build --no-cache --platform linux/amd64,linux/arm64 -t imagenarium/selenoid:1.11.3 --push .
