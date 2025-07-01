#!/bin/bash

docker buildx build --platform linux/amd64,linux/arm64 -t imagenarium/selenoid-ui:1.10.11 --push .
