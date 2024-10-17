#Get Endpoints Script

#!bin/bash
userpool=''

curl https://cognito-idp.us-east-1.amazonaws.com/$userpool/.well-known/openid-configuration | jq