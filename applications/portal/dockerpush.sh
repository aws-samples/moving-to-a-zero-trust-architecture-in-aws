#!/bin/bash

aws ecr get-login-password --region {REGION} | docker login --username AWS --password-stdin {ACCOUNT_ID}.dkr.ecr.{REGION}.amazonaws.com
docker build -t frontend .
docker tag frontend:latest {ACCOUNT_ID}.dkr.ecr.{REGION}.amazonaws.com/frontend:latest
docker push {ACCOUNT_ID}.dkr.ecr.{REGION}.amazonaws.com/frontend:latest