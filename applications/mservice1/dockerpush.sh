#!/bin/bash

aws ecr get-login-password --region {REGION} | docker login --username AWS --password-stdin {ACCOUNT_ID}.dkr.ecr.{REGION}.amazonaws.com/mservice1
docker build -t frontend .
docker tag frontend:latest {ACCOUNT_ID}.dkr.ecr.{REGION}.amazonaws.com/mservice1:latest
docker push {ACCOUNT_ID}.dkr.ecr.{REGION}.amazonaws.com/mservice1:latest