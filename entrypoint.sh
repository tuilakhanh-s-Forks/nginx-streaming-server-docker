#!/bin/sh

nohup nginx -g "daemon off;" 2>&1 &
exec /usr/local/bin/server