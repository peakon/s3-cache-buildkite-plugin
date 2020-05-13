#!/usr/bin/env bash

until [[ "$(curl -s 'http://localhost:4566')" =~ "running" ]]; do
  echo -n '.'
  sleep 1
done
