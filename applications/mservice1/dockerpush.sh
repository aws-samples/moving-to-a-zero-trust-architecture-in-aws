#!/bin/bash

aws ecr get-login-password --region eu-west-1 | docker login --username AWS --password-stdin 992382807606.dkr.ecr.eu-west-1.amazonaws.com/mservice1
docker build -t frontend .
docker tag frontend:latest 992382807606.dkr.ecr.eu-west-1.amazonaws.com/mservice1:latest
docker push 992382807606.dkr.ecr.eu-west-1.amazonaws.com/mservice1:latest