#!/bin/bash

aws ecr get-login-password --region eu-west-1 | docker login --username AWS --password-stdin 471112834120.dkr.ecr.eu-west-1.amazonaws.com
docker build -t frontend .
docker tag frontend:latest 471112834120.dkr.ecr.eu-west-1.amazonaws.com/frontend:latest
docker push 471112834120.dkr.ecr.eu-west-1.amazonaws.com/frontend:latest